local M = {}
local config = require('deltaview.config')
local utils = require('deltaview.utils')
local state = require('deltaview.state')

--- Setup all user commands and global keybinds
M.setup = function()
    -- fetch git branches once at setup time
    local branches = vim.fn.systemlist('git branch --format="%(refname:short)"')

    vim.api.nvim_create_user_command('DeltaView', M.DeltaView, {
        nargs = '?',
        complete = M.ref_complete(2, branches),
        desc =
        'Open Diff View against a git ref (branch, commit, tag, etc). Using it with no arguments runs it against the last argument used, or defaults to HEAD.'
    })

    -- :DeltaView global keybind
    if config.options.keyconfig.dv_toggle_keybind ~= nil and config.options.keyconfig.dv_toggle_keybind ~= '' then
        vim.keymap.set('n', config.options.keyconfig.dv_toggle_keybind, function()
            vim.cmd('DeltaView')
        end)
    end

    -- :DeltaMenu command
    vim.api.nvim_create_user_command('DeltaMenu', M.DeltaMenu,
    {
        nargs = '?',
        complete = M.ref_complete(2, branches),
        desc =
        'Open Diff Menu against a git ref (branch, commit, tag, etc). Using it with no arguments runs it against the last argument used, or defaults to HEAD.'
    })

    -- :DeltaMenu global keybind
    if config.options.keyconfig.dm_toggle_keybind ~= nil and config.options.keyconfig.dm_toggle_keybind ~= '' then
        vim.keymap.set('n', config.options.keyconfig.dm_toggle_keybind, function()
            vim.cmd('DeltaMenu')
        end)
    end

    -- :Delta command
    vim.api.nvim_create_user_command('Delta', M.Delta, {
        nargs = '*',
        complete = function(arg_lead, cmd_line, _)
            local args = vim.split(cmd_line, '%s+')
            if #args == 2 then
                return vim.fn.getcompletion(arg_lead, 'file')
            end
            if #args == 3 then
                return { '0', '1', '2', '3' }
            end
            if #args == 4 then
                return M.ref_complete(4, branches)(arg_lead, cmd_line, _)
            end
            return {}
        end,
        desc =
        'Open Diff View for a path against a git ref. Usage: Delta [path] [context] [ref]. Defaults to current buffer path or cwd.'
    })

    -- :Delta global keybind
    if config.options.keyconfig.d_toggle_keybind ~= nil and config.options.keyconfig.d_toggle_keybind ~= '' then
        vim.keymap.set('n', config.options.keyconfig.d_toggle_keybind, function()
            vim.cmd('Delta')
        end)
    end
end

--- @param command_argument vim.api.keyset.create_user_command.command_args
M.DeltaView = function(command_argument)
    local success, err = pcall(function()
        state.diff_target_ref = command_argument.fargs[1] ~= nil
            and command_argument.fargs[1]
            or state.diff_target_ref
        state.diffed_files.files = nil
        state.diffed_files.cur_idx = nil
        require('deltaview.view').deltaview_file(state.diff_target_ref)
    end)
    if not success then
        vim.notify('Failed to open DeltaView - ' .. tostring(err), vim.log.levels.ERROR)
    end
end

--- @param command_argument vim.api.keyset.create_user_command.command_args
M.DeltaMenu = function(command_argument)
    local success, err = pcall(function()
        state.diff_target_ref = command_argument.fargs[1] ~= nil
            and command_argument.fargs[1]
            or state.diff_target_ref
        state.diffed_files.files = nil
        state.diffed_files.cur_idx = nil
        require('deltaview.menu').create_diff_menu_pane(state.diff_target_ref)
    end)
    if not success then
        vim.notify('Failed to open DeltaMenu - ' .. tostring(err), vim.log.levels.ERROR)
    end
end

--- @param command_argument vim.api.keyset.create_user_command.command_args
M.Delta = function(command_argument)
    local success, err = pcall(function()
        local custom_path = command_argument.fargs[1]
        state.default_context = command_argument.fargs[2] ~= nil and
            tonumber(command_argument.fargs[2]) or state.default_context
        state.diff_target_ref = command_argument.fargs[3] ~= nil
            and command_argument.fargs[3]
            or state.diff_target_ref
        state.diffed_files.files = nil
        state.diffed_files.cur_idx = nil

        local path
        if custom_path ~= nil and custom_path ~= '' then
            path = vim.fn.fnamemodify(custom_path, ':p')
        else
            path = vim.fn.expand('%:p')
            if path == nil or path == '' then
                -- I want this to be usable from the nvim splashscreen, and there is no path
                path = vim.fn.getcwd()
            end
        end
        require('deltaview.view').delta_path(state.diff_target_ref, state.default_context, path)
    end)
    if not success then
        vim.notify('Failed to open Delta - ' .. tostring(err), vim.log.levels.ERROR)
    end
end

--- @param ref_arg_position number position of the ref in the arguments list of the user command
--- @param branches string[] branches to append to the list of items available in the autocomplete of the user command
M.ref_complete = function(ref_arg_position, branches)
    return function(arg_lead, cmd_line, _)
        local args = vim.split(cmd_line, '%s+')
        if #args == ref_arg_position then
            local refs = { 'HEAD' }
            for _, branch in ipairs(branches) do
                table.insert(refs, branch)
            end
            return utils.filter_refs(refs, arg_lead)
        end
        return {}
    end
end

return M
