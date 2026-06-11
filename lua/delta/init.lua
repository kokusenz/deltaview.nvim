---@class Delta
local M = {}
local config = require('delta.config')
local utils_highlighting = require('delta.utils_highlighting')
local diff = require('delta.diff')
local utils = require('delta.utils')

---@param opts DeltaOpts
M.setup = function(opts)
    config.setup(opts)
    utils_highlighting.initialize_hl_groups()
end

utils_highlighting.initialize_hl_groups()

-- API
M.git_diff = diff.git_diff
M.text_diff = diff.text_diff
M.patch_diff = diff.patch_diff
M.highlight_delta_artifacts = diff.highlight_delta_artifacts
M.syntax_highlight_git_diff = diff.syntax_highlight_git_diff
M.syntax_highlight_diff_set = diff.syntax_highlight_diff_set
M.diff_highlight_diff = diff.diff_highlight_diff
M.setup_delta_statuscolumn = diff.setup_delta_statuscolumn

---@class DeltaParse
local parse = {}
parse.get_diff_data_git = diff.get_diff_data_git
parse.get_diff_data = diff.get_diff_data
parse.get_language_from_filename = utils.get_language_from_filename
M.parse = parse

-- Example Usages of Api

--- Test function for git diff workflow. This is a typical sequence.
--- @param ref string
M.test_git_diff = function(ref)
    ref = ref or 'HEAD'
    local cur_path
    local ok, expanded = pcall(vim.fn.expand, '%:p')
    if ok and expanded ~= '' then
        cur_path = expanded
    else
        cur_path = nil
    end

    local bufnr = M.git_diff(ref, nil, {})
    if bufnr == nil then
        return -- Error already notified
    end

    vim.api.nvim_win_set_buf(0, bufnr)
    M.highlight_delta_artifacts(bufnr)
    M.syntax_highlight_git_diff(bufnr)
    M.diff_highlight_diff(bufnr)
    M.setup_delta_statuscolumn(bufnr)
end

--- Test function for git diff workflow where each decorating function is called async. Allows the buf to start rendering
--- before specifics are applied, but each function still suffers from cursor lock/textlock
--- @param ref string
M.test_git_diff_async = function(ref)
    ref = ref or 'HEAD'
    local cur_path
    local ok, expanded = pcall(vim.fn.expand, '%:p')
    if ok and expanded ~= '' then
        cur_path = expanded
    else
        cur_path = nil
    end

    local bufnr = M.git_diff(ref, nil, {})
    if bufnr == nil then
        return -- Error already notified
    end

    vim.api.nvim_win_set_buf(0, bufnr)
    vim.schedule(function() M.highlight_delta_artifacts(bufnr) end)
    vim.schedule(function() M.syntax_highlight_git_diff(bufnr) end)
    vim.schedule(function() M.diff_highlight_diff(bufnr) end)
    vim.schedule(function() M.setup_delta_statuscolumn(bufnr) end)
end

--- Test function for text diff workflow. This is a typical sequence.
--- @param s1 string
--- @param s2 string
--- @param lang lang
M.test_text_diff = function(s1, s2)
    local original =
    "local x = 1\nlocal y = 2\nlocal z = 3\n-- a comment\n-- a second comment\n-- a third comment\n-- a fourth comment\n-- a fourth comment\n-- a fifth comment\n-- a sixth comment\nlocal l = 'original'"
    local modified =
    "local x = 1\nlocal y = 10\nlocal z = 3\n-- a comment\n-- a second comment\n-- a third comment\n-- a fourth comment\n-- a fourth comment\n-- a fifth comment\n-- a sixth comment\nlocal l = 'new'"

    local bufnr = M.text_diff(s1 or original, s2 or modified, 'lua', {})
    if bufnr == nil then
        return
    end

    vim.api.nvim_win_set_buf(0, bufnr)
    M.highlight_delta_artifacts(bufnr)
    M.syntax_highlight_diff_set(bufnr)
    M.diff_highlight_diff(bufnr)
    M.setup_delta_statuscolumn(bufnr)
end

--- Test function for patch_diff workflow. This is a typical sequence.
M.test_patch_diff = function(use_current_file, is_git, language)
    if use_current_file and not is_git and not language then
        vim.notify("language is expected when used on a non git patch file", vim.log.levels.WARN)
    end
    local diffstring = table.concat({
        "@@ -1,4 +1,4 @@",
        " local x = 1",
        "-local y = 2",
        "+local y = 10",
        " local z = 3",
        " local w = 4",
    }, "\n")
    if use_current_file then
        local file_lines = utils.read_file_lines(vim.fn.expand('%:p'))
        if file_lines == nil then
            return
        end
        diffstring = table.concat(file_lines, '\n')
    end
    local lang = use_current_file and language

    local bufnr = M.patch_diff(diffstring, is_git or false, not use_current_file and 'lua' or lang, {})
    if bufnr == nil then
        return
    end
    vim.api.nvim_win_set_buf(0, bufnr)
    M.highlight_delta_artifacts(bufnr)
    M.syntax_highlight_diff_set(bufnr)
    M.diff_highlight_diff(bufnr)
    M.setup_delta_statuscolumn(bufnr)
end

return M
