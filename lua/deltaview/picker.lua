local M = {}
local utils = require('deltaview.utils')
local state = require('deltaview.state')
local view = require('deltaview.view')
local selector = require('deltaview.selector')

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


--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
--- @param mods string[]
--- @param changes_data table<string, string> for each file in mods, the size of the change in the file
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
        self.win:update_preview_title(' ' .. vim.fn.fnamemodify(entry_str, ':t') .. ' | Delta.lua ')
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
--- @param changes_data table<string, string> for each file in mods, the size of the change in the file
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

return M
