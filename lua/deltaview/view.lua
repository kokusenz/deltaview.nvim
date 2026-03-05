local M = {}
local utils = require('deltaview.utils')
local config = require('deltaview.config')

--- deltaview file diff buffer orchestrator, using delta.lua. opens a deltaview diff on top of current window
--- @param ref string|nil Optional git ref to compare against (defaults to HEAD). Can be branch, commit, tag, etc.
--- @return number | nil bufnr buf id of delta.lua buffer
M.deltaview_file = function(ref)
    local filepath = vim.fn.expand('%:p')
    local cur_bufnr = vim.api.nvim_get_current_buf()
    local cursor_placement = M.get_cursor_placement_current_buffer()
    local og_winline = vim.fn.winline()
    local diff_bufnr = M.open_git_diff_buffer(filepath, ref)
    if diff_bufnr == nil then
        return
    end
    M.place_cursor_delta_buffer_entry(diff_bufnr, 0, cursor_placement, og_winline)
    M.setup_hunk_navigation(diff_bufnr)
    local nav_back_and_place_cursor = M.get_delta_buffer_cursor_exit_strategy(diff_bufnr, 0, cur_bufnr)
    if nav_back_and_place_cursor == nil then
        return
    end

    vim.keymap.set('n', '<Esc>', nav_back_and_place_cursor, { buffer = diff_bufnr, noremap = true, silent = true })
    vim.keymap.set('n', 'q', nav_back_and_place_cursor, { buffer = diff_bufnr, noremap = true, silent = true })
end

--- opens a delta.lua git diff buffer for the specified file against a git ref, using Delta.text_diff
--- Handles both tracked and untracked files
--- @param filepath string The file path to diff
--- @param ref string|nil Optional git ref to compare against (defaults to HEAD). Can be branch, commit, tag, etc.
--- @param winnr number|nil Optional window number to open on.
--- @return number | nil bufnr buf id of delta.lua buffer
M.open_git_diff_buffer = function(filepath, ref, winnr)
    local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
    if vim.v.shell_error ~= 0 then
        vim.notify('Not in a git repository. Cannot open git diff delta.lua buffer.', vim.log.levels.WARN)
        return
    end
    assert(filepath ~= nil)
    if vim.fn.filereadable(filepath) == 0 then
        vim.notify('Not on a real file. Cannot open git diff delta.lua buffer.', vim.log.levels.WARN)
        return
    end

    local diff_result = vim.system({ 'git', 'diff', '-U0', '--', filepath }):wait()
    if diff_result.code ~= 0 and diff_result.code ~= 1 then
        vim.notify('Failed to run git diff - ' .. diff_result.stderr, vim.log.levels.ERROR)
        return
    end
    local diffstring = diff_result.stdout

    if diffstring == nil or diffstring == "" then
        vim.notify('No changes detected in current file', vim.log.levels.WARN)
        return
    end

    local parsed_git_data = Delta.parse.get_diff_data_git(diffstring)

    local file_lines = utils.read_file_lines(git_root .. '/' .. parsed_git_data[1].new_path)
    assert(file_lines ~= nil)
    local s2 = table.concat(file_lines, "\n")
    local s1 = ''

    if parsed_git_data[1].old_path then
        local show_result = vim.system({ 'git', 'show', (ref or 'HEAD') .. ':' .. parsed_git_data[1].old_path }):wait()
        if show_result.code ~= 0 and show_result.code ~= 1 then
            vim.notify('Failed to run git show - ' .. show_result.stderr, vim.log.levels.ERROR)
            return
        end
        s1 = show_result.stdout or ''
        -- there exists a trailing newline for some reason with git show
        s1 = s1:gsub('\n+$', '')
    end

    local bufnr = Delta.text_diff(s1, s2, parsed_git_data[1].language, { context = #file_lines })
    if bufnr == nil then
        return -- error already notified
    end

    vim.api.nvim_win_set_buf(winnr or 0, bufnr)
    Delta.highlight_delta_artifacts(bufnr)
    Delta.syntax_highlight_diff_set(bufnr)
    Delta.diff_highlight_diff(bufnr)
    if config.options.line_numbers then
        Delta.setup_delta_statuscolumn(bufnr)
    end

    local delta_files_data = vim.b[bufnr].delta_diff_data_set
    assert(delta_files_data ~= nil)
    --- @cast delta_files_data DiffData[]

    -- displays ref, filename, size of hunks
    local diff_buffer_name = filepath .. '    '
        .. config.viewconfig().vs .. ' ' .. ref .. '    '
        .. config.viewconfig().segment .. ' ' .. #parsed_git_data[1].hunks .. ' '

    vim.api.nvim_buf_set_name(bufnr, diff_buffer_name)

    --- for Delta.text_diff buffers, because of full file context, everything is one hunk. This is the data with theoretically 0 context, meaning each hunk is separate
    --- @type DiffData[]
    vim.b[bufnr].parsed_git_data = parsed_git_data
    return bufnr
end

--- Captures the current window and cursor position before opening a diff buffer
--- Call this before open_delta_lua_git_diff, then pass the result to place_cursor_in_diff_buffer
--- @return CursorPlacement snapshot of the current window and cursor; [1] is row, [2] is col
M.get_cursor_placement_current_buffer = function()
    local winnr = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(winnr)
    return { winnr = winnr, cursor = cursor }
end

--- finds the line in the delta.lua buffer that corresponds to the real file to place the cursor at.
--- @param bufnr number buf_id of delta.lua buffer id
--- @param winnr number win id of delta.lua window id
--- @param cursor_placement CursorPlacement if filepath is not specified, they will try to place the cursor on the first file of the diff. If the delta.lua buffer does not have filepath, but you know the file your cursor was on matches with the delta.lua file, use filepath = nil.
--- @param og_winline number winline of the cursor in the source buffer, used to preserve relative screen position in the diff buffer
M.place_cursor_delta_buffer_entry = function(bufnr, winnr, cursor_placement, og_winline)
    local delta_diff_data_set = vim.b[bufnr].delta_diff_data_set
    assert(delta_diff_data_set ~= nil)
    --- @cast delta_diff_data_set DiffData[]

    for _, diff_data in ipairs(delta_diff_data_set) do
        -- when using Delta.text_diff, there is no filepath in diff_data to compare to.
        -- in the interest of making this usable with Delta.text_diff, we do a fail open (if we can't find a filepath, we try to do a cursor placement anyways)
        if cursor_placement.filepath == nil or diff_data.new_path == cursor_placement.filepath then
            for _, hunk in ipairs(diff_data.hunks) do
                for _, line in ipairs(hunk.lines) do
                    if line.new_line_num == cursor_placement.cursor[1] then
                        local target_lnum = line.formatted_diff_line_num + 1
                        M.set_restview(winnr, og_winline, target_lnum, cursor_placement.cursor[2])
                        return
                    end
                end
            end
            -- fallback: just place at top of first hunk of matched filepath
            local success, err = pcall(function()
                vim.api.nvim_win_set_cursor(winnr, { diff_data.hunks[1].lines[1].formatted_diff_line_num + 1, 0 })
            end)
            if not success then
                vim.notify('Failed to place cursor.' .. tostring(err), vim.log.levels.ERROR)
            end
            return
        end
    end
    vim.notify("Corresponding cursor location or filepath could not be found. Cursor will not be placed.",
        vim.log.levels.WARN)
end

--- @type CursorPlacement | nil
M.cursor_placement = nil -- module level upvalue, reusable in multiple module scoped functions


--- Populates the module level upvalue to track the cursor in the delta diff buffer
--- @param bufnr number
--- @param winnr number
M.setup_cursor_placement_tracking = function(bufnr, winnr)
    local delta_diff_data_set = vim.b[bufnr].delta_diff_data_set
    assert(delta_diff_data_set ~= nil)
    --- @cast delta_diff_data_set DiffData[]

    --- @type table<number, CursorLookupEntry | false>
    local row_lookup = {}
    for _, diff_data in ipairs(delta_diff_data_set) do
        for _, hunk in ipairs(diff_data.hunks) do
            for _, line in ipairs(hunk.lines) do
                if line.new_line_num ~= nil then
                    row_lookup[line.formatted_diff_line_num + 1] = {
                        new_line_num = line.new_line_num,
                        filepath = diff_data.new_path or nil,
                    }
                else
                    row_lookup[line.formatted_diff_line_num + 1] = false
                end
            end
        end
    end

    local populate_cursor_placement = function()
        local pos = vim.api.nvim_win_get_cursor(0)
        local current_row = pos[1]
        local current_col = pos[2]

        local entry = row_lookup[current_row]
        if entry == nil then
            -- not yet cached — row is not a diff line
            row_lookup[current_row] = false
            M.cursor_placement = nil
            return
        end

        if entry == false then
            M.cursor_placement = nil
            return
        end

        M.cursor_placement = {
            winnr = winnr,
            cursor = { entry.new_line_num, current_col },
            filepath = entry.filepath,
        }
    end

    populate_cursor_placement()

    vim.api.nvim_create_autocmd('CursorMoved', {
        buffer = bufnr,
        callback = populate_cursor_placement
    })
end

--- returns a function that, when invoked, opens the file to and places the cursor where the cursor was in the diff buffer. The function can fail if the cursor is not in a valid location.
--- @param bufnr number buf_id of delta.lua buffer id
--- @param winnr number win id of the buffer we are exiting to
--- @param alternative_bufnr number | nil buf_id of the buffer id to exit to. If given, is used.
--- @return nil | fun(): boolean strategy strategy function returns a boolean when executed if the window succcessfully exited to anotherb uffer and if the cursor was successfully placed. If used on a Delta.text_diff or Delta.patch_diff buffer, will not redirect to any filepath given by the buffer, so would prefer to have alternative_bufnr. If used on a Delta.git_diff buffer where the filepath is displayed, it will navigate to that before placing the cursor
M.get_delta_buffer_cursor_exit_strategy = function(bufnr, winnr, alternative_bufnr)
    M.setup_cursor_placement_tracking(bufnr, winnr)

    return function()
        if M.cursor_placement == nil then
            return false
        end
        local og_winline = vim.fn.winline()

        if alternative_bufnr ~= nil then
            local success, err = pcall(function()
                vim.api.nvim_set_current_buf(alternative_bufnr)
            end)
            if not success then
                vim.notify('Failed to navigate to alternative buffer' .. tostring(err), vim.log.levels.ERROR)
                return false
            end
            goto place_cursor
        end

        if M.cursor_placement.filepath ~= nil then
            local success, err = pcall(function()
                vim.cmd('e ' .. vim.fn.fnameescape(M.cursor_placement.filepath))
            end)
            if not success then
                vim.notify('Failed to open file: ' .. M.cursor_placement.filepath .. ' - ' .. tostring(err),
                    vim.log.levels.ERROR)
                return false
            end
        end

        ::place_cursor::
        M.set_restview(winnr, og_winline, M.cursor_placement.cursor[1], M.cursor_placement.cursor[2])
        M.cursor_placement = nil
        return true
    end
end

--- sets the view state while maintaining the cursor position relative to the top of the window. Accounts for new line wrapping.
--- @param winnr number
--- @param og_winline number original distance between cursor and top of window
--- @param target_row number row of where cursor should be placed
--- @param target_col number col of where the cursor should be placed
M.set_restview = function(winnr, og_winline, target_row, target_col)
    local success, err = pcall(function()
        vim.api.nvim_win_call(winnr, function()
            vim.api.nvim_win_set_cursor(winnr, { target_row, target_col })
            vim.cmd('normal! zb')

            local topline = target_row

            -- accounting for the cursor being on a wrapped screen line within target_row.
            local sp_cursor_line_start = vim.fn.screenpos(winnr, target_row, 1)
            local sp_cursor = vim.fn.screenpos(winnr, target_row, math.max(1, target_col + 1)) -- col is 1-based
            local cursor_line_offset = (sp_cursor_line_start.row ~= 0 and sp_cursor.row ~= 0)
                and (sp_cursor.row - sp_cursor_line_start.row)
                or 0
            local screen_lines_walked = 1 + cursor_line_offset

            while screen_lines_walked < og_winline and topline > 1 do
                local next_topline = topline - 1
                local line_end_col = math.max(1, vim.fn.col({ next_topline, '$' }) - 1) -- col is 1-based
                local sp_start = vim.fn.screenpos(winnr, next_topline, 1)
                local sp_end = vim.fn.screenpos(winnr, next_topline, line_end_col)
                if sp_start.row == 0 or sp_end.row == 0 then
                    -- there is a bug when this function is called with the cursor on the very last row.
                    -- if you put print statements here, you will observe that sp_start and sp_end return 0
                    -- values when the cursor starts on the last row, and it tries to calculate for the
                    -- second to last row. Root cause is completely unknown.
                    break
                end
                topline = next_topline
                screen_lines_walked = screen_lines_walked + (sp_end.row - sp_start.row + 1)
            end
            vim.fn.winrestview({
                topline = topline,
                lnum = target_row,
                col = target_col,
            })
        end)
    end)
    if not success then
        vim.notify('Failed to place cursor. ' .. tostring(err), vim.log.levels.ERROR)
    end
end

--- @param bufnr number
M.setup_hunk_navigation = function(bufnr)
    local delta_diff_data_set = vim.b[bufnr].delta_diff_data_set
    assert(delta_diff_data_set ~= nil)
    --- @cast delta_diff_data_set DiffData[]

    -- TODO known bug when cursor on an added line, cannot jump to next hunk if next hunk is also added line
    vim.keymap.set('n', config.options.keyconfig.next_hunk, function()
        local cursor_placement = M.get_cursor_placement_current_buffer()
        for _, diff_data in ipairs(delta_diff_data_set) do
            -- delta_diff_data_set only has 1 hunk, because of unlimited context
            local lines = diff_data.hunks[1].lines
            for i = 1, #lines, 1 do
                local real_buf_line = lines[i]
                -- we are using the fact that a hunk does not have both old and new line number to identify hunks
                -- instead of using the deserialized vim.b[bufnr].parsed_git_data
                if (real_buf_line.new_line_num == nil and
                        real_buf_line.old_line_num ~= nil and
                        lines[cursor_placement.cursor[1]].new_line_num ~= nil
                    ) or
                    (real_buf_line.new_line_num ~= nil and
                        real_buf_line.old_line_num == nil and
                        lines[cursor_placement.cursor[1]].old_line_num ~= nil
                    )
                then
                    if i > cursor_placement.cursor[1] then
                        local og_winline = vim.fn.winline()
                        M.set_restview(0, og_winline, real_buf_line.formatted_diff_line_num + 1, 1)
                        vim.api.nvim_echo({ { 'TODO: print hunk / total hunks', 'Normal' } }, false, {})
                        return
                    end
                end
            end
        end
    end, { buffer = bufnr, silent = true })

    vim.keymap.set('n', config.options.keyconfig.prev_hunk, function()
        local cursor_placement = M.get_cursor_placement_current_buffer()
        for _, diff_data in ipairs(delta_diff_data_set) do
            -- delta_diff_data_set only has 1 hunk, because of unlimited context
            local lines = diff_data.hunks[1].lines
            for i = #lines, 1, -1 do
                local real_buf_line = lines[i]
                -- we are using the fact that a hunk does not have both old and new line number to identify hunks
                -- instead of using the deserialized vim.b[bufnr].parsed_git_data
                if (real_buf_line.new_line_num == nil and
                        real_buf_line.old_line_num ~= nil and
                        lines[cursor_placement.cursor[1]].new_line_num ~= nil
                    ) or
                    (real_buf_line.new_line_num ~= nil and
                        real_buf_line.old_line_num == nil and
                        lines[cursor_placement.cursor[1]].old_line_num ~= nil
                    )
                then
                    if i < cursor_placement.cursor[1] then
                        local og_winline = vim.fn.winline()
                        M.set_restview(0, og_winline, real_buf_line.formatted_diff_line_num + 1, 1)
                        vim.api.nvim_echo({ { 'TODO: print hunk / total hunks', 'Normal' } }, false, {})
                        return
                    end
                end
            end
        end
    end, { buffer = bufnr, silent = true })
end


return M

--- @alias CursorPlacement { winnr: number, filepath: string | nil, cursor: number[] }

--- @class CursorLookupEntry
--- @field new_line_num number
--- @field filepath string | nil
