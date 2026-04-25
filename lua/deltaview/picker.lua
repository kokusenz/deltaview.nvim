local M = {}
local utils = require('deltaview.utils')
local state = require('deltaview.state')
local view = require('deltaview.view')
local selector = require('deltaview.selector')
local config = require('deltaview.config')
local help = require('deltaview.help')

local _buf_name_seq = 0

--- TODO remove mods and all that maybe, if i can just go off the content in the quickfix list only? just query the current quickfix list, assert that it is populated the way I want
--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
--- @param mods string[]
--- @param changes_data ChangesData for each file in mods, the size of the change in the file
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
        _buf_name_seq = _buf_name_seq + 1
        local bufnr = nil
        local success, err = pcall(function()
            bufnr = view.open_git_diff_buffer_for_path(filepath, ref, state.default_context, preview_winid,
                tostring(_buf_name_seq))
        end)
        if not success or bufnr == nil then
            local tmp = self:get_tmp_buffer()
            vim.api.nvim_buf_set_lines(tmp, 0, -1, false, { 'No diff available for: ' .. entry_str })
            vim.api.nvim_buf_set_lines(tmp, 1, -1, false, { tostring(err) })
            self:set_preview_buf(tmp)
            return
        end
        -- Inform fzf-lua about the new buffer and clean up the old placeholder.
        self.preview_bufnr = bufnr
        self:set_style_winopts()
        vim.wo[self.win.preview_winid].wrap = true
        self:safe_buf_delete(old_bufnr)
        local title = ' ' .. changes_data[entry_str].status .. ' '
            .. vim.fn.fnamemodify(entry_str, ':t') .. ' > '
            .. changes_data[entry_str].changes .. ' '
        self.win:update_preview_title(title)
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
                end
            end
        }
    })
end

--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
--- @param mods string[]
--- @param changes_data ChangesData for each file in mods, the size of the change in the file
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
            return ' ' .. changes_data[entry.value].status .. ' '
                .. vim.fn.fnamemodify(entry.value, ':t') .. ' '
                .. changes_data[entry.value].changes .. ' '
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

            _buf_name_seq = _buf_name_seq + 1
            local bufnr = nil
            local success, err = pcall(function()
                bufnr = view.open_git_diff_buffer_for_path(filepath, ref, state.default_context, preview_winid,
                    tostring(_buf_name_seq))
            end)
            if not success or bufnr == nil then
                local fallback = vim.api.nvim_create_buf(false, true)
                table.insert(preview_bufs, fallback)
                vim.api.nvim_buf_set_lines(fallback, 0, -1, false, { 'No diff available for: ' .. entry.value })
                vim.api.nvim_buf_set_lines(fallback, 1, -1, false, { tostring(err) })
                vim.api.nvim_win_set_buf(preview_winid, fallback)
                return
            end

            table.insert(preview_bufs, bufnr)
            vim.wo[preview_winid].wrap = true

            -- Set the preview border title directly; this works regardless of
            -- the user's dynamic_preview_title config value.
            if status.layout.preview.border then
                local title = ' ' .. changes_data[entry.value].status .. ' '
                    .. vim.fn.fnamemodify(entry.value, ':t') .. ' '
                    .. changes_data[entry.value].changes .. ' '
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
