local M = {}
local utils = require('deltaview.utils')
local state = require('deltaview.state')
local view = require('deltaview.view')

local _buf_name_seq = 0

M.open_vim_ui_select = function()
    local qf_info = vim.fn.getqflist({ items = 1, size = 1 })
    if qf_info.size == 0 then
        return
    end

    local qf_list = {}
    local mods = {}
    for i, entry in ipairs(qf_info.items) do
        --- @cast entry DeltaViewQfListEntry
        if entry.user_data and entry.user_data.deltaview then
            table.insert(mods, entry.user_data.bufname)
            qf_list[entry.user_data.bufname] = {
                idx = i,
                title = ' ' .. entry.user_data.status
                    .. ' ' .. vim.fn.fnamemodify(entry.user_data.bufname, ':t')
                    .. ' > ' .. entry.user_data.changes .. ' '}
        end
    end

    vim.ui.select(mods, {
        prompt = 'DeltaView Menu',
        format_item = function(item)
            return qf_list[item].title
        end,
    }, function(choice)
        if not choice then return end
        local idx = qf_list[choice].idx
        if idx then
            vim.cmd('cc ' .. idx)
        end
    end)
end

--- TODO integration tests to assert that the preview window behaves as expected for when inside git root, not at git root
--- opens a fzf-lua picker for deltaview entries in the quickfix list with a delta.lua preview window
M.open_deltaview_fzf_lua_menu = function()
    local fzf_lua = require('fzf-lua')
    local builtin = require('fzf-lua.previewer.builtin')

    local DeltaviewPreviewer = builtin.base:extend()

    local qf_info = vim.fn.getqflist({ items = 1, size = 1 })
    if qf_info.size == 0 then
        return
    end

    local qf_list = {}
    local mods = {}
    for i, entry in ipairs(qf_info.items) do
        --- @cast entry DeltaViewQfListEntry
        if entry.user_data and entry.user_data.deltaview then
            table.insert(mods, entry.user_data.bufname)
            qf_list[entry.user_data.bufname] = {
                idx = i,
                ref = entry.user_data.ref,
                title = ' ' .. entry.user_data.status
                    .. ' ' .. vim.fn.fnamemodify(entry.user_data.bufname, ':t')
                    .. ' > ' .. entry.user_data.changes .. ' '}
        end
    end

    function DeltaviewPreviewer:new(o, opts, fzf_win)
        self.super.new(self, o, opts, fzf_win)
        setmetatable(self, DeltaviewPreviewer)
        return self
    end

    function DeltaviewPreviewer:populate_preview_buf(entry_str)
        if not self.win or not self.win:validate_preview() then return end
        local filepath = utils.git_rel_to_abs(entry_str)
        local ref = qf_list[entry_str].ref
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
            local lines = vim.fn.split(tostring(err), "\n")
            vim.api.nvim_buf_set_lines(tmp, 1, -1, false, lines)
            self:set_preview_buf(tmp)
            return
        end
        -- Inform fzf-lua about the new buffer and clean up the old placeholder.
        self.preview_bufnr = bufnr
        self:set_style_winopts()
        self:safe_buf_delete(old_bufnr)
        local title = qf_list[entry_str].title
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
                    local idx = qf_list[selected[1]].idx
                    if idx then
                        vim.cmd('cc ' .. idx)
                    end
                end
            end
        }
    })
end

M.open_deltaview_telescope_menu = function()
    local pickers = require('telescope.pickers')
    local finders = require('telescope.finders')
    local conf = require('telescope.config').values
    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')
    local previewers = require('telescope.previewers')

    local qf_info = vim.fn.getqflist({ items = 1, size = 1 })
    if qf_info.size == 0 then
        return
    end

    local qf_list = {}
    local mods = {}
    for i, entry in ipairs(qf_info.items) do
        --- @cast entry DeltaViewQfListEntry
        if entry.user_data and entry.user_data.deltaview then
            table.insert(mods, entry.user_data.bufname)
            qf_list[entry.user_data.bufname] = {
                idx = i,
                ref = entry.user_data.ref,
                title = ' ' .. entry.user_data.status
                    .. ' ' .. vim.fn.fnamemodify(entry.user_data.bufname, ':t')
                    .. ' > ' .. entry.user_data.changes .. ' '}
        end
    end

    -- Track buffers we create so we can clean them up on teardown.
    local preview_bufs = {}

    local deltaview_previewer = previewers.new({
        title = 'Delta.lua',
        dyn_title = function(_, entry)
            if entry == nil then return 'Delta.lua' end
            return qf_list[entry.value].title
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
                bufnr = view.open_git_diff_buffer_for_path(filepath, qf_list[entry.value].ref, state.default_context, preview_winid,
                    tostring(_buf_name_seq))
            end)
            if not success or bufnr == nil then
                local fallback = vim.api.nvim_create_buf(false, true)
                table.insert(preview_bufs, fallback)
                vim.api.nvim_buf_set_lines(fallback, 0, -1, false, { 'No diff available for: ' .. entry.value })
                local lines = vim.fn.split(tostring(err), "\n")
                vim.api.nvim_buf_set_lines(fallback, 1, -1, false, lines)
                vim.api.nvim_win_set_buf(preview_winid, fallback)
                return
            end

            table.insert(preview_bufs, bufnr)
            vim.schedule(function()
                if vim.api.nvim_win_is_valid(preview_winid) then
                    vim.wo[preview_winid].wrap = false
                end
            end)

            -- Set the preview border title directly; this works regardless of
            -- the user's dynamic_preview_title config value.
            if status.layout.preview.border then
                local title = qf_list[entry.value].title
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

                local idx = qf_list[selected].idx
                if idx then
                    vim.cmd('cc ' .. idx)
                end
            end)
            return true
        end,
    }):find()
end

return M
