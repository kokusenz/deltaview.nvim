local M = {}
local selector = require('deltaview.selector')
local utils = require('deltaview.utils')

--- create an interactive menu pane for selecting and viewing diffs of modified files
--- @param diffing_function function Function to call for displaying diffs, receives (filepath, ref)
--- @param ref string|nil Optional git ref to compare against (defaults to HEAD). Can be branch, commit, tag, etc.
M.create_diff_menu_pane = function(diffing_function, ref)
    if diffing_function == nil then
        print('ERROR: must declare a function to diff the file')
        return
    end

    local mods = utils.get_diffed_files(ref)
    if #mods == 0 then
        print('No diffs to display')
        return
    end
    -- TODO: allow integration with fzf-lua and telescope pickers. opt into it with opts. Custom picker as a fallback
    selector.ui_select(mods, {
        prompt = 'Modified Files',
        label_item = utils.label_filepath_item,
        win_predefined = 'hsplit',
    }, function(filepath, selected_idx)
        if filepath == nil then
            return
        end
        local success, err = pcall(function()
            vim.cmd('e ' .. vim.fn.fnameescape(filepath))
        end)
        if not success then
            print('ERROR: Failed to open file: ' .. filepath .. ' - file may have been removed.')
            return
        end

        M.diffed_files.files = mods
        M.diffed_files.cur_idx = selected_idx
        diffing_function(filepath, ref)
    end)
end

--- select from diff menu programmatically
--- @param diffing_function function function to call for displaying diffs, receives (filepath, ref)
--- @param filepath string filepath selected
--- @param ref string|nil optional git ref to compare against (defaults to HEAD). Can be branch, commit, tag, etc.
M.programmatically_select_diff_from_menu = function(diffing_function, filepath, ref)
    if diffing_function == nil then
        print('ERROR: must declare a function to diff the file')
        return
    end

    if filepath == nil then
        return
    end

    local mods = utils.get_diffed_files(ref)
    if #mods == 0 then
        print('No diffs to display')
        return
    end

    for key, value in ipairs(mods) do
        if value == filepath then
            M.diffed_files.files = mods
            M.diffed_files.cur_idx = key
        end
    end

    local success, err = pcall(function()
        vim.cmd('e ' .. vim.fn.fnameescape(filepath))
    end)
    if not success then
        print('ERROR: Failed to open file: ' .. filepath .. ' - file may have been removed.')
        return
    end
    diffing_function(filepath, ref)
end

--- Run a git diff for the specified file against a git ref
--- Handles both tracked and untracked files
--- @param filepath string The file path to diff
--- @param ref string|nil Optional git ref to compare against (defaults to HEAD). Can be branch, commit, tag, etc.
M.run_diff_against = function(filepath, ref)
    local is_diffable = utils.is_diffable_filepath(filepath)
    if is_diffable == false then
        print('WARNING: cannot run diff on a directory')
        return
    end
    -- check if file is tracked to determine which git diff command to use
    local is_tracked = vim.fn.system({ 'git', 'ls-files', '--', filepath })
    if vim.v.shell_error ~= 0 then
        print('ERROR: Failed to check if file is tracked')
        return
    end

    local cmd
    local hunk_cmd

    if is_tracked == '' or is_tracked == '\n' then
        -- untracked file
        cmd = 'git diff -U3000 --no-index /dev/null ' .. vim.fn.shellescape(filepath)
        hunk_cmd = 'git diff -U0 --no-index /dev/null ' .. vim.fn.shellescape(filepath)
    else
        -- tracked file
        local modified_files = vim.fn.system({ 'git', 'diff', ref ~= nil and ref or 'HEAD', '--name-only', '--', filepath })
        if vim.v.shell_error ~= 0 then
            print('ERROR: Failed to get modified files from git')
            return
        end
        if modified_files ~= nil and modified_files ~= '' then
            -- note that due to hard coded context ceiling (found no viable alternative), files above 3000 lines might not show all lines
            cmd = 'git diff -U3000 ' .. (ref ~= nil and ref or 'HEAD') .. ' -- ' .. vim.fn.shellescape(filepath)
            hunk_cmd = 'git diff -U0 ' .. (ref ~= nil and ref or 'HEAD') .. ' -- ' .. vim.fn.shellescape(filepath)
        end
    end

    if cmd == nil then
        print('WARNING: file is not modified. No diff to display')
        return
    end

    -- dry run: test commands, terminate early if fail
    local test_output = vim.fn.system(cmd)
    local exit_code = vim.v.shell_error
    if exit_code ~= 0 and exit_code ~= 1 then
        print('ERROR: git diff failed (exit ' .. exit_code .. '): ' .. vim.trim(test_output))
        return
    end

    test_output = vim.fn.system(hunk_cmd)
    exit_code = vim.v.shell_error
    if exit_code ~= 0 and exit_code ~= 1 then
        print('ERROR: git diff failed (exit ' .. exit_code .. '): ' .. vim.trim(test_output))
        return
    end

    local cmd_ui = {}
    local diff_target_message = M.viewconfig.vs .. ' ' .. (M.diff_target_ref or 'HEAD')
    utils.append_cmd_ui(cmd_ui, diff_target_message, true)

    local adjacent_files = utils.get_adjacent_files(M.diffed_files)
    if adjacent_files ~= nil then
        local next_diff_message = (M.show_verbose_nav and (vim.fn.fnamemodify(adjacent_files.prev.name, ':t') .. ' ' .. M.viewconfig.prev) or '') ..
            ' [' .. M.diffed_files.cur_idx .. '/' .. #M.diffed_files.files .. '] ' .. M.viewconfig.next .. ' ' ..
            vim.fn.fnamemodify(adjacent_files.next.name, ':t')
        utils.append_cmd_ui(cmd_ui, next_diff_message, false)
    end

    local diff_buffer_funcs = M.display_diff_followcursor(cmd)
    M.setup_hunk_navigation(hunk_cmd, diff_buffer_funcs, cmd_ui)
end

--- display git diff output in a terminal buffer with cursor position syncing
--- creates a terminal buffer running delta, syncs cursor position between source and diff
--- @param cmd string The git diff command to execute
--- @return table DiffBufferFuncs some exposed functionality to be able to interact with created terminal bufer
M.display_diff_followcursor = function(cmd)
    local delta_cmd = cmd .. ' | delta --line-numbers --paging=never | sed "1,7d"'

    -- get previous cursor state
    vim.cmd('normal! zz')
    local cur_buf = vim.api.nvim_get_current_buf()
    local cur_cursor_pos = vim.api.nvim_win_get_cursor(0) -- output {row, column}, 1-indexed
    local cur_line = vim.api.nvim_get_current_line()

    local term_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = term_buf })

    vim.api.nvim_buf_set_var(term_buf, 'is_deltaview', true)

    vim.api.nvim_set_current_buf(term_buf)

    local last_valid_currentdiff_cursor_pos
    local move_to_line
    --- @param line number # target line number to move to; moves to line post diff, not pre diff
    local move_to_line_wrapper = function(line)
        if move_to_line ~= nil then
            move_to_line(line)
        else
            print('WARNING: move_to_line has not been initialized. No action will be performed')
        end
    end

    vim.fn.jobstart(delta_cmd, {
        term = true,
        on_exit = function()
            vim.schedule(function()
                -- place cursor upon entry
                local diff_buf_lines = vim.api.nvim_buf_get_lines(term_buf, 0, -1, false)
                for key, value in ipairs(diff_buf_lines) do
                    if string.match(value, '⋮%s+' .. cur_cursor_pos[1]) ~= nil then
                        local success, err = pcall(function()
                            if cur_line == '' or cur_line == nil then
                                vim.api.nvim_win_set_cursor(0, { key, #value })
                                last_valid_currentdiff_cursor_pos = { key, #value }
                            else
                                vim.api.nvim_win_set_cursor(0, { key, cur_cursor_pos[2] + (#value - #cur_line) })
                                last_valid_currentdiff_cursor_pos = { key, cur_cursor_pos[2] + (#value - #cur_line) }
                            end
                            vim.cmd('normal! zz')
                        end)
                        if not success then
                            -- Cursor position might be out of bounds, set to safe default
                            vim.api.nvim_win_set_cursor(0, { key, 0 })
                            last_valid_currentdiff_cursor_pos = { key, 0 }
                        end
                        break
                    end
                end

                -- update where cursor should be upon exit
                vim.api.nvim_create_autocmd('CursorMoved', {
                    buffer = term_buf,
                    callback = function()
                        local term_buf_cur_line = vim.api.nvim_get_current_line()
                        local term_buf_cur_cursor_pos = vim.api.nvim_win_get_cursor(0)
                        local matching_line_number = string.match(term_buf_cur_line, '⋮%s+(%d+)')
                        local git_delta_linenumber_artifacts = string.match(term_buf_cur_line, '(.*│)')
                        if matching_line_number ~= nil then
                            last_valid_currentdiff_cursor_pos = { tonumber(matching_line_number), math.max(
                                term_buf_cur_cursor_pos[2] - string.len(git_delta_linenumber_artifacts), 0) }
                        end
                    end
                })

                -- expose functions to interact with term buffer

                --- @param line number # target line number to move to; moves to line post diff, not pre diff
                move_to_line = function(line)
                    for key, value in ipairs(diff_buf_lines) do
                        if string.match(value, '⋮%s+' .. line .. '%s*│') ~= nil then
                            local success, err = pcall(function()
                                vim.api.nvim_win_set_cursor(0, { key, 0 })
                                vim.cmd('normal! zz')
                            end)
                            if not success then
                                print('ERROR: Failed to move cursor to line ' .. line)
                            end
                            return
                        end
                    end
                end
            end)
        end
    })

    vim.api.nvim_buf_set_name(term_buf, cmd)

    local return_to_cur_buffer = function()
        local success, err = pcall(function()
            vim.api.nvim_set_current_buf(cur_buf)
            if last_valid_currentdiff_cursor_pos ~= nil then
                vim.api.nvim_win_set_cursor(0,
                    { last_valid_currentdiff_cursor_pos[1], last_valid_currentdiff_cursor_pos[2] })
            end
            vim.cmd('normal! zz')
        end)
        if not success then
            print('ERROR: Failed to return to original buffer')
        end
    end

    vim.keymap.set('n', '<Esc>', function()
        return_to_cur_buffer()
    end, { buffer = term_buf, noremap = true, silent = true })

    vim.keymap.set('n', 'q', function()
        return_to_cur_buffer()
    end, { buffer = term_buf, noremap = true, silent = true })

    if M.dv_toggle_keybind ~= nil and M.dv_toggle_keybind ~= '' then
        vim.keymap.set('n', M.dv_toggle_keybind, function()
            return_to_cur_buffer()
        end, { buffer = term_buf, noremap = true, silent = true })
    end

    local adjacent_files = utils.get_adjacent_files(M.diffed_files)
    if adjacent_files ~= nil then
        vim.keymap.set('n', M.keyconfig.next_diff, function()
            return_to_cur_buffer()
            M.programmatically_select_diff_from_menu(M.run_diff_against, adjacent_files.next.name, M.diff_target_ref)
        end, { buffer = term_buf, noremap = true, silent = true })

        vim.keymap.set('n', M.keyconfig.prev_diff, function()
            return_to_cur_buffer()
            M.programmatically_select_diff_from_menu(M.run_diff_against, adjacent_files.prev.name, M.diff_target_ref)
        end, { buffer = term_buf, noremap = true, silent = true })
    end

    --- @class DiffBufferFuncs table to expose functions to interact with the diff buffer
    --- @field move_to_line function
    --- @field buf_id number
    local funcs = { buf_id = term_buf, move_to_line = move_to_line_wrapper }
    return funcs
end

--- sets up hunk navigation for the buffer the diff is displayed on. keymaps for moving between hunks, visual indicator for hunk progress
--- @param hunk_cmd string a git diff command with 0 context to be able to properly parse for hunks
--- @param diff_buffer_funcs DiffBufferFuncs
--- @param cmd_ui table the existing cmd ui to append to
M.setup_hunk_navigation = function(hunk_cmd, diff_buffer_funcs, cmd_ui)
    local output = vim.fn.system(hunk_cmd)
    if vim.v.shell_error ~= 0 and vim.v.shell_error ~= 1 then
        print('ERROR: Failed to get hunks from git diff')
        return
    end

    local matches = {}
    for line_after in string.gmatch(output, '@@ %-%d+,?%d* %+(%d+),?%d* @@') do
        table.insert(matches, tonumber(line_after))
    end

    local cur_line_number = tonumber(1)
    local cur_prev_line_number = nil

    local update_cur_line_number = function()
        local term_buf_cur_line = vim.api.nvim_get_current_line()
        local before_line_number = string.match(term_buf_cur_line, '%s*(%d+)%s*⋮')
        local after_line_number = string.match(term_buf_cur_line, '⋮%s+(%d+)')
        cur_prev_line_number = tonumber(before_line_number)
        -- both cur_prev_line_number and cur_line_number should not be nil at the same time.
        -- fallback: if cur_prev_line_number is nil, then avoid updating cur_line_number if after_line_number also nil
        if cur_prev_line_number == nil then
            if tonumber(after_line_number) ~= nil then
                cur_line_number = tonumber(after_line_number)
            end
        else
            cur_line_number = tonumber(after_line_number)
        end
    end

    local get_line_number_before_negative_hunk = function()
        if cur_line_number == nil and cur_prev_line_number ~= nil then
            local diff_buf_lines = vim.api.nvim_buf_get_lines(diff_buffer_funcs.buf_id, 0, -1, false)
            local last_after_line_number = tonumber(1)
            for _, value in ipairs(diff_buf_lines) do
                local before_line_number = string.match(value, '%s*(%d+)%s*⋮')
                local after_line_number = string.match(value, '⋮%s+(%d+)')
                if tonumber(after_line_number) ~= nil then
                    last_after_line_number = tonumber(after_line_number)
                end
                if tonumber(before_line_number) == cur_prev_line_number then
                    return last_after_line_number
                end
            end
        end
        return nil
    end

    --- hunk progress indicator
    local render_hunk_progress_cmd_ui = function()
        local cur_hunk = 1
        for i = 1, #matches + 1, 1 do
            if i == #matches + 1 or (matches[i] > (cur_line_number or get_line_number_before_negative_hunk())) then
                cur_hunk = i
                break
            end
        end

        if cur_hunk == 1 then
            utils.display_cmd_ui(cmd_ui, M.viewconfig.dot:rep(#matches))
        else
            local left = cur_hunk - 2
            local right = #matches - (cur_hunk - 1)
            utils.display_cmd_ui(cmd_ui, M.viewconfig.dot:rep(left) .. M.viewconfig.circle .. M.viewconfig.dot:rep(right))
        end
    end

    vim.api.nvim_create_autocmd('CursorMoved', {
        buffer = diff_buffer_funcs.buf_id,
        callback = function()
            update_cur_line_number()
            render_hunk_progress_cmd_ui()
        end
    })

    vim.api.nvim_create_autocmd('BufLeave', {
        buffer = diff_buffer_funcs.buf_id,
        callback = function()
            -- clear cmd_ui
            vim.cmd('echo ""')
        end
    })

    vim.keymap.set('n', M.keyconfig.next_hunk, function()
        for i = 1, #matches, 1 do
            local line = matches[i]
            if (cur_line_number or get_line_number_before_negative_hunk()) < line then
                diff_buffer_funcs.move_to_line(line)
                return
            end
        end
        -- if we couldn't find a hunk (eg. we are past the last hunk) loop back around to the first hunk
        diff_buffer_funcs.move_to_line(matches[1])
    end, { buffer = diff_buffer_funcs.buf_id, noremap = true, silent = true })

    vim.keymap.set('n', M.keyconfig.prev_hunk, function()
        for i = #matches, 1, -1 do
            local line = matches[i]
            if (cur_line_number or get_line_number_before_negative_hunk()) > line then
                diff_buffer_funcs.move_to_line(line)
                return
            end
        end
        -- if we couldn't find a hunk (eg. we are before the first hunk) loop back around to the last hunk
        diff_buffer_funcs.move_to_line(matches[#matches])
    end, { buffer = diff_buffer_funcs.buf_id, noremap = true, silent = true })
end

M.setup = function(opts)
    -- considerations for opts:
    -- set toggle keybind, (we should make DeltaView toggle by default, guess that's a todo)
    -- use fzf_lua picker or telescope picker
    -- control whether dmenu uses number labels or letter labels
    --     consider for dmenu sorting; we can go by diff loc size to begin with, but maybe even consider treesitter integration
    --     for loc, we should go first is top loc (ignoring test files), but then everything in that directory no matter loc
    --     if we go with dmenu goes away immediately after opening a diff, we show a cmd_ui that hints that we can do <C-n> or something to go to the next diff on the list...

    --- @class DeltaViewOpts
    --- @field dv_toggle_keybind string | nil if defined, will create keybind that runs DeltaView, and exits Diff buffer if open
    --- @field dm_toggle_keybind string | nil if defined, will create keybind that runs DeltaMenu
    --- @field use_nerdfonts boolean | nil
    --- @field keyconfig KeyConfig | nil
    --- @field show_verbose_nav boolean | nil Show both prev and next filenames (true) or just position + next (false, default)
    opts = opts or {}
    if opts.use_nerdfonts then
        M.viewconfig = M.nerdfont_viewconfig
    end

    if opts.keyconfig then
        M.keyconfig = opts.keyconfig
    end

    M.show_verbose_nav = opts.show_verbose_nav or false
    M.dv_toggle_keybind = opts.dv_toggle_keybind or nil
    M.dm_toggle_keybind = opts.dm_toggle_keybind or nil

    vim.api.nvim_create_user_command('DeltaView', function(delta_view_opts)
        local success, err = pcall(function()
            M.diff_target_ref = delta_view_opts.args ~= '' and delta_view_opts.args or nil
            M.diffed_files.files = nil
            M.diffed_files.cur_idx = nil
            M.run_diff_against(vim.fn.expand('%:p'), M.diff_target_ref)
        end)
        if not success then
            print('ERROR: Failed to create diff view: ' .. tostring(err))
        end
    end, {
        nargs = '?',
        desc =
        'Open Diff View against a git ref (branch, commit, tag, etc). Using it with no arguments runs it against the last argument used, or defaults to HEAD.'
    })

    if M.dv_toggle_keybind ~= nil and M.dv_toggle_keybind ~= '' then
        vim.keymap.set('n', M.dv_toggle_keybind, function()
            vim.cmd('DeltaView')
        end)
    end

    vim.api.nvim_create_user_command('DeltaMenu', function(diff_menu_opts)
        local success, err = pcall(function()
            M.diff_target_ref = diff_menu_opts.args ~= '' and diff_menu_opts.args or nil
            M.create_diff_menu_pane(M.run_diff_against, M.diff_target_ref)
        end)
        if not success then
            print('ERROR: Failed to create diff menu: ' .. tostring(err))
        end
    end, {
        nargs = '?',
        desc =
        'Open Diff Menu against a git ref (branch, commit, tag, etc). Using it with no arguments runs it against the last argument used, or defaults to HEAD.'
    })

    if M.dm_toggle_keybind ~= nil and M.dm_toggle_keybind ~= '' then
        vim.keymap.set('n', M.dm_toggle_keybind, function()
            vim.cmd('DeltaMenu')
        end)
    end
end

--- @class ViewConfig
--- @field dot string
--- @field circle string
--- @field vs string
M.viewconfig = {
    dot = "·",
    circle = "•",
    vs = "comparing to",
    next = "->",
    prev = "<-"
}

M.nerdfont_viewconfig = {
    dot = "",
    circle = "",
    vs = "",
    next = "󰁕",
    prev = "󰁎"
}

--- @class KeyConfig
--- @field next_hunk string
--- @field prev_hunk string
M.keyconfig = {
    next_hunk = "<Tab>",
    prev_hunk = "<S-Tab>",
    next_diff = "]f",
    prev_diff = "[f"
}

--- enables the user to go to "next diff in menu" if the current diff was opened via the menu.
--- @class DiffedFiles
--- @field files table | nil
--- @field cur_idx number | nil
M.diffed_files = { files = nil, cur_idx = nil }

return M
