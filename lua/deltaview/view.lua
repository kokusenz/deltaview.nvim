local M = {}
local utils = require('deltaview.utils')

--- deltaview file diff buffer orchestrator, using delta.lua. opens a deltaview diff on top of current window
--- @param ref string|nil Optional git ref to compare against (defaults to HEAD). Can be branch, commit, tag, etc.
--- @return number | nil bufnr buf id of delta.lua buffer
M.deltaview_file = function(ref)
    local filepath = vim.fn.expand('%:p')
    local cur_buf = vim.api.nvim_get_current_buf()
    local cursor_placement = M.get_cursor_placement_current_buffer()
    local diff_bufnr = M.open_git_diff_buffer(filepath, ref)
    if diff_bufnr == nil then
        return
    end
    M.place_cursor_delta_buffer(diff_bufnr, 0, cursor_placement)
    local place_cursor = M.get_delta_buffer_cursor_exit_strategy(diff_bufnr, 0)
    if place_cursor == nil then
        return
    end
    -- TODO create exit keybinds, where if invoked, bring the user back to cur_buf, and then calls place_cursor()
    -- in this entire flow of this orchestrator function, completely safe to assume vim.text.diff
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
        vim.notify('Not in a git repository', vim.log.levels.WARN)
        return
    end

    if filepath == nil then
        vim.notify('ERROR: filepath is nil', vim.log.levels.WARN)
        return
    end

    if vim.fn.filereadable(filepath) == 0 then
        print('ERROR: not a valid file.')
        return
    end

    local diff_result = vim.system({ 'git', 'diff', '-U0', '--', filepath }):wait()
    if diff_result.code ~= 0 and diff_result.code ~= 1 then
        vim.notify('Failed to run git diff', vim.log.levels.ERROR)
        return
    end
    local diffstring = diff_result.stdout

    if diffstring == nil or diffstring == "" then
        vim.notify('No changes detected in current file', vim.log.levels.WARN)
        return
    end

    local data = Delta.parse.get_diff_data_git(diffstring)[1]

    local file_lines = utils.read_file_lines(git_root .. '/' .. data.new_path)
    if file_lines == nil then
        vim.notify('ERROR: couldnt read file', vim.log.levels.WARN)
        return
    end
    local s2 = table.concat(file_lines, "\n")
    local s1 = ''

    if data.old_path then
        local show_result = vim.system({ 'git', 'show', (ref or 'HEAD') .. ':' .. data.old_path }):wait()
        if show_result.code ~= 0 then
            vim.notify('Failed to run git show', vim.log.levels.ERROR)
            return
        end
        s1 = show_result.stdout or ''
    end

    local bufnr = Delta.text_diff(s1, s2, data.language, { context = #file_lines })
    if bufnr == nil then
        return -- error already notified
    end

    vim.api.nvim_win_set_buf(winnr or 0, bufnr)
    Delta.highlight_delta_artifacts(bufnr)
    Delta.syntax_highlight_diff_set(bufnr)
    Delta.diff_highlight_diff(bufnr)
    Delta.setup_delta_statuscolumn(bufnr)
    return bufnr
    -- what else left to do: hunk navigation, and the enter cursor placement, and the exit cursor placement
    -- hunk navigation can be done as long as I have the buf number and diff info (in buffer), i can just use set_cursor
    -- enter cursor can be done as long as I have the buf id of delta.lua buffer and original buf id (can be found at callsite)
    -- exit cursor can be done via tracking where cursor is via cursormoved autocmd, then make a bufleave autocmd that sets it.
end

--- Captures the current window and cursor position before opening a diff buffer
--- Call this before open_delta_lua_git_diff, then pass the result to place_cursor_in_diff_buffer
--- @return CursorPlacement snapshot of the current window and cursor; [1] is row, [2] is col
M.get_cursor_placement_current_buffer = function()
    local winnr = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(winnr)
    return { winnr = winnr, cursor = cursor }
end

--- finds the corresponding line in the delta.lua buffer to place the cursor at.
--- @param bufnr number buf_id of delta.lua buffer id
--- @param winnr number win id of delta.lua window id
--- @param cursor_placement CursorPlacement if filepath is not specified, they will try to place the cursor on the first file of the diff. If the delta.lua buffer does not have filepath, but you know the file your cursor was on matches with the delta.lua file, use filepath = nil.
M.place_cursor_delta_buffer = function(bufnr, winnr, cursor_placement)
    local delta_files_data = vim.b[bufnr].delta_diff_data_set

    if delta_files_data == nil then
        vim.notify("Buffer did not contain delta diff data. Cursor will not be placed.", vim.log.levels.WARN)
        return
    end
    --- @cast delta_files_data DiffData[]

    for _, diff_data in ipairs(delta_files_data) do
        -- when using Delta.text_diff, there is no filepath in diff_data to compare to.
        -- in the interest of making this usable with Delta.text_diff, we do a fail open (if we can't find a filepath, we try to do a cursor placement anyways)
        if cursor_placement.filepath == nil or diff_data.new_path == cursor_placement.filepath then
            for _, hunk in ipairs(diff_data.hunks) do
                for _, line in ipairs(hunk.lines) do
                    if line.new_line_num == cursor_placement.cursor[1] then
                        vim.api.nvim_win_set_cursor(winnr,
                            { line.formatted_diff_line_num + 1, cursor_placement.cursor[2] })
                        return
                    end
                end
            end
            -- fallback: just place at top of first hunk of matched filepath
            vim.api.nvim_win_set_cursor(winnr, { diff_data.hunks[1].lines[1].formatted_diff_line_num + 1, 0 })
            return
        end
    end
    vim.notify("Corresponding cursor location or filepath could not be found. Cursor will not be placed.", vim.log.levels.WARN)
end

--- returns a function that, when invoked, opens the file to and places the cursor where the cursor was in the diff buffer. The function can fail if the cursor is not in a valid location.
--- @param bufnr number buf_id of delta.lua buffer id
--- @param winnr number win id of the buffer we are exiting to
--- @return function | nil place_cursor returns boolean whether the cursor was successfully placed. If used on a Delta.text_diff or Delta.patch_diff buffer, will not redirect to any filepath. If used on a Delta.git_diff buffer, will go to the filepath at the top
M.get_delta_buffer_cursor_exit_strategy = function(bufnr, winnr)
    local delta_files_data = vim.b[bufnr].delta_diff_data_set

    if delta_files_data == nil then
        vim.notify("Buffer did not contain delta diff data. Cursor exit autocmds will not be declared.", vim.log.levels.WARN)
        return
    end
    --- @cast delta_files_data DiffData[]

    --- @type CursorPlacement | nil
    local cursor_placement = nil

    --- @class CursorLookupEntry
    --- @field new_line_num number
    --- @field filepath string | nil

    --- @type table<number, CursorLookupEntry | false>
    local row_lookup = {}
    for _, diff_data in ipairs(delta_files_data) do
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

    vim.api.nvim_create_autocmd('CursorMoved', {
        buffer = bufnr,
        callback = function()
            local pos = vim.api.nvim_win_get_cursor(0)
            local current_row = pos[1]
            local current_col = pos[2]

            local entry = row_lookup[current_row]
            if entry == nil then
                -- not yet cached — row is not a diff line
                row_lookup[current_row] = false
                cursor_placement = nil
                return
            end

            if entry == false then
                cursor_placement = nil
                return
            end

            cursor_placement = {
                winnr = winnr,
                cursor = { entry.new_line_num, current_col },
                filepath = entry.filepath,
            }
        end
    })

    return function()
        if cursor_placement == nil then
            return false
        end

        if cursor_placement.filepath ~= nil then
            local success, err = pcall(function()
                vim.cmd('e ' .. vim.fn.fnameescape(cursor_placement.filepath))
            end)
            if not success then
                vim.notify('ERROR: Failed to open file: ' .. cursor_placement.filepath .. ' - ' .. tostring(err), vim.log.levels.ERROR)
                return false
            end
        end

        vim.api.nvim_win_set_cursor(cursor_placement.winnr, cursor_placement.cursor)
        return true
    end
end

return M

--- @alias CursorPlacement { winnr: number, filepath: string | nil, cursor: number[] }
