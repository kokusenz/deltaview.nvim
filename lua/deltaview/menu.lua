local M = {}
local utils = require('deltaview.utils')
local view = require('deltaview.view')
local state = require('deltaview.state')
local selector = require('deltaview.selector')
local config = require('deltaview.config')

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

    if #mods >= config.options.fzf_threshold then
    --if #mods >= 1 then
        M.open_deltaview_fzf_menu(ref, mods, changes_data)
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
M.open_deltaview_fzf_menu = function(ref, mods, changes_data)
    assert(ref ~= nil)
    assert(mods ~= nil)
    assert(changes_data ~= nil)

    local on_select_with_key = function(result)
        assert(result ~= nil)
        assert(result[1] ~= nil)
        assert(result[2] ~= nil)

        local key = result[1]
        local filepath = result[2]

        if key == config.options.keyconfig.fzf_toggle then
            M.open_deltaview_fzf_menu(ref, mods, changes_data)
            return
        end

        local selected_idx = nil
        for idx, value in ipairs(mods) do
            if value == filepath then
                selected_idx = idx
            end
        end
        assert(selected_idx ~= nil)

        local success, err = pcall(function()
            vim.cmd('e ' .. utils.git_rel_to_abs(vim.fn.fnameescape(filepath)))
            local bufnr = view.deltaview_file(ref)
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

    local success, err = pcall(function()
        vim.fn['fzf#run'](vim.fn['fzf#wrap']({
            source = mods,
            ['sink*'] = on_select_with_key,
            options = {
                '--style', 'minimal',
                '--layout', 'reverse',
                '--prompt', 'DeltaView Menu > ',
                '--preview', 'if [ -z "$(git ls-files -- {})" ]; then git diff --no-index /dev/null {}; else git diff ' ..
            state.diff_target_ref .. ' -- {}; fi | delta --paging=never',
                '--border-label', 'comparing to ' .. state.diff_target_ref,
                '--expect', config.options.keyconfig.fzf_toggle,
            },
            window = { width = 0.8, height = 0.9, border = 'rounded' }
        }))
    end)
    if not success then
        vim.notify('fzf#run failed: ' .. tostring(err) .. '. Using default picker.', vim.log.levels.WARN)
        M.open_deltaview_quickselect_menu(ref, mods, changes_data)
    end
end

--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
--- @param mods string[]
--- @param changes_data table<string, string> for each file in mods, the size of the change in the file
M.open_deltaview_quickselect_menu = function(ref, mods, changes_data)
    assert(ref ~= nil)
    assert(mods ~= nil)
    assert(changes_data ~= nil)

    --- @param filepath string
    --- @param selected_idx number
    local on_select = function(filepath, selected_idx)
        if filepath == nil then
            return
        end

        local success, err = pcall(function()
            vim.cmd('e ' .. utils.git_rel_to_abs(vim.fn.fnameescape(filepath)))
            local bufnr = view.deltaview_file(ref)
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

    selector.ui_select(mods, {
        prompt = 'DeltaView Menu  |  ' .. config.viewconfig().vs .. ' ' .. (ref),
        label_item = utils.label_filepath_item,
        win_predefined = config.options.quick_select_view,
        additional_data = changes_data
    }, on_select)
end

return M
