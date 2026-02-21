local M = {}
local delta = require('delta')
local utils = require('deltaview.utils')

--- Run a git diff for the specified file against a git ref
--- Handles both tracked and untracked files
--- @param filepath string The file path to diff
--- @param ref string|nil Optional git ref to compare against (defaults to HEAD). Can be branch, commit, tag, etc.
M.run_git_diff_against_file = function(filepath, ref)
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

    local cmd = string.format('git diff -- %s', vim.fn.shellescape(filepath))
    local handle = io.popen(cmd)

    if not handle then
        vim.notify("Failed to run git diff", vim.log.levels.ERROR)
        return
    end

    local diffstring = handle:read("*a")

    if diffstring == "" then
        vim.notify("No changes detected in current file", vim.log.levels.WARN)
        return
    end

    local data = delta.parse.get_diff_data_git(diffstring)[1]

    local file_lines = utils.read_file_lines(git_root .. '/' .. data.new_path)
    if file_lines == nil then
        vim.notify('ERROR: couldnt read file', vim.log.levels.WARN)
        return
    end
    local s2 = table.concat(file_lines, "\n")
    local s1 = ''

    if (data.old_path) then
        local before = string.format('git show %s:%s', ref or 'HEAD', vim.fn.shellescape(data.old_path))
        handle = io.popen(before)
        if not handle then
            vim.notify("Failed to run git show", vim.log.levels.ERROR)
            return
        end
        local old_diffstring = handle:read("*a")
        -- TODO remove newline from old_diffstring at the end if it exists, figure out why these come out with newline at end?
        s1 = old_diffstring
        handle:close()
    end

    local bufnr = delta.text_diff(s1, s2, data.language, {context = 1000})
    vim.api.nvim_win_set_buf(0, bufnr)
    delta.highlight_delta_artifacts(bufnr)
    delta.syntax_highlight_diff_set(bufnr)
    delta.diff_highlight_diff(bufnr)
    delta.setup_delta_statuscolumn(bufnr)

    --local cmd_ui = {}
    --local diff_target_message = config.viewconfig().vs .. ' ' .. (M.diff_target_ref or 'HEAD')
    --utils.append_cmd_ui(cmd_ui, diff_target_message, true)

    ----- @param diff_buffer_funcs DiffBufferFuncs
    --local on_ready_callback = function(diff_buffer_funcs)
    --    M.setup_hunk_navigation(hunk_cmd, diff_buffer_funcs, cmd_ui)
    --    M.setup_yank_override(diff_buffer_funcs)
    --end
    --M.display_delta_file(cmd, cmd_ui, on_ready_callback)
end

return M
