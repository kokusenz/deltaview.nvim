local M = {}
local utils = require('deltaview.utils')
local state = require('deltaview.state')
local view = require('deltaview.view')
local selector = require('deltaview.selector')
local config = require('deltaview.config')

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

--- @param filepath string
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
--- @param changes_data table<string, string[]> for each file in mods, the size of the change in the file
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


--- TODO replace the total diff with full context with a git specific diff after implementing git diff
--- should also make sure the "buffer with this name already exists" bug when opening deltamenu from a deltaview buffer gets resolved by this
--- this will also address the issue where new files don't preview
--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
--- @param mods string[]
--- @param changes_data table<string, string[]> for each file in mods, the size of the change in the file
M.open_deltaview_fzf_lua_menu = function(ref, mods, changes_data)
    local fzf_lua = require('fzf-lua')
    local builtin = require('fzf-lua.previewer.builtin')

    local DeltaviewPreviewer = builtin.base:extend()

    function DeltaviewPreviewer:new(o, opts, fzf_win)
        self.super.new(self, o, opts, fzf_win)
        setmetatable(self, DeltaviewPreviewer)
        return self
    end

    function DeltaviewPreviewer:populate_preview_buf(entry_str)
        if not self.win or not self.win:validate_preview() then return end
        local filepath = utils.git_rel_to_abs(entry_str)
        if filepath == nil then return end
        local preview_winid = self.win.preview_winid
        local old_bufnr = vim.api.nvim_win_get_buf(preview_winid)
        local bufnr = view.open_git_diff_buffer(filepath, ref, preview_winid)
        if bufnr == nil then
            local tmp = self:get_tmp_buffer()
            vim.api.nvim_buf_set_lines(tmp, 0, -1, false, { 'No diff available for: ' .. entry_str })
            self:set_preview_buf(tmp)
            return
        end
        -- Inform fzf-lua about the new buffer and clean up the old placeholder.
        self.preview_bufnr = bufnr
        self:set_style_winopts()
        vim.wo[self.win.preview_winid].wrap = true
        self:safe_buf_delete(old_bufnr)
        self.win:update_preview_title(' ' .. vim.fn.fnamemodify(entry_str, ':t') .. ' | '
            .. tostring(changes_data[entry_str][1] or ''))
    end

    fzf_lua.fzf_exec(mods, {
        prompt = 'DeltaView Menu > ',
        winopts = {
            title = 'comparing to ' .. state.diff_target_ref,
        },
        previewer = DeltaviewPreviewer,
        actions = {
            ['default'] = function(selected)
                if selected and selected[1] then
                    local selected_idx = nil
                    for idx, value in ipairs(mods) do
                        if value == selected[1] then
                            selected_idx = idx
                        end
                    end
                    assert(selected_idx ~= nil)
                    vim.cmd('e ' .. utils.git_rel_to_abs(vim.fn.fnameescape(selected[1])))
                    local bufnr = view.deltaview_file(state.diff_target_ref)
                    if bufnr == nil then
                        return
                    end
                    state.diffed_files.files = mods
                    state.diffed_files.cur_idx = selected_idx
                    M.decorate_deltaview_with_next_keybinds(bufnr)
                end
            end
        }
    })
end

--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
--- @param mods string[]
--- @param changes_data table<string, string[]> for each file in mods, the size of the change in the file
M.open_deltaview_fzf_junegunn_menu = function(ref, mods, changes_data)
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
            M.open_deltaview_quickselect_menu(ref, mods, changes_data)
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

    -- TODO now that there is no expectation of having delta installed, make this delta if exists, otherwise, just regular git diff is ok
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

--- TODO replace the total diff with full context with a git specific diff after implementing git diff
--- this will also address the issue where new files don't preview
--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
--- @param mods string[]
--- @param changes_data table<string, string[]> for each file in mods, the size of the change in the file
M.open_deltaview_telescope_menu = function(ref, mods, changes_data)
    assert(ref ~= nil)
    assert(mods ~= nil)
    assert(changes_data ~= nil)

    local telescope = require('telescope')
    local pickers = require('telescope.pickers')
    local finders = require('telescope.finders')
    local conf = require('telescope.config').values
    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')
    local previewers = require('telescope.previewers')

    -- Track buffers we create so we can clean them up on teardown.
    local preview_bufs = {}

    local deltaview_previewer = previewers.new({
        title = 'Delta.lua',
        dyn_title = function(_, entry)
            if entry == nil then return 'Delta.lua' end
            return ' ' .. vim.fn.fnamemodify(entry.value, ':t') .. ' | ' .. changes_data[entry.value][1]
        end,
        setup = function(_self)
            return {}
        end,
        teardown = function(_self)
            for _, bufnr in ipairs(preview_bufs) do
                if vim.api.nvim_buf_is_valid(bufnr) then
                    vim.api.nvim_buf_delete(bufnr, { force = true })
                end
            end
            preview_bufs = {}
        end,
        preview_fn = function(_self, entry, status)
            local preview_winid = status.layout.preview and status.layout.preview.winid
            if not preview_winid or not vim.api.nvim_win_is_valid(preview_winid) then return end

            local filepath = utils.git_rel_to_abs(entry.value)
            if filepath == nil then
                local fallback = vim.api.nvim_create_buf(false, true)
                table.insert(preview_bufs, fallback)
                vim.api.nvim_buf_set_lines(fallback, 0, -1, false, { 'No diff available for: ' .. entry.value })
                vim.api.nvim_win_set_buf(preview_winid, fallback)
                return
            end

            local bufnr = view.open_git_diff_buffer(filepath, ref, preview_winid)
            if bufnr == nil then
                local fallback = vim.api.nvim_create_buf(false, true)
                table.insert(preview_bufs, fallback)
                vim.api.nvim_buf_set_lines(fallback, 0, -1, false, { 'No diff available for: ' .. entry.value })
                vim.api.nvim_win_set_buf(preview_winid, fallback)
                return
            end

            table.insert(preview_bufs, bufnr)
            vim.wo[preview_winid].wrap = true

            -- Set the preview border title directly; this works regardless of
            -- the user's dynamic_preview_title config value.
            if status.layout.preview.border then
                local title = ' ' .. vim.fn.fnamemodify(entry.value, ':t') .. ' | ' .. changes_data[entry.value][1]
                status.layout.preview.border:change_title(title)
            end
        end,
    })

    pickers.new({}, {
        prompt_title = 'DeltaView Menu',
        results_title = 'comparing to ' .. state.diff_target_ref,
        finder = finders.new_table({
            results = mods,
        }),
        sorter = conf.generic_sorter({}),
        previewer = deltaview_previewer,
        dynamic_preview_title = true,
        attach_mappings = function(prompt_bufnr, _map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection == nil then return end

                local selected = selection.value
                local selected_idx = nil
                for idx, value in ipairs(mods) do
                    if value == selected then
                        selected_idx = idx
                    end
                end
                assert(selected_idx ~= nil)

                local success, err = pcall(function()
                    vim.cmd('e ' .. utils.git_rel_to_abs(vim.fn.fnameescape(selected)))
                    local bufnr = view.deltaview_file(ref)
                    if bufnr == nil then return end
                    state.diffed_files.files = mods
                    state.diffed_files.cur_idx = selected_idx
                    M.decorate_deltaview_with_next_keybinds(bufnr)
                end)
                if not success then
                    vim.notify('An error occured while trying to open DeltaView - ' .. tostring(err),
                        vim.log.levels.ERROR)
                end
            end)
            return true
        end,
    }):find()
end

return M
