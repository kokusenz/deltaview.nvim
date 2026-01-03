-- Homemade git diff viewing experience. makes keybinds for git status, viewing a diff of a file while on it, and exposes a command to compare against a branch

-- TODO, ideas for future implementation
-- keybinds to jump between hunks (either using git delta syntax parsing or using git diff porcelain outputs)
-- ideally, remove manual syntax parsing/pattern finding. Investigate any metadata coming out of git-delta that we can use
-- some sort of staging functionality? There are many plugins that handle this already, may not be necessary unless I plan on completely tossing git/fzf plugins.

local M = {}
local selector = require('deltaview.selector')

--- Check if a path is a valid file path for diffing (not a directory or empty)
--- @param path string|nil The file path to validate
--- @return boolean True if the path is a diffable file, false otherwise
local is_diffable_filepath = function(path)
    if path == nil or string.sub(path, -1) == "/" or path == '' then
        return false
    end
    return true
end

--- Factory function that creates a label extractor for file paths
--- Extracts unique single-character labels from filenames (not full paths)
--- @return function A function that takes a filepath and returns a single-character label
local label_filepath_item = function()
    local used_labels = {}
    return function(item)
        -- extract just the filename (everything after the last forward slash)
        local filename = item:match("([^/]+)$") or item
        local i = 1
        while i <= #filename do
            local char = string.lower(filename:sub(i, i))
            if used_labels[char] == nil then
                used_labels[char] = true
                return char
            end
            i = i + 1
        end
        -- fallback if all characters are used
        return tostring(i)
    end
end

--- Get list of modified and untracked files
--- @param branch_name string|nil Branch to compare against (defaults to HEAD if nil). If nil, includes untracked files
--- @return table Array of file paths that have been modified or are untracked
local get_diffed_files = function(branch_name)
    -- diffed files
    local diffed = vim.fn.system({'git', 'diff', branch_name ~= nil and branch_name or 'HEAD', '--name-only'})
    if vim.v.shell_error ~= 0 then
        print('ERROR: Failed to get diff files from git')
        return {}
    end

    -- new untracked files
    local untracked = ''
    if branch_name == nil then
        untracked = vim.fn.system({'git', 'ls-files', '-o', '--exclude-standard'})
        if vim.v.shell_error ~= 0 then
            print('ERROR: Failed to get untracked files from git')
            untracked = ''
        end
    end

    local files = {}
    local seen = {}

    for match in (diffed .. untracked):gmatch('[^\n]+') do
        if not seen[match] and match ~= '' then
            seen[match] = true
            table.insert(files, match)
        end
    end

    return files
end

--- Create an interactive menu pane for selecting and viewing diffs of modified files
--- @param diffing_function function Function to call for displaying diffs, receives (filepath, branch_name)
--- @param branch_name string|nil Optional branch to compare against (defaults to HEAD)
M.create_diff_menu_pane = function(diffing_function, branch_name)
    if diffing_function == nil then
        print('ERROR: must declare a function to diff the file')
        return
    end
    local mods = get_diffed_files(branch_name)
    -- note that label_item, win_predefined are custom opts on a custom vim-ui-select
    -- A vanilla vim.ui.select will simply label these with numbers, and show them where they want to.
    -- We are labeling these with letters, and showing them in a horizontal split.
    selector.ui_select(mods, {
        prompt = 'Modified Files',
        label_item = label_filepath_item,
        win_predefined='hsplit',
    }, function(filepath, _)
        if filepath == nil then
            return
        end
        -- TODO sometimes, files will be returned in a diff that do not exist, because they were removed.
        -- account for that, in the labeling and the handling here; just print something instead of editing.
        local success, err = pcall(function()
            vim.cmd('e ' .. vim.fn.fnameescape(filepath))
        end)
        if not success then
            print('ERROR: Failed to open file: ' .. filepath)
            return
        end
        local cur_win = vim.api.nvim_get_current_win()
        M.create_diff_menu_pane(diffing_function, branch_name)
        -- shift focus back to window
        vim.api.nvim_set_current_win(cur_win)
        diffing_function(filepath, branch_name)
    end)
end

--- Run a git diff for the specified file against a branch
--- Handles both tracked and untracked files
--- @param filepath string The file path to diff
--- @param branch_name string|nil Optional branch to compare against (defaults to HEAD)
M.run_diff_against = function(filepath, branch_name)
    local is_diffable = is_diffable_filepath(filepath)
    if is_diffable == false then
        print('WARNING: cannot run diff on a directory')
        return
    end
    -- check if file is tracked to determine which git diff command to use
    local is_tracked = vim.fn.system({'git', 'ls-files', '--', filepath})
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
        local modified_files = vim.fn.system({'git', 'diff', branch_name ~= nil and branch_name or 'HEAD', '--name-only', '--', filepath})
        if vim.v.shell_error ~= 0 then
            print('ERROR: Failed to get modified files from git')
            return
        end
        if modified_files ~= nil and modified_files ~= '' then
            -- note that due to hard coded context ceiling (found no viable alternative), files above 3000 lines might not show all lines
            cmd = 'git diff -U3000 ' .. (branch_name ~= nil and branch_name or 'HEAD') .. ' -- ' .. vim.fn.shellescape(filepath)
            hunk_cmd = 'git diff -U0 ' .. (branch_name ~= nil and branch_name or 'HEAD') .. ' -- ' .. vim.fn.shellescape(filepath)
        end
    end

    if cmd == nil then
        print('WARNING: file is not modified. No diff to display')
        return
    end

    local diff_buffer_funcs  = M.display_diff_followcursor(cmd)
    M.setup_hunk_navigation(hunk_cmd, diff_buffer_funcs)
end

--- Display git diff output in a terminal buffer with cursor position syncing
--- Creates a terminal buffer running delta, syncs cursor position between source and diff
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
                for key,value in ipairs(diff_buf_lines) do
                    -- on an empty line, we look for the line number instead. Line numbers show up in git delta, will be pattern matched.
                    if string.match(value, '⋮%s+' .. cur_cursor_pos[1]) ~= nil then
                        local success, err = pcall(function()
                            if cur_line == '' or cur_line == nil then
                                vim.api.nvim_win_set_cursor(0, { key , #value })
                                last_valid_currentdiff_cursor_pos = { key, #value }
                            else
                                vim.api.nvim_win_set_cursor(0, { key , cur_cursor_pos[2] + (#value - #cur_line) })
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
                vim.api.nvim_create_autocmd('CursorMoved', { buffer = term_buf, callback = function()
                    local term_buf_cur_line = vim.api.nvim_get_current_line()
                    local term_buf_cur_cursor_pos = vim.api.nvim_win_get_cursor(0)
                    local matching_line_number = string.match(term_buf_cur_line, '⋮%s+(%d+)')
                    local git_delta_linenumber_artifacts = string.match(term_buf_cur_line, '(.*│)')
                    if matching_line_number ~= nil then
                        last_valid_currentdiff_cursor_pos = { tonumber(matching_line_number), math.max(term_buf_cur_cursor_pos[2] - string.len(git_delta_linenumber_artifacts), 0) }
                    end
                end})

                -- expose functions to interact with term buffer

                --- @param line number # target line number to move to; moves to line post diff, not pre diff
                move_to_line = function(line)
                    for key,value in ipairs(diff_buf_lines) do
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

    local return_to_cur_buffer = function()
        local success, err = pcall(function()
            vim.api.nvim_set_current_buf(cur_buf)
            if last_valid_currentdiff_cursor_pos ~= nil then
                vim.api.nvim_win_set_cursor(0, {last_valid_currentdiff_cursor_pos[1], last_valid_currentdiff_cursor_pos[2]})
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
    vim.keymap.set('n', '<leader>dl', function()
        return_to_cur_buffer()
    end, { buffer = term_buf, noremap = true, silent = true })

    --- @return number
    local get_current_line = function()
        if last_valid_currentdiff_cursor_pos ~= nil then
            return last_valid_currentdiff_cursor_pos[1]
        end
        return 1  -- default to line 1 if not set
    end

    --- @class DiffBufferFuncs
    --- @field get_current_line function
    --- @field move_to_line function 
    --- @field buf_id number
    local funcs = { buf_id = term_buf, get_current_line = get_current_line, move_to_line = move_to_line_wrapper }
    return funcs
end

--- sets up hunk navigation for the buffer the diff is displayed on
--- @param hunk_cmd string git diff with 0 context to be able to properly parse for hunks
--- @param diff_buffer_funcs DiffBufferFuncs
M.setup_hunk_navigation = function(hunk_cmd, diff_buffer_funcs)
    local output = vim.fn.system(hunk_cmd)
    if vim.v.shell_error ~= 0 then
        print('ERROR: Failed to get hunks from git diff')
        return
    end

    -- need target line numbers
    local matches = {}
    for line_after in string.gmatch(output, '@@%s%-%d+,%d+%s%+(%d+),%d+%s@@') do
        table.insert(matches, tonumber(line_after))
    end
    -- create keybind to go to next hunk and prev hunk
    -- cycle through hunks
    -- scrollpeek indicator needs hunk count
    -- todo: allow manual config of what key this should be in setup, <Tab> and <S-Tab> as fallbacks/defaults
    vim.keymap.set('n', '<Tab>', function()
        local cur_line = diff_buffer_funcs.get_current_line()
        for i = 1, #matches, 1 do
            local line = matches[i]
            if line > tonumber(cur_line) then
                -- this line is the target "next hunk"
                -- because we iterate linearly, and all hunks should be ascending, we can assume the first line we find greater than cur_line is the next hunk
                print(line)
                diff_buffer_funcs.move_to_line(line)
                return
            end
        end
    end, { buffer = diff_buffer_funcs.buf_id, noremap = true, silent = true })

    vim.keymap.set('n', '<S-Tab>', function()
        local cur_line = diff_buffer_funcs.get_current_line()
        for i = #matches, 1, -1 do
            local line = matches[i]
            if line < tonumber(cur_line) then
                -- this line is the target "next hunk"
                -- because we iterate linearly, and all hunks should be ascending, we can assume the first line we find greater than cur_line is the next hunk
                print(line)
                diff_buffer_funcs.move_to_line(line)
                return
            end
        end
    end, { buffer = diff_buffer_funcs.buf_id, noremap = true, silent = true })
end

--- Setup keymaps and commands for diff functionality
--- Keymaps: <leader>dm for diff menu, <leader>dl for diff current file
--- Commands: :DiffMenu [branch] to compare against a branch
M.setup = function()
    vim.keymap.set('n', '<leader>dm', function()
        M.create_diff_menu_pane(M.run_diff_against)
    end)

    vim.keymap.set('n', '<leader>dl', function()
        M.run_diff_against(vim.fn.expand('%:p'))
    end)

    vim.cmd([[cabbrev dm DiffMenu]])
    vim.api.nvim_create_user_command('DiffMenu', function(opts)
        local success, err = pcall(function()
            local branch_name = opts.args ~= '' and opts.args or nil
            M.create_diff_menu_pane(M.run_diff_against, branch_name)
        end)
        if not success then
            print('ERROR: Failed to create diff menu: ' .. tostring(err))
        end
    end, {
        nargs = '?',
        desc = 'Open Diff Menu against a branch.'
    })
end

return M
