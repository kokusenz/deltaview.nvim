local M = {}
local config = require('deltaview.config')
local utils = require('deltaview.utils')
local state = require('deltaview.state')

--- Setup all user commands and global keybinds
M.setup = function()
    if config.options.use_deltalua == false then
        M.setup_legacy_delta_commands()
        return
    end

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
        'Open Diff View for a path against a git ref. Usage: Delta [TODO]. Defaults to current buffer path or cwd.'
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
        print('ERROR: Failed to create diff view: ' .. tostring(err))
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
        --TODO menu.whateverfunction
        --require('deltaview.view').run_git_diff_against_file(vim.fn.expand('%:p'), state.diff_target_ref)
    end)
    if not success then
        print('ERROR: Failed to create diff view: ' .. tostring(err))
    end
end

--- @param command_argument vim.api.keyset.create_user_command.command_args
M.Delta = function(command_argument)
    -- TODO figure out function structure
    -- what if I want to use the cur file functionality while also specifying a ref?
    -- what if I don't want to specify the ref, but I want to specify a path?
    -- what if I don't want to change the context, but I want to specify the ref? lot of options
    -- could consider tossing the cur file functionality, or specifying a specific thing like . for it
    -- so it's easy for somebody to type it. ref is harder to write, especially if you want to maintain the ref in memory that is very specific (like a three dot ref for a code review)
    local success, err = pcall(function()
        local custom_path = command_argument.fargs[1]
        state.default_context = command_argument.fargs[1] ~= nil and
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
        -- TODO delta.functiontobeimplemented
    end)
    if not success then
        print('ERROR: Failed to create diff view: ' .. tostring(err))
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

-- ____________________________________________ LEGACY _________________________________________________

--- commands for DeltaView up to v0.1.2, which was using dandavison/delta.
M.setup_legacy_delta_commands = function()
    local diff = require('deltaview.diff_legacy')
    -- Fetch git branches once at setup time
    local branches = vim.fn.systemlist('git branch --format="%(refname:short)"')

    -- :DeltaView command
    vim.api.nvim_create_user_command('DeltaView', function(delta_view_opts)
        local success, err = pcall(function()
            diff.diff_target_ref = (delta_view_opts.args ~= '' and delta_view_opts.args ~= nil) and delta_view_opts.args or
                diff.diff_target_ref
            diff.diffed_files.files = nil
            diff.diffed_files.cur_idx = nil
            local path = vim.fn.expand('%:p')
            if path == nil or path == '' then
                print('WARNING: not a valid path')
                return
            end
            if vim.fn.filereadable(path) == 0 then
                print(
                    'WARNING: not a valid file. Use :Delta to view the diff of the directory, or :DeltaMenu for all diffs')
                return
            end
            diff.run_diff_against_file(path, diff.diff_target_ref)
        end)
        if not success then
            print('ERROR: Failed to create diff view: ' .. tostring(err))
        end
    end, {
        nargs = '?',
        complete = function(arg_lead, cmd_line, _)
            local args = vim.split(cmd_line, '%s+')
            if #args == 2 then
                local refs = { 'HEAD' }
                for _, branch in ipairs(branches) do
                    table.insert(refs, branch)
                end
                return utils.filter_refs(refs, arg_lead)
            end
            return {}
        end,
        desc =
        'Open Diff View against a git ref (branch, commit, tag, etc). Using it with no arguments runs it against the last argument used, or defaults to HEAD.'
    })

    -- :DeltaView global keybind
    if config.options.keyconfig.dv_toggle_keybind ~= nil and config.options.keyconfig.dv_toggle_keybind ~= '' then
        vim.keymap.set('n', config.options.keyconfig.dv_toggle_keybind, function()
            vim.cmd('DeltaView')
        end)
    end

    -- :Delta command
    vim.api.nvim_create_user_command('Delta', function(delta_view_opts)
        local success, err = pcall(function()
            diff.diff_target_ref = (delta_view_opts.fargs[1] ~= nil and delta_view_opts.fargs[1] ~= '') and
                delta_view_opts.fargs[1] or diff.diff_target_ref
            diff.default_context = (delta_view_opts.fargs[2] ~= nil and delta_view_opts.fargs[2] ~= '') and
                tonumber(delta_view_opts.fargs[2]) or diff.default_context
            local custom_path = delta_view_opts.fargs[3]
            assert(delta_view_opts.fargs[4] == nil, 'Delta only accepts up to three args')
            diff.diffed_files.files = nil
            diff.diffed_files.cur_idx = nil

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
            diff.run_diff_against_path(path, diff.diff_target_ref)
        end)
        if not success then
            print('ERROR: Failed to create diff view: ' .. tostring(err))
        end
    end, {
        nargs = '*',
        complete = function(arg_lead, cmd_line, _)
            local args = vim.split(cmd_line, '%s+')

            if #args == 2 then
                local refs = { 'HEAD' }
                for _, branch in ipairs(branches) do
                    table.insert(refs, branch)
                end
                return utils.filter_refs(refs, arg_lead)
            end

            if #args == 3 then
                return { '0', '1', '2', '3' }
            end

            if #args == 4 then
                return vim.fn.getcompletion(arg_lead, 'file')
            end

            return {}
        end,
        desc =
        'Open Diff View for a path against a git ref. Usage: Delta [ref] [context] [path]. Defaults to current buffer path or cwd.'
    })

    -- :Delta global keybind
    if config.options.keyconfig.d_toggle_keybind ~= nil and config.options.keyconfig.d_toggle_keybind ~= '' then
        vim.keymap.set('n', config.options.keyconfig.d_toggle_keybind, function()
            vim.cmd('Delta')
        end)
    end

    -- :DeltaMenu command
    vim.api.nvim_create_user_command('DeltaMenu', function(delta_menu_opts)
        local success, err = pcall(function()
            diff.diff_target_ref = (delta_menu_opts.args ~= '' and delta_menu_opts.args ~= nil) and delta_menu_opts.args or
                diff.diff_target_ref
            diff.create_diff_menu_pane(diff.run_diff_against_file, diff.diff_target_ref)
        end)
        if not success then
            print('ERROR: Failed to create diff menu: ' .. tostring(err))
        end
    end, {
        nargs = '?',
        complete = function(arg_lead, cmd_line, _)
            local args = vim.split(cmd_line, '%s+')
            if #args == 2 then
                local refs = { 'HEAD' }
                for _, branch in ipairs(branches) do
                    table.insert(refs, branch)
                end
                return utils.filter_refs(refs, arg_lead)
            end
            return {}
        end,
        desc =
        'Open Diff Menu against a git ref (branch, commit, tag, etc). Using it with no arguments runs it against the last argument used, or defaults to HEAD.'
    })

    -- :DeltaMenu global keybind
    if config.options.keyconfig.dm_toggle_keybind ~= nil and config.options.keyconfig.dm_toggle_keybind ~= '' then
        vim.keymap.set('n', config.options.keyconfig.dm_toggle_keybind, function()
            vim.cmd('DeltaMenu')
        end)
    end
end

return M
