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

    local changes_data = {}
    for _, value in ipairs(sorted_files) do
        changes_data[value.name] = { '+' .. value.added .. ',-' .. value.removed }
    end

    --if #mods >= config.options.fzf_threshold then
    if #mods >= 1 then
        M.choose_deltaview_fzf_menu(ref, mods, changes_data)
        return
    end
    M.open_deltaview_quickselect_menu(ref, mods, changes_data)
end

--- @param bufnr number
M.decorate_deltaview_with_next_keybinds = function(bufnr)
    local adjacent_files = utils.get_adjacent_files(state.diffed_files)
    if adjacent_files ~= nil then
        local next_diff_message = ''
        if config.options.show_verbose_nav then
            next_diff_message = next_diff_message ..
                vim.fn.fnamemodify(adjacent_files.prev, ':t') .. ' ' .. config.viewconfig().prev
        end
        next_diff_message = next_diff_message ..
            ' [' .. state.diffed_files.cur_idx ..
            '|' .. #state.diffed_files.files ..
            '] ' .. config.viewconfig().next ..
            ' ' .. vim.fn.fnamemodify(adjacent_files.next, ':t') ..
            '    '

        local name = vim.api.nvim_buf_get_name(bufnr)
        vim.api.nvim_buf_set_name(bufnr, name .. '    ' .. next_diff_message)

        vim.keymap.set('n', config.options.keyconfig.next_diff, function()
            M.programmatically_select_diff_from_menu(adjacent_files.next)
        end, { buffer = bufnr, silent = true })

        vim.keymap.set('n', config.options.keyconfig.prev_diff, function()
            M.programmatically_select_diff_from_menu(adjacent_files.prev)
        end, { buffer = bufnr, silent = true })
    end
end

--- select from diff menu programmatically
M.programmatically_select_diff_from_menu = function(filepath)
    local rev_parse_result = vim.system({ 'git', 'rev-parse', '--show-toplevel' }):wait()
    if rev_parse_result.code ~= 0 and rev_parse_result.code ~= 1 then
        vim.notify('Not in a git repository. Cannot open git diff delta.lua buffer.', vim.log.levels.WARN)
        return
    end

    local sorted_files = utils.get_sorted_diffed_files(state.diff_target_ref)
    local mods = utils.get_filenames_from_sortedfiles(sorted_files)

    local selected_idx = nil
    for idx, value in ipairs(mods) do
        if value == filepath then
            selected_idx = idx
        end
    end
    assert(selected_idx ~= nil, 'filepath not found in list of diffed files.')

    local success, err = pcall(function()
        vim.cmd('e ' .. utils.git_rel_to_abs(vim.fn.fnameescape(filepath)))
        local bufnr = view.deltaview_file(state.diff_target_ref)
        if bufnr == nil then
            return
        end
        state.diffed_files.files = mods
        state.diffed_files.cur_idx = selected_idx
        M.decorate_deltaview_with_next_keybinds(bufnr)
    end)
    if not success then
        vim.notify('An error occured while trying to open DeltaView - ' .. tostring(err), vim.log.levels.ERROR)
        return
    end
end

--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
--- @param mods string[]
--- @param changes_data table<string, string> for each file in mods, the size of the change in the file
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
        print('TODO implement telescope picker')
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
        print('TODO implement telescope picker')
        return
    end

    -- fallback - use fzf, which falls back to quickselect if fzf cannot be found
    picker.open_deltaview_fzf_junegunn_menu(ref, mods, changes_data)
end

return M
