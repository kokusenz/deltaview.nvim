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

    -- check if cwd matches git root
    if not utils.is_cwd_git_root() then
        print('ERROR: Current working directory must be the git repository root to use DeltaView Menu.')
        return
    end

    local diffed_files = utils.get_diffed_files(ref)
    local mods = utils.get_filenames_from_sortedfiles(diffed_files)

    if #mods == 0 then
        print('DeltaView: No diffs to display')
        return
    end
    local changes_data = {}
    for _, value in ipairs(diffed_files) do
        changes_data[value.name] = {'+' .. value.added .. ',-' .. value.removed}
    end

    local on_select = function(filepath, selected_idx)
        if filepath == nil then
            return
        end
        if selected_idx == nil then
            for key, value in ipairs(mods) do
                if value == filepath then
                    selected_idx = key
                end
            end
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
    end

    local deltaview_quickselect_menu = function()
        selector.ui_select(mods, {
            prompt = 'DeltaView Menu  |  ' .. M.viewconfig.vs .. ' ' .. (ref or 'HEAD'),
            label_item = utils.label_filepath_item,
            win_predefined = 'hsplit',
            additional_data = changes_data
        }, on_select)
    end

    if #mods >= M.fzf_threshold then
        -- TODO: allow integration with fzf-lua and telescope pickers; use those pickers if available
        local on_select_with_key = function(result)
            if result == nil or #result == 0 then
                return
            end

            local key = result[1]

            if key == M.keyconfig.fzf_toggle then
                deltaview_quickselect_menu()
                return
            end

            -- result[2] contains the selected item
            if result[2] then
                on_select(result[2], nil)
            end
        end

        local success, err = pcall(function()
            vim.fn['fzf#run'](vim.fn['fzf#wrap']({
                source = mods,
                ['sink*'] = on_select_with_key,
                options = {
                    '--style', 'minimal',
                    '--layout', 'reverse',
                    '--prompt', 'DeltaView Menu > ',
                    '--preview', 'if [ -z "$(git ls-files -- {})" ]; then git diff --no-index /dev/null {}; else git diff ' .. (ref or 'HEAD') .. ' -- {}; fi | delta --paging=never',
                    '--border-label', 'comparing to ' .. (ref or 'HEAD'),
                    '--expect', M.keyconfig.fzf_toggle,
                },
                window = { width = 0.8, height = 0.9, border = 'rounded' }
            }))
        end)
        if success then
            return
        else
            print('WARNING: fzf#run failed: ' .. tostring(err) .. '. Using default picker.')
        end
    end
    deltaview_quickselect_menu()
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

    local diffed_files = utils.get_diffed_files(ref)
    local mods = utils.get_filenames_from_sortedfiles(diffed_files)
    if #mods == 0 then
        print('DeltaView: No diffs to display')
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
M.run_diff_against_file = function(filepath, ref)
    if filepath == nil then
        print('ERROR: filepath is nil')
        return
    end

    if vim.fn.filereadable(filepath) == 0 then
        print('ERROR: not a valid file.')
        return
    end

    -- check if file is tracked to determine which git diff command to use
    local is_tracked = vim.fn.system({ 'git', 'ls-files', '--', filepath })
    if vim.v.shell_error ~= 0 then
        print('ERROR: Failed to check if file is tracked')
        return
    end

    -- get file line count for context size
    local line_count_output = vim.fn.system({'wc', '-l', filepath})
    local line_count = tonumber(vim.trim(line_count_output):match('^%d+')) or 10000
    local context = math.min(line_count + 100, 10000)

    local cmd
    local hunk_cmd

    if is_tracked == '' or is_tracked == '\n' then
        -- untracked file
        cmd = 'git diff -U' .. context .. ' --no-index /dev/null ' .. vim.fn.shellescape(filepath)
        hunk_cmd = 'git diff -U0 --no-index /dev/null ' .. vim.fn.shellescape(filepath)
    else
        -- tracked file
        local modified_files = vim.fn.system({ 'git', 'diff', ref ~= nil and ref or 'HEAD', '--name-only', '--', filepath })
        if vim.v.shell_error ~= 0 then
            print('ERROR: Failed to get modified files from git')
            return
        end
        if modified_files ~= nil and modified_files ~= '' then
            cmd = 'git diff -U' .. context .. ' ' .. (ref ~= nil and ref or 'HEAD') .. ' -- ' .. vim.fn.shellescape(filepath)
            hunk_cmd = 'git diff -U0 ' .. (ref ~= nil and ref or 'HEAD') .. ' -- ' .. vim.fn.shellescape(filepath)
        end
    end

    if cmd == nil then
        print('WARNING: file is not modified. No diff to display')
        return
    end

    -- check if buf with name already exists
    local existing_buf = vim.fn.bufnr(cmd)
    if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
        vim.api.nvim_buf_delete(existing_buf, { force = true })
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

--- @alias MoveToLineFunction fun(line: number, before: boolean|nil, file: string|nil): nil

--- @class DiffBufferFuncs table to expose functions to interact with the diff buffer
--- @field buf_id number
--- @field move_to_line MoveToLineFunction Move cursor to specified line in diff buffer
--- @field get_current_file function | nil

    --- @param diff_buffer_funcs DiffBufferFuncs
    local on_ready_callback = function(diff_buffer_funcs)
        M.setup_hunk_navigation(hunk_cmd, diff_buffer_funcs, cmd_ui)
    end
    M.display_delta_file(cmd, cmd_ui, on_ready_callback)
end

--- Run a git diff for the specified directory against a git ref
--- @param path string The path to diff
--- @param ref string|nil Optional git ref to compare against (defaults to HEAD). Can be branch, commit, tag, etc.
M.run_diff_against_directory = function(path, ref)
    local cmd = 'git diff -U'.. M.default_context .. ' ' .. (ref ~= nil and ref or 'HEAD') .. ' -- ' .. vim.fn.shellescape(path)
    local hunk_cmd = 'git diff -U0 ' .. (ref ~= nil and ref or 'HEAD') .. ' -- ' .. vim.fn.shellescape(path)

    -- check if buf with name already exists
    local existing_buf = vim.fn.bufnr(cmd)
    if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
        vim.api.nvim_buf_delete(existing_buf, { force = true })
    end

    -- dry run: test commands, terminate early if fail
    local test_output = vim.fn.system(cmd)
    local exit_code = vim.v.shell_error
    if exit_code ~= 0 and exit_code ~= 1 then
        print('ERROR: git diff failed (exit ' .. exit_code .. '): ' .. vim.trim(test_output))
        return
    end

    if vim.trim(test_output) == '' then
        print('WARNING: path is not modified. No diff to display')
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

    --- @param diff_buffer_funcs DiffBufferFuncs
    local on_ready_callback = function(diff_buffer_funcs)
        M.setup_hunk_navigation(hunk_cmd, diff_buffer_funcs, cmd_ui)
    end
    M.display_delta_directory(cmd, cmd_ui, on_ready_callback)
end

--- display git diff delta output in a terminal buffer with cursor position syncing and all context for one file
--- @param cmd string The git diff command to execute
--- @param cmd_ui table The cmd_ui
--- @param on_ready_callback function after the cmd_ui has initialized, run this function
M.display_delta_file = function(cmd, cmd_ui, on_ready_callback)
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

    local last_valid_currentdiff_cursor_pos = { 1, 0 }

    vim.fn.jobstart(delta_cmd, {
        term = true,
        on_exit = function()
            vim.schedule(function()
                -- place cursor upon entry
                -- TODO does not handle wrapped lines well. When entering while cursor is on a wrapped line, it enters at the right line but the wrong position
                local diff_buf_lines = vim.api.nvim_buf_get_lines(term_buf, 0, -1, false)
                for key, value in ipairs(diff_buf_lines) do
                    if string.match(value, '⋮%s*' .. cur_cursor_pos[1]) ~= nil then
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
                            -- cursor position might be out of bounds, set to safe default
                            vim.api.nvim_win_set_cursor(0, { key, 0 })
                            last_valid_currentdiff_cursor_pos = { key, 0 }
                        end
                        break
                    end
                end

                -- update where cursor should be upon exit
                -- TODO does not handle wrapped lines well. When exiting while cursor is on a wrapped line, it exits at the right line but the wrong position
                vim.api.nvim_create_autocmd('CursorMoved', {
                    buffer = term_buf,
                    callback = function()
                        local term_buf_cur_line = vim.api.nvim_get_current_line()
                        local term_buf_cur_cursor_pos = vim.api.nvim_win_get_cursor(0)
                        local matching_line_number = string.match(term_buf_cur_line, '⋮%s*(%d+)')
                        local git_delta_linenumber_artifacts = string.match(term_buf_cur_line, '(.*│)')
                        if matching_line_number ~= nil then
                            last_valid_currentdiff_cursor_pos = { tonumber(matching_line_number), math.max(
                                term_buf_cur_cursor_pos[2] - string.len(git_delta_linenumber_artifacts), 0) }
                        end
                    end
                })

                --- note: while file is defined here for consistency with the expected method signature move_to_line, it is unused, as multiple files are not a factor in this workflow
                --- @type MoveToLineFunction
                local move_to_line = function(line, before, file)
                    assert(file == nil, "delta for a single file does not expect file as a specification for which line to move to")
                    for key, value in ipairs(diff_buf_lines) do
                        local after_pattern = '⋮%s*' .. line .. '%s*│'
                        local before_pattern = '%s*' .. line .. '%s*⋮'
                        if string.match(value, before and before_pattern or after_pattern) ~= nil then
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

                --- @type DiffBufferFuncs
                local funcs = { buf_id = term_buf, move_to_line = move_to_line, get_current_file = nil }
                on_ready_callback(funcs)
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

    if M.keyconfig.dv_toggle_keybind ~= nil and M.keyconfig.dv_toggle_keybind ~= '' then
        vim.keymap.set('n', M.keyconfig.dv_toggle_keybind, function()
            return_to_cur_buffer()
        end, { buffer = term_buf, noremap = true, silent = true })
    end

    local adjacent_files = utils.get_adjacent_files(M.diffed_files)
    if adjacent_files ~= nil then
        local next_diff_message = (M.show_verbose_nav and (vim.fn.fnamemodify(adjacent_files.prev.name, ':t') .. ' ' .. M.viewconfig.prev) or '') ..
            ' [' .. M.diffed_files.cur_idx .. '/' .. #M.diffed_files.files .. '] ' .. M.viewconfig.next .. ' ' ..
            vim.fn.fnamemodify(adjacent_files.next.name, ':t')
        utils.append_cmd_ui(cmd_ui, next_diff_message, false)

        vim.keymap.set('n', M.keyconfig.next_diff, function()
            return_to_cur_buffer()
            M.programmatically_select_diff_from_menu(M.run_diff_against_file, adjacent_files.next.name, M.diff_target_ref)
        end, { buffer = term_buf, noremap = true, silent = true })

        vim.keymap.set('n', M.keyconfig.prev_diff, function()
            return_to_cur_buffer()
            M.programmatically_select_diff_from_menu(M.run_diff_against_file, adjacent_files.prev.name, M.diff_target_ref)
        end, { buffer = term_buf, noremap = true, silent = true })
    end
end

--- display git diff delta output in a terminal buffer with optional exit strategy and configurable context
--- @param cmd string The git diff command to execute
--- @param cmd_ui table The cmd ui
--- @param on_ready_callback function after the cmd_ui has initialized, run this function
M.display_delta_directory = function(cmd, cmd_ui, on_ready_callback)
    local delta_cmd = cmd .. ' | delta --line-numbers --paging=never'
    local name_only_cmd = cmd:gsub("diff", "diff --name-only", 1)
    local cur_buf = vim.api.nvim_get_current_buf()

    local term_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = term_buf })
    vim.api.nvim_buf_set_var(term_buf, 'is_deltaview', true)
    vim.api.nvim_set_current_buf(term_buf)

    local prev_cursorline = vim.wo.cursorline
    local prev_cursorlineopt = vim.wo.cursorlineopt
    local prev_cursorline_hl = vim.api.nvim_get_hl(0, { name = 'CursorLine' })
    local bold_hl = vim.tbl_extend('force', prev_cursorline_hl, { bold = true })

    vim.api.nvim_create_autocmd('BufLeave', {
        buffer = term_buf,
        once = true,
        callback = function()
            vim.wo.cursorline = prev_cursorline
            vim.wo.cursorlineopt = prev_cursorlineopt
            vim.api.nvim_set_hl(0, 'CursorLine', prev_cursorline_hl)
        end
    })

    local diffed_file_names = {}
    for file in vim.fn.system(name_only_cmd):gmatch("[^\r\n]+") do
        table.insert(diffed_file_names, file)
    end

    local last_valid_cursor_pos = nil
    local current_file = diffed_file_names[1]

    vim.fn.jobstart(delta_cmd, {
        term = true,
        on_exit = function()
            vim.schedule(function()
                -- update what line and file we are on. purely for performance reasons; stores found results in memory for lookup
                local line_file_map = {}
                --- @param cur_line number line/row number in delta file, not the line it's referring to in the origin file
                local get_file_at_line = function(cur_line)
                    -- keep in mind cur_line refers to the actual line within the term window, not the line it's referring to in the file
                    if line_file_map[cur_line] == nil then
                        for i = cur_line, 1, -1 do
                            local line_content = vim.api.nvim_buf_get_lines(term_buf, i - 1, i, false)[1]
                            local trimmed = vim.trim(line_content)
                            for _, file in ipairs(diffed_file_names) do
                                if trimmed == file then
                                    line_file_map[cur_line] = file
                                    goto found
                                end
                            end
                        end
                    end
                    ::found::
                    return line_file_map[cur_line]
                end
                vim.api.nvim_create_autocmd('CursorMoved', {
                    buffer = term_buf,
                    callback = function()
                        -- TODO getting current line means this does not detect the wrapped part of a wrapped line as a real valid line.
                        -- Figure out how to handle jumping (<CR>) on a wrapped line, highlighting a wrapped line, confirm that hunk jumping when cursor is on wrapped lines works as intended
                        local term_buf_cur_line = vim.api.nvim_get_current_line()
                        local term_buf_cur_cursor_pos = vim.api.nvim_win_get_cursor(0)
                        local matching_line_number = string.match(term_buf_cur_line, '⋮%s*(%d+)')
                        local before_line_number = string.match(term_buf_cur_line, '%s*(%d+)%s*⋮')
                        local git_delta_linenumber_artifacts = string.match(term_buf_cur_line, '(.*│)')
                        if matching_line_number ~= nil then
                            last_valid_cursor_pos = {
                                tonumber(matching_line_number),
                                math.max(term_buf_cur_cursor_pos[2] - string.len(git_delta_linenumber_artifacts or ''), 0)
                            }
                            if before_line_number == nil then
                                -- this line will be marked green. make the highlight stand out
                                vim.api.nvim_set_hl(0, 'CursorLine', bold_hl)
                            else
                                vim.api.nvim_set_hl(0, 'CursorLine', prev_cursorline_hl)
                            end
                            vim.wo.cursorline = true
                            vim.wo.cursorlineopt = 'screenline'
                        else
                            last_valid_cursor_pos = nil
                            vim.wo.cursorline = prev_cursorline
                            vim.wo.cursorlineopt = prev_cursorlineopt
                            vim.api.nvim_set_hl(0, 'CursorLine', prev_cursorline_hl)
                        end
                        current_file = get_file_at_line(term_buf_cur_cursor_pos[1])
                    end
                })

                local diff_buf_lines = vim.api.nvim_buf_get_lines(term_buf, 0, -1, false)

                --- @type MoveToLineFunction
                local move_to_line = function(line, before, file)
                    for key, value in ipairs(diff_buf_lines) do
                        if file ~= nil and file ~= '' and get_file_at_line(key) ~= file then
                            goto continue
                        end
                        local after_pattern = '⋮%s*' .. line .. '%s*│'
                        local before_pattern = '%s*' .. line .. '%s*⋮'
                        if string.match(value, before and before_pattern or after_pattern) ~= nil then
                            local success, err = pcall(function()
                                vim.api.nvim_win_set_cursor(0, { key, 0 })
                                vim.cmd('normal! zz')
                            end)
                            if not success then
                                print('ERROR: Failed to move cursor to line ' .. line)
                            end
                            return
                        end
                        ::continue::
                    end
                end

                local get_current_file = function()
                    return current_file
                end

                --- @type DiffBufferFuncs
                local funcs = { buf_id = term_buf, move_to_line = move_to_line, get_current_file = get_current_file}
                on_ready_callback(funcs)
            end)
        end
    })

    vim.api.nvim_buf_set_name(term_buf, cmd)

    local jump_to_chosen_diff = function()
        if last_valid_cursor_pos ~= nil then
            local success, err = pcall(function()
                vim.cmd('e ' .. vim.fn.fnameescape(current_file))
                vim.api.nvim_win_set_cursor(0, last_valid_cursor_pos)
                vim.cmd('normal! zz')
            end)
            if not success then
                print('ERROR: Failed to open file: ' .. current_file .. ' - file may have been removed.')
                return
            end
        else
            utils.display_cmd_ui(cmd_ui, "WARNING: could not jump to an invalid location")
        end
    end

    vim.keymap.set('n', '<Esc>', function()
        vim.api.nvim_set_current_buf(cur_buf)
    end, { buffer = term_buf, noremap = true, silent = true })

    vim.keymap.set('n', 'q', function()
        vim.api.nvim_set_current_buf(cur_buf)
    end, { buffer = term_buf, noremap = true, silent = true })

    vim.keymap.set('n', M.keyconfig.jump_to_line, function()
        jump_to_chosen_diff()
    end, { buffer = term_buf, noremap = true, silent = true })

    if M.keyconfig.d_toggle_keybind ~= nil and M.keyconfig.d_toggle_keybind ~= '' then
        vim.keymap.set('n', M.keyconfig.d_toggle_keybind, function()
            vim.api.nvim_set_current_buf(cur_buf)
        end, { buffer = term_buf, noremap = true, silent = true })
    end
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

    --- @class Hunk
    --- @field after number the line number after
    --- @field before number the line number before
    --- @field is_pure_deletion boolean

    --- @class Dictionary<Hunk>: { [string] : Hunk[] }
    local matches = {}
    local file_order = {}
    local current_file = nil

    for line in output:gmatch("[^\r\n]+") do
        local file = line:match('%+%+%+ %a/(.+)')
        if file then
            current_file = file
            table.insert(file_order, file)
            matches[file] = {}
        end

        local line_before, line_after, additions = line:match('@@ %-(%d+),?%d* %+(%d+),?(%d*) @@')
        if line_after and current_file then
            if tonumber(line_after) == nil or tonumber(line_before) == nil then
                assert(false, "parsing line numbers from hunks failed")
            end
            local is_pure_deletion = additions == '0'
            --- @type Hunk
            local hunk = {
                after = tonumber(line_after) or 1,
                before = tonumber(line_before) or 1,
                is_pure_deletion = is_pure_deletion
            }
            table.insert(matches[current_file], hunk)
        end
    end

    -- flattened list for when there is only one file
    --- @type Hunk[]
    local matches_flat = {}
    for _, file in ipairs(file_order) do
        for _, hunk in ipairs(matches[file]) do
            table.insert(matches_flat, hunk)
        end
    end

    if #file_order > 1 and diff_buffer_funcs.get_current_file == nil then
        print('ERROR: setup_hunk_navigation requires get_current_file for multi-file diffs')
        return
    end

    local cur_line_number = tonumber(1)
    local cur_prev_line_number = nil

    local update_cur_line_number = function()
        local term_buf_cur_line = vim.api.nvim_get_current_line()
        local before_line_number = string.match(term_buf_cur_line, '%s*(%d+)%s*⋮')
        local after_line_number = string.match(term_buf_cur_line, '⋮%s*(%d+)')
        cur_prev_line_number = tonumber(before_line_number)
        cur_line_number = tonumber(after_line_number)
    end

    local get_line_number_before_negative_hunk = function()
        if cur_line_number == nil and cur_prev_line_number ~= nil then
            local diff_buf_lines = vim.api.nvim_buf_get_lines(diff_buffer_funcs.buf_id, 0, -1, false)
            local last_after_line_number = tonumber(1)
            for _, value in ipairs(diff_buf_lines) do
                local before_line_number = string.match(value, '%s*(%d+)%s*⋮')
                local after_line_number = string.match(value, '⋮%s*(%d+)')
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

    -- when using limited context, not every line of the delta buffer is guaranteed to have before/after line numbers. this handles those lines
    local get_line_number_before_empty_line = function()
        if cur_line_number == nil and cur_prev_line_number == nil then
            local cur_row = vim.api.nvim_win_get_cursor(0)[1]
            local diff_buf_lines = vim.api.nvim_buf_get_lines(diff_buffer_funcs.buf_id, 0, cur_row, false)
            local last_after_line_number = tonumber(0)
            for _, value in ipairs(diff_buf_lines) do
                local after_line_number = string.match(value, '⋮%s*(%d+)')
                if tonumber(after_line_number) ~= nil then
                    last_after_line_number = tonumber(after_line_number)
                end
            end
            return last_after_line_number
        end
        return 0
    end

    --- hunk progress indicator
    local render_hunk_progress_cmd_ui = function()
        if #file_order <= 1 then
            local cur_hunk = 1
            for i = 1, #matches_flat + 1, 1 do
                if i == #matches_flat + 1
                    or (matches_flat[i].after > (cur_line_number or get_line_number_before_negative_hunk() or get_line_number_before_empty_line())) then
                    cur_hunk = i
                    break
                end
            end

            if cur_hunk == 1 then
                utils.display_cmd_ui(cmd_ui, M.viewconfig.dot:rep(#matches_flat))
            else
                local left = cur_hunk - 2
                local right = #matches_flat - (cur_hunk - 1)
                utils.display_cmd_ui(cmd_ui, M.viewconfig.dot:rep(left) .. M.viewconfig.circle .. M.viewconfig.dot:rep(right))
            end
        elseif diff_buffer_funcs.get_current_file ~= nil then
            local diff_buffer_cur_file = diff_buffer_funcs.get_current_file()
            if diff_buffer_cur_file == nil then
                local next_diff_message = ' [0/' .. #file_order .. '] ' .. M.viewconfig.next .. ' ' ..
                    vim.fn.fnamemodify(file_order[1], ':t')
                utils.display_cmd_ui(cmd_ui, next_diff_message)
                return
            end
            local message = ''
            for idx, file in ipairs(file_order) do
                local hunks = matches[file]
                if file == diff_buffer_cur_file then
                    local cur_hunk = 1
                    for i = 1, #hunks + 1, 1 do
                        if i == #hunks + 1
                            or (hunks[i].after > (cur_line_number or get_line_number_before_negative_hunk() or get_line_number_before_empty_line())) then
                            cur_hunk = i
                            break
                        end
                    end

                    if cur_hunk == 1 then
                        message = message .. M.viewconfig.dot:rep(#hunks)
                    else
                        local left = cur_hunk - 2
                        local right = #hunks - (cur_hunk - 1)
                        message = message .. M.viewconfig.dot:rep(left) .. M.viewconfig.circle .. M.viewconfig.dot:rep(right)
                    end
                    message = message .. '    '
                    local next_diff_message = vim.fn.fnamemodify(diff_buffer_cur_file, ':t') ..
                        ' [' .. idx .. '/' .. #file_order .. '] ' .. M.viewconfig.next .. ' ' ..
                        vim.fn.fnamemodify(file_order[idx+1 > #file_order and 1 or idx+1], ':t')
                    message = message .. next_diff_message
                end
            end
            utils.display_cmd_ui(cmd_ui, message)
        else
            assert(false, "unreachable: multi-file diff should receive a get_current_file function")
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

    --- @param hunk Hunk
    --- @param file string | nil
    local move_to_hunk = function(hunk, file)
        if hunk.is_pure_deletion then
            diff_buffer_funcs.move_to_line(hunk.before, true, file)
            return
        end
        diff_buffer_funcs.move_to_line(hunk.after, false, file)
    end

    vim.keymap.set('n', M.keyconfig.next_hunk, function()
        -- maybe add validation that file_order is unique
        if #file_order <= 1 then
            for i = 1, #matches_flat, 1 do
                local hunk = matches_flat[i]
                if ((hunk.is_pure_deletion and cur_prev_line_number or cur_line_number) or get_line_number_before_negative_hunk() or get_line_number_before_empty_line()) 
                    < (hunk.is_pure_deletion and hunk.before or hunk.after) then
                    move_to_hunk(hunk)
                    return
                end
            end
            -- if we couldn't find a hunk (eg. we are past the last hunk) loop back around to the first hunk
            move_to_hunk(matches_flat[1])
        elseif diff_buffer_funcs.get_current_file ~= nil then
            local diff_buffer_cur_file = diff_buffer_funcs.get_current_file()
            for idx, file in ipairs(file_order) do
                local hunks = matches[file]
                if file == diff_buffer_cur_file then
                    for i = 1, #hunks, 1 do
                        local hunk = hunks[i]
                        if ((hunk.is_pure_deletion and cur_prev_line_number or cur_line_number) or get_line_number_before_negative_hunk() or get_line_number_before_empty_line())
                            < (hunk.is_pure_deletion and hunk.before or hunk.after) then
                            move_to_hunk(hunk, file)
                            return
                        end
                    end
                    -- if we couldn't find a hunk (eg. we are past the last hunk) move to the next hunk in the next file
                    local next_file = file_order[idx+1 > #file_order and 1 or idx+1]
                    local next_file_hunks = matches[next_file]
                    move_to_hunk(next_file_hunks[1], next_file)
                    return
                end
            end
            -- if ending without finding a file move to first hunk
            move_to_hunk(matches_flat[1])
        else
            assert(false, "unreachable: multi-file diff should receive a get_current_file function")
        end
    end, { buffer = diff_buffer_funcs.buf_id, noremap = true, silent = true })

    vim.keymap.set('n', M.keyconfig.prev_hunk, function()
        -- maybe add validation that file_order is unique
        if #file_order <= 1 then
            for i = #matches_flat, 1, -1 do
                local hunk = matches_flat[i]
                if ((hunk.is_pure_deletion and cur_prev_line_number or cur_line_number) or get_line_number_before_negative_hunk() or get_line_number_before_empty_line())
                    > (hunk.is_pure_deletion and hunk.before or hunk.after) then
                    move_to_hunk(hunk)
                    return
                end
            end
            -- if we couldn't find a hunk (eg. we are before the first hunk) loop back around to the last hunk
            move_to_hunk(matches_flat[#matches_flat])
        elseif diff_buffer_funcs.get_current_file ~= nil then
            local diff_buffer_cur_file = diff_buffer_funcs.get_current_file()
            for idx, file in ipairs(file_order) do
                local hunks = matches[file]
                if file == diff_buffer_cur_file then
                    for i = #hunks, 1, -1 do
                        local hunk = hunks[i]
                        if ((hunk.is_pure_deletion and cur_prev_line_number or cur_line_number) or get_line_number_before_negative_hunk() or get_line_number_before_empty_line())
                            > (hunk.is_pure_deletion and hunk.before or hunk.after) then
                            move_to_hunk(hunk, file)
                            return
                        end
                    end
                    -- if we couldn't find a hunk (eg. we are before the first hunk) pick last hunk in prev file
                    local next_file = file_order[idx-1 < 1 and #file_order or idx-1]
                    local next_file_hunks = matches[next_file]
                    move_to_hunk(next_file_hunks[#next_file_hunks], next_file)
                    return
                end
            end
            -- move to last hunk
            move_to_hunk(matches_flat[#matches_flat])
        else
            assert(false, "unreachable: multi-file diff should receive a get_current_file function")
        end
    end, { buffer = diff_buffer_funcs.buf_id, noremap = true, silent = true })

    if #file_order > 1 then
        vim.keymap.set('n', M.keyconfig.next_diff, function()
            local diff_buffer_cur_file = diff_buffer_funcs.get_current_file()
            for idx, file in ipairs(file_order) do
                if file == diff_buffer_cur_file then
                    local next_file = file_order[idx + 1 > #file_order and 1 or idx + 1]
                    local next_file_hunks = matches[next_file]
                    move_to_hunk(next_file_hunks[1], next_file)
                    return
                end
            end
            -- move to first file's first hunk if output of get_current_file cannot be found (for example is returning nil)
            local first_file = file_order[1]
            move_to_hunk(matches[first_file][1], first_file)
        end, { buffer = diff_buffer_funcs.buf_id, noremap = true, silent = true })

        vim.keymap.set('n', M.keyconfig.prev_diff, function()
            local diff_buffer_cur_file = diff_buffer_funcs.get_current_file()
            for idx, file in ipairs(file_order) do
                if file == diff_buffer_cur_file then
                    local prev_file = file_order[idx - 1 < 1 and #file_order or idx - 1]
                    local prev_file_hunks = matches[prev_file]
                    move_to_hunk(prev_file_hunks[1], prev_file)
                    return
                end
            end
            -- move to last file's last hunk if output of get_current_file cannot be found (for example is returning nil)
            local last_file = file_order[#file_order]
            move_to_hunk(matches[last_file][1], last_file)
        end, { buffer = diff_buffer_funcs.buf_id, noremap = true, silent = true })
    end
end

M.setup = function(opts)
    -- considerations for opts:
    --- @class DeltaViewOpts
    --- @field use_nerdfonts boolean | nil Defaults to true
    --- @field keyconfig KeyConfig | nil
    --- @field show_verbose_nav boolean | nil Show both prev and next filenames (true) or just position + next (false, default)
    --- @field fzf_threshold number | nil if the number of diffed files is equal to or greater than this threshold, it will show up in a fuzzy finding picker. Default to 10. Set to 1 or 0 if you would always like a fuzzy picker
    --- @field default_context number | nil if running deltaview on a directory rather than a file, it will show a typical delta view with limited context. Default to 3. Set here, or pass it in as a second param to DeltaView, which will persist as the context for this session
    opts = opts or {}
    if opts.use_nerdfonts ~= nil and opts.use_nerdfonts == false then
        M.viewconfig = M.basic_viewconfig
    end

    if opts.keyconfig then
        M.keyconfig = opts.keyconfig
    end

    M.show_verbose_nav = opts.show_verbose_nav or false
    M.fzf_threshold = opts.fzf_threshold or M.fzf_threshold
    M.default_context = opts.default_context or M.default_context

    -- TODO for DeltaView and Delta, keybind ? to open a keybind guide menu
    vim.api.nvim_create_user_command('DeltaView', function(delta_view_opts)
        local success, err = pcall(function()
            M.diff_target_ref = (delta_view_opts.args ~= '' and delta_view_opts.args ~= nil) and delta_view_opts.args or M.diff_target_ref
            M.diffed_files.files = nil
            M.diffed_files.cur_idx = nil
            local path = vim.fn.expand('%:p')
            if path == nil or path == '' then
                print('WARNING: not a valid path')
                return
            end
            if vim.fn.filereadable(path) == 0 then
                print('WARNING: not a valid file. Use :Delta to view the diff of the directory, or :DeltaMenu for all diffs')
                return
            end
            M.run_diff_against_file(path, M.diff_target_ref)
        end)
        if not success then
            print('ERROR: Failed to create diff view: ' .. tostring(err))
        end
    end, {
        nargs = '?',
        desc =
        'Open Diff View against a git ref (branch, commit, tag, etc). Using it with no arguments runs it against the last argument used, or defaults to HEAD.'
    })

    if M.keyconfig.dv_toggle_keybind ~= nil and M.keyconfig.dv_toggle_keybind ~= '' then
        vim.keymap.set('n', M.keyconfig.dv_toggle_keybind, function()
            vim.cmd('DeltaView')
        end)
    end

    vim.api.nvim_create_user_command('Delta', function(delta_view_opts)
        local success, err = pcall(function()
            M.diff_target_ref = (delta_view_opts.fargs[1] ~= nil and delta_view_opts.fargs[1] ~= '') and delta_view_opts.fargs[1] or M.diff_target_ref
            M.default_context = (delta_view_opts.fargs[2] ~= nil and delta_view_opts.fargs[2] ~= '') and delta_view_opts.fargs[2] or M.default_context
            if delta_view_opts.fargs[3] ~= nil then
                print('Delta only accepts up to two args')
                return
            end
            M.diffed_files.files = nil
            M.diffed_files.cur_idx = nil
            local path = vim.fn.expand('%:p')
            if path == nil or path == '' then
                path = vim.fn.getcwd()
            end
            M.run_diff_against_directory(path, M.diff_target_ref)
        end)
        if not success then
            print('ERROR: Failed to create diff view: ' .. tostring(err))
        end
    end, {
        nargs = '*',
        desc =
        'Open Diff View against a git ref (branch, commit, tag, etc). Using it with no arguments runs it against the last argument used, or defaults to HEAD.'
    })

    if M.keyconfig.d_toggle_keybind ~= nil and M.keyconfig.d_toggle_keybind ~= '' then
        vim.keymap.set('n', M.keyconfig.d_toggle_keybind, function()
            vim.cmd('Delta')
        end)
    end

    vim.api.nvim_create_user_command('DeltaMenu', function(delta_menu_opts)
        local success, err = pcall(function()
            M.diff_target_ref = (delta_menu_opts.args ~= '' and delta_menu_opts.args ~= nil) and delta_menu_opts.args or M.diff_target_ref
            M.create_diff_menu_pane(M.run_diff_against_file, M.diff_target_ref)
        end)
        if not success then
            print('ERROR: Failed to create diff menu: ' .. tostring(err))
        end
    end, {
        nargs = '?',
        desc =
        'Open Diff Menu against a git ref (branch, commit, tag, etc). Using it with no arguments runs it against the last argument used, or defaults to HEAD.'
    })

    if M.keyconfig.dm_toggle_keybind ~= nil and M.keyconfig.dm_toggle_keybind ~= '' then
        vim.keymap.set('n', M.keyconfig.dm_toggle_keybind, function()
            vim.cmd('DeltaMenu')
        end)
    end
end

--- @class ViewConfig
M.basic_viewconfig = {
    dot = "·",
    circle = "•",
    vs = "comparing to",
    next = "->",
    prev = "<-"
}

--- @class ViewConfig
M.nerdfont_viewconfig = {
    dot = "",
    circle = "",
    vs = "",
    next = "󰁕",
    prev = "󰁎"
}

--- @class ViewConfig
--- @field dot string
--- @field circle string
--- @field vs string
--- @field next string
--- @field prev string
M.viewconfig = M.nerdfont_viewconfig

--- @class KeyConfig
--- @field dv_toggle_keybind string | nil if defined, will create keybind that runs DeltaView, and exits Diff buffer if open
--- @field dm_toggle_keybind string | nil if defined, will create keybind that runs DeltaView Menu
--- @field next_hunk string skip to next hunk in diff.
--- @field prev_hunk string skip to prev hunk in diff.
--- @field next_diff string when diff was opened from DeltaMenu, open next file in the menu
--- @field prev_diff string when diff was opened from DeltaMenu, open prev file in the menu
--- @field fzf_toggle string when DeltaView Menu is opened in fzf mode (eg. when count exceeds the threshold), can switch back to default quick select.
--- @field d_toggle_keybind string | nil if defined, will create keybind that runs Delta, and exits Diff buffer if open
M.keyconfig = {
    dm_toggle_keybind = "<leader>dm",
    dv_toggle_keybind = "<leader>dl",
    d_toggle_keybind = "<leader>da",
    next_hunk = "<Tab>",
    prev_hunk = "<S-Tab>",
    next_diff = "]f",
    prev_diff = "[f",
    fzf_toggle = "alt-;",
    jump_to_line = "<CR>"
}

--- enables the user to go to "next diff in menu" if the current diff was opened via the menu.
--- @class DiffedFiles
--- @field files table | nil
--- @field cur_idx number | nil
M.diffed_files = { files = nil, cur_idx = nil }

M.fzf_threshold = 6
M.default_context = 3

return M
