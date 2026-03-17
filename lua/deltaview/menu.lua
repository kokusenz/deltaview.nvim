local M = {}
local utils = require('deltaview.utils')
local view = require('deltaview.view')
local state = require('deltaview.state')
local config = require('deltaview.config')
local picker = require('deltaview.picker')

--- Creates a menu pane, and orchestrates the logic of switching between a fuzzy finder or a quick select depending on how large the diff is
--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
M.create_diff_menu_pane = function(ref)
    local rev_parse_result = vim.system({ 'git', 'rev-parse', '--show-toplevel' }):wait()
    if rev_parse_result.code ~= 0 and rev_parse_result.code ~= 1 then
        vim.notify('Not in a git repository. Cannot open DeltaView menu for git.', vim.log.levels.WARN)
        return
    end

    assert(ref)
    local sorted_files = utils.get_sorted_diffed_files(ref)
    local mods = utils.get_filenames_from_sortedfiles(sorted_files)

    if #mods == 0 then
        vim.notify('No modified files to display', vim.log.levels.INFO)
        return
    end

    --- @type table<string, string[]>
    local changes_data = {}
    for _, value in ipairs(sorted_files) do
        changes_data[value.name] = { '+' .. value.added .. ',-' .. value.removed }
    end

    if #mods >= config.options.fzf_threshold then
        M.choose_deltaview_fzf_menu(ref, mods, changes_data)
        return
    end
    picker.open_deltaview_quickselect_menu(ref, mods, changes_data)
end

--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
--- @param mods string[]
--- @param changes_data table<string, string[]> for each file in mods, the size of the change in the file
M.choose_deltaview_fzf_menu = function(ref, mods, changes_data)
    if config.options.fzf_picker == 'fzf-lua' then
        local ok = pcall(require, 'fzf-lua')
        if not ok then
            vim.notify('fzf-lua not found. attempting to use the first picker available.', vim.log.levels.WARN)
            goto default
        end
        -- continue using fzf-lua
        picker.open_deltaview_fzf_lua_menu(ref, mods, changes_data)
        return
    elseif config.options.fzf_picker == 'telescope' then
        local ok = pcall(require, 'telescope')
        if not ok then
            vim.notify('telescope not found. attempting to use the first picker available.', vim.log.levels.WARN)
            goto default
        end
        picker.open_deltaview_telescope_menu(ref, mods, changes_data)
        return
    elseif config.options.fzf_picker == 'fzf' then
        -- this function already naturally falls back to quickselect. no need to notify or configure fallback
        picker.open_deltaview_fzf_junegunn_menu(ref, mods, changes_data)
        return
    end
    ::default::
    -- try default order - fzf-lua -> fzf -> quick_select
    local fzf_lua_ok = pcall(require, 'fzf-lua')
    if fzf_lua_ok then
        picker.open_deltaview_fzf_lua_menu(ref, mods, changes_data)
        return
    end

    local telescope_ok = pcall(require, 'telescope')
    if telescope_ok then
        picker.open_deltaview_telescope_menu(ref, mods, changes_data)
        return
    end

    -- fallback - use fzf, which falls back to quickselect if fzf cannot be found
    picker.open_deltaview_fzf_junegunn_menu(ref, mods, changes_data)
end

return M
