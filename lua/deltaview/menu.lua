local M = {}
local _quickfix_autocmd_registered = false
local utils = require('deltaview.utils')
local config = require('deltaview.config')
local picker = require('deltaview.picker')
local view = require('deltaview.view')
local help = require('deltaview.help')

--- get items needed for display in :DeltaMenu. notifies if error
--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
--- @return DeltaMenuItems | nil returns nil if it needs to notify that there is an error
local get_modified_files = function(ref)
    local rev_parse_result = vim.system({ 'git', 'rev-parse', '--show-toplevel' }):wait()
    if rev_parse_result.code ~= 0 and rev_parse_result.code ~= 1 then
        vim.notify('Not in a git repository. Cannot open DeltaView menu for git.', vim.log.levels.WARN)
        return
    end

    assert(ref)
    local sorted_files = utils.get_sorted_diffed_files(ref)
    local mods = utils.get_filenames_from_sortedfiles(sorted_files)

    if #mods == 0 then
        vim.notify('No changes to display.', vim.log.levels.INFO)
        return
    end

    --- @type ChangesData
    local changes_data = {}
    for _, value in ipairs(sorted_files) do
        changes_data[value.name] = { changes = '+' .. value.added .. ',-' .. value.removed, status = value.status }
    end
    return { mods = mods, changes_data = changes_data, ref = ref }
end

--- @type fun(dv_data: DeltaViewQfListEntryUserData): nil
local open_deltaview_on_buffer = function(dv_data)
    vim.schedule(function()
        local success, err = pcall(function()
            -- return to last known cursor position; quickfix without lnum automatically puts you at top
            -- commented out; can be confusing when restarting nvim sessions
            -- while it's a nice qol to jump back to where you were, DiffTool also doesn't have this behavior. ok to leave it out
            -- local last_pos = vim.api.nvim_buf_get_mark(0, '"')
            -- if last_pos[1] > 0 then
            --     vim.api.nvim_win_set_cursor(0, last_pos)
            -- end
            local dv_bufid
            if dv_data.status == 'D' then
                -- delta_path works for deleted files, while deltaview_file doesn't because it expects a real file to exist to function off of.
                -- slight design discrepancy here; this has the delta.lua header, while the others don't. But I can live with that.
                -- alternative is to refactor deltaview_file to no longer assume it is being called from a real file, and take in a path like delta_path does
                dv_bufid = view.delta_path(dv_data.ref, require('deltaview.state').default_context, dv_data.abs_path)
            else
                dv_bufid = view.deltaview_file(dv_data.ref)
            end
            if dv_bufid ~= nil then
                help.register_keybind(dv_bufid, ':DeltaMenu! [ref]',
                    'Populate the quickfix list with all diff files, then open it')
                help.register_keybind(dv_bufid, ']q / [q ',
                    'Use native quickfix keybind to open next diff file or prev diff file if in quickfix list')
                help.register_keybind(dv_bufid, ':colder OR :cex []',
                    'Restore the previous quickfix list, exiting the DeltaMenu review workflow')

                -- flagging breaking changes
                if config.options.keyconfig.next_diff ~= nil and config.options.keyconfig.next_diff ~= '' then
                    vim.keymap.set('n', config.options.keyconfig.next_diff, function()
                        vim.notify([[Deltaview next_diff keybind has been removed. You can achieve the original function of this keybind by first populating the quickfix list using `:DeltaMenu! [ref]`, then using ']q', or `:cnext`. Please read CHANGELOG.txt for v0.3.0 for more details. This warning will be removed in the near future.]], vim.log.levels.WARN)
                    end)
                end

                if config.options.keyconfig.prev_diff ~= nil and config.options.keyconfig.prev_diff ~= '' then
                    vim.keymap.set('n', config.options.keyconfig.prev_diff, function()
                        vim.notify([[Deltaview prev_diff keybind has been removed. You can achieve the original function of this keybind by first populating the quickfix list using `:DeltaMenu! [ref]`, then using '[q', or `:cprev`. Please read CHANGELOG.txt for v0.3.0 for more details. This warning will be removed in the near future.]], vim.log.levels.WARN)
                    end)
                end
            end
        end)
        if not success then
            vim.notify('An error occured while trying to open DeltaView - ' .. tostring(err),
                vim.log.levels.ERROR)
            return
        end
    end)
end

--- @param deltamenu_items DeltaMenuItems
--- @return DeltaViewQfListEntry[]
local get_deltaview_qf_list_entries = function(deltamenu_items)
    assert(deltamenu_items.ref ~= nil)
    assert(deltamenu_items.mods ~= nil)
    assert(deltamenu_items.changes_data ~= nil)

    local qflist = {}
    for _, path in ipairs(deltamenu_items.mods) do
        local text = path
        local status = deltamenu_items.changes_data[path].status
        --- @cast status Status
        local filepath
        if status == 'D' then
            -- need /tmp because this isn't a scratch buffer neovim controls the deletion of
            filepath = '/tmp/deltaview://deleted/' .. utils.git_rel_to_abs(path)
        else
            filepath = utils.git_rel_to_abs(path)
        end
        --- @class DeltaViewQfListEntry
        local qflist_entry = {
            filename = filepath,
            text = text,
            --- @class DeltaViewQfListEntryUserData
            user_data = {
                deltaview = true,                      -- identifier, allows us to confidently use @cast DeltaViewQfListEntry
                bufname = path,
                abs_path = utils.git_rel_to_abs(path), -- note that this is different from filename; is the same most of the time, but for deleted files, can be different
                show_delta_on_entry = true,
                ref = deltamenu_items.ref,
                status = status,
                changes = deltamenu_items.changes_data[path].changes,
            }
        }
        table.insert(qflist, qflist_entry)
    end
    --- @cast qflist DeltaViewQfListEntry[]
    return qflist
end

--- Creates a menu pane, and orchestrates the logic of switching between a fuzzy finder or a quick select depending on how large the diff is
--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
M.create_diff_menu_pane = function(ref)
    local deltamenu_items = get_modified_files(ref)
    if deltamenu_items == nil then return end
    local deltaview_qf_list_entries = get_deltaview_qf_list_entries(deltamenu_items)
    M.choose_deltaview_menu(deltaview_qf_list_entries)
end

--- Populates the quickfix menu with all entries, with metadata on the items such that autocmd's can recognize when a diff buffer should be opened.
M.populate_quickfix_deltamenu_items = function()
    local deltamenu_items = get_modified_files(require('deltaview.state').diff_target_ref)
    if deltamenu_items == nil then return end
    local qflist = get_deltaview_qf_list_entries(deltamenu_items)

    vim.fn.setqflist({}, ' ', {
        nr = '$',
        title = 'DeltaView Menu  |  ' .. config.viewconfig().vs .. ' ' .. (deltamenu_items.ref),
        items = qflist,
        ---@param info {id: number, start_idx: number, end_idx: number}
        quickfixtextfunc = function(info)
            --- @type table[]
            local items = vim.fn.getqflist({ id = info.id, items = 1 }).items
            local out = {}
            for item = info.start_idx, info.end_idx do
                local entry = items[item]
                if entry.user_data and entry.user_data.deltaview then
                    table.insert(out,
                        entry.user_data.status .. ' ' .. entry.user_data.bufname .. ' > ' .. entry.user_data.changes)
                end
            end
            return out
        end,
    })
end

--- orchestrator of which picker to use, based on config or default order; see fzf_picker in lua/deltaview/config.lua
--- @param deltaview_qf_list DeltaViewQfListEntry[]
M.choose_deltaview_menu = function(deltaview_qf_list)
    if config.options.fzf_picker == 'fzf-lua' then
        local ok = pcall(require, 'fzf-lua')
        if not ok then
            vim.notify('fzf-lua not found. Falling back to the first picker available.', vim.log.levels.WARN)
            goto default
        end
        -- continue using fzf-lua
        picker.open_deltaview_fzf_lua_menu(deltaview_qf_list, open_deltaview_on_buffer)
        return
    elseif config.options.fzf_picker == 'telescope' then
        local ok = pcall(require, 'telescope')
        if not ok then
            vim.notify('telescope not found. Falling back to the first picker available.', vim.log.levels.WARN)
            goto default
        end
        picker.open_deltaview_telescope_menu(deltaview_qf_list, open_deltaview_on_buffer)
        return
    elseif config.options.fzf_picker == 'ui_select' then
        picker.open_vim_ui_select(deltaview_qf_list, open_deltaview_on_buffer)
        return
    end
    ::default::
    local fzf_lua_ok = pcall(require, 'fzf-lua')
    if fzf_lua_ok then
        picker.open_deltaview_fzf_lua_menu(deltaview_qf_list, open_deltaview_on_buffer)
        return
    end

    local telescope_ok = pcall(require, 'telescope')
    if telescope_ok then
        picker.open_deltaview_telescope_menu(deltaview_qf_list, open_deltaview_on_buffer)
        return
    end

    picker.open_vim_ui_select(deltaview_qf_list, open_deltaview_on_buffer)
end

M.setup_quickfix_deltaview_on_entry = function()
    if _quickfix_autocmd_registered then
        return
    end

    --- identifies if the buffer is in the quickfix as a deltaview entry, using bufname
    --- @param bufnr number
    --- @return DeltaViewQfListEntry | nil quickfix_entry entry of getqflist
    --- @return number | nil quickfix_entry entry of getqflist
    local get_delta_entry = function(bufnr)
        assert(bufnr)
        local qf_info = vim.fn.getqflist({ items = 1, size = 1 })
        if qf_info.size == 0 then
            return
        end

        local bufname = vim.api.nvim_buf_get_name(bufnr)
        if string.match(bufname, 'deltaview://deleted/') then
            -- if this is a buffer we created to represent a deleted buffer, the naming is weird. So this will match it up.
            bufname = string.gsub(bufname, '.*/deltaview://deleted/', '')
        end
        for i, entry in ipairs(qf_info.items) do
            if
                entry.user_data
                and entry.user_data.deltaview
                and entry.user_data.abs_path == bufname
            then
                --- @cast entry DeltaViewQfListEntry
                return entry, i
            end
        end
    end

    --- clears deltaview flag of current quickfix list entry
    --- @param bufnr number
    local clear_delta_entry = function(bufnr)
        assert(bufnr)
        local entry, idx = get_delta_entry(bufnr)
        if
            entry
            and entry.user_data
            and entry.user_data.deltaview
        then
            local current_qflist = vim.fn.getqflist({ all = 1 }).items
            if current_qflist[idx] and current_qflist[idx].user_data then
                current_qflist[idx].user_data.show_delta_on_entry = false
                vim.fn.setqflist({}, 'r', { items = current_qflist, idx = idx })
            end
        end
    end

    --- restores deltaview user_data flag for all quickfix list entries
    local restore_delta_entries = function()
        --- @type {items: table[], size: number}
        local qf_info = vim.fn.getqflist({ items = 1, size = 1 })
        local idx = vim.fn.getqflist({ idx = 0 }).idx
        if qf_info.size == 0 then
            return
        end

        for _, entry in ipairs(qf_info.items) do
            if entry.user_data and entry.user_data.deltaview and not entry.user_data.show_delta_on_entry then
                entry.user_data.show_delta_on_entry = true
            end
        end
        vim.fn.setqflist({}, 'r', { items = qf_info.items, idx = idx })
    end

    vim.api.nvim_create_autocmd('BufWinEnter', {
        pattern = '*',
        callback = function(ev)
            if vim.bo[ev.buf].buftype ~= '' then
                return
            end

            local entry, _ = get_delta_entry(ev.buf)

            -- left the deltamenu workflow entirely: restore/clear the quickfix list
            if entry == nil then
                utils.undo_deltamenu_qf_list()
                return
            end

            -- still in the deltamenu workflow but entry should not trigger a diff view
            if not entry.user_data.show_delta_on_entry then
                return
            end

            vim.schedule(function()
                restore_delta_entries()
                clear_delta_entry(ev.buf)
            end)
            open_deltaview_on_buffer(entry.user_data)
        end,
    })
    _quickfix_autocmd_registered = true
end

M.setup_quickfix_deltaview_on_entry()

--- key is filepath, values are tables where key is type of change, value is value
--- for example, change type "changes" has "+23,-16", and change type "status" has "M", or "D", etc.
--- @alias ChangesData table<string, table<string, string>>

--- @class DeltaMenuItems
--- @field mods string[] list of changed filepaths
--- @field changes_data ChangesData list of changes data, where the keys are 1 to 1 with mods
--- @field ref string

return M
