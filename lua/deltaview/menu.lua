local M = {}
local _quickfix_autocmd_registered = false
local utils = require('deltaview.utils')
local config = require('deltaview.config')
local picker = require('deltaview.picker')
local view = require('deltaview.view')
local help = require('deltaview.help')

--- Creates a menu pane, and orchestrates the logic of switching between a fuzzy finder or a quick select depending on how large the diff is
--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
M.create_diff_menu_pane = function(ref)
    local rev_parse_result = vim.system({ 'git', 'rev-parse', '--show-toplevel' }):wait()
    if rev_parse_result.code ~= 0 and rev_parse_result.code ~= 1 then
        vim.notify('Not in a git repository. Cannot open DeltaView menu for git.', vim.log.levels.WARN)
        return
    end

    assert(ref)
    -- we can poc handling of deleted files first with quickfix list, then raise a separate pr for applying that fix for all pickers
    local sorted_files = utils.get_sorted_diffed_files(ref)
    local mods = utils.get_filenames_from_sortedfiles(sorted_files)

    if #mods == 0 then
        -- TODO allow this to pass through and just open empty quickfix maybe
        vim.notify('No modified files to display', vim.log.levels.INFO)
        return
    end

    --- @type ChangesData
    local changes_data = {}
    for _, value in ipairs(sorted_files) do
        changes_data[value.name] = { changes = '+' .. value.added .. ',-' .. value.removed, status = value.status }
    end

    -- todo need to deprecate stuff but don't make a breaking change without a warning, saying that this will be removed at xxx
    M.setup_quickfix_deltaview_on_entry()
    picker.populate_quickfix_deltamenu_items(ref, mods, changes_data)
    M.choose_deltaview_menu(ref, mods, changes_data)
end


M.setup_quickfix_deltaview_on_entry = function()
    if _quickfix_autocmd_registered then
        return
    end

    --- identifies if the buffer is in the quickfix as a deltaview entry, using bufname
    --- @param bufnr number
    --- @return DeltaViewQfListEntry | nil quickfix_entry entry of getqflist
    --- @return number | nil quickfix_entry entry of getqflist
    local function get_delta_entry(bufnr)
        assert(bufnr)
        local qf_info = vim.fn.getqflist({ items = 1, size = 1 })
        if qf_info.size == 0 then
            return
        end

        local bufname = vim.api.nvim_buf_get_name(bufnr)
        for i, entry in ipairs(qf_info.items) do
            if entry.user_data
                and entry.user_data.deltaview
                and utils.git_rel_to_abs(entry.user_data.bufname) == bufname
            then
                --- @cast entry DeltaViewQfListEntry
                return entry, i
            end
        end
    end

    --- clears deltaview flag of current quickfix list entry
    --- @param bufnr number
    local function clear_delta_entry(bufnr)
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
    local function restore_delta_entries()
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
                local qf_nr = vim.fn.getqflist({ nr = 0 }).nr
                if qf_nr > 1 then
                    vim.cmd('colder')
                else
                    vim.fn.setqflist({}, 'r', { items = {}, title = '' })
                end
                vim.cmd('cclose')
                return
            end

            -- still in the deltamenu workflow but entry should not trigger a diff view
            if not entry.user_data.show_delta_on_entry then
                return
            end

            -- deltamenu entry that should open a diff view
            vim.schedule(function()
                local success, err = pcall(function()
                    restore_delta_entries()
                    clear_delta_entry(ev.buf)
                    -- return to last known cursor position; quickfix without lnum automatically puts you at top
                    local last_pos = vim.api.nvim_buf_get_mark(ev.buf, '"')
                    if last_pos[1] > 0 then
                        vim.api.nvim_win_set_cursor(0, last_pos)
                    end
                    local bufnr = view.deltaview_file(entry.user_data.ref)
                    if bufnr ~= nil then
                        help.register_keybind(bufnr, ']q', 'use quickfix keybind to open next file diff')
                        help.register_keybind(bufnr, '[q', 'use quickfix keybind to open prev file diff')
                    end
                end)
                if not success then
                    vim.notify('An error occured while trying to open DeltaView - ' .. tostring(err),
                        vim.log.levels.ERROR)
                    return
                end
            end)
        end,
    })
    _quickfix_autocmd_registered = true
end


--- orchestrator of which menu to call, based on config or default order (fzf -> telescope -> quickfix)
--- @param ref string git ref to compare against. Can be branch, commit, tag, etc.
--- @param mods string[]
--- @param changes_data ChangesData for each file in mods, the size of the change in the file, and the status ("M", "D", etc.)
M.choose_deltaview_menu = function(ref, mods, changes_data)
    if config.options.fzf_picker == 'fzf-lua' then
        local ok = pcall(require, 'fzf-lua')
        if not ok then
            vim.notify('fzf-lua not found. Falling back to the first picker available.', vim.log.levels.WARN)
            goto default
        end
        -- continue using fzf-lua
        picker.open_deltaview_fzf_lua_menu(ref, mods, changes_data)
        return
    elseif config.options.fzf_picker == 'telescope' then
        local ok = pcall(require, 'telescope')
        if not ok then
            vim.notify('telescope not found. Falling back to the first picker available.', vim.log.levels.WARN)
            goto default
        end
        picker.open_deltaview_telescope_menu(ref, mods, changes_data)
        return
    elseif config.options.fzf_picker == 'quickfix' then
        vim.cmd('copen')
        return
    end
    ::default::
    -- try default order - fzf-lua -> quickfix
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

    -- fallback; just open quickfix menu
    vim.cmd('copen')
end

--- @alias ChangesData table<string, table<string, string>>

return M
