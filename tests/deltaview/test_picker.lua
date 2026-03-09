local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                package.loaded['deltaview.utils'] = {
                    get_adjacent_files = function(_diffed_files) return nil end,
                    get_sorted_diffed_files = function(_ref) return {} end,
                    get_filenames_from_sortedfiles = function(_sf) return {} end,
                    git_rel_to_abs = function(p) return p end,
                    label_filepath_item = function(item) return item end,
                }
                package.loaded['deltaview.state'] = {
                    diffed_files = { files = {}, cur_idx = 1 },
                    diff_target_ref = 'HEAD',
                }
                package.loaded['deltaview.config'] = {
                    options = {
                        show_verbose_nav = false,
                        keyconfig = {
                            next_diff = ']d',
                            prev_diff = '[d',
                            fzf_toggle = 'ctrl-t',
                        },
                        quick_select_view = nil,
                    },
                    viewconfig = function()
                        return { vs = '|', next = '->', prev = '<-' }
                    end,
                }
                package.loaded['deltaview.selector'] = {
                    ui_select = function(_items, _opts, _on_select) end,
                }
                package.loaded['deltaview.view'] = {
                    deltaview_file = function(_ref) return nil end,
                    open_git_diff_buffer = function(_filepath, _ref, _winid) return nil end,
                }

                vim.notify = function(msg, _level)
                    _G.fixture.notified = msg
                end

                M = require('deltaview.picker')
            ]])
            child.lua([[_G.fixture = {}]])
        end,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- decorate_deltaview_with_next_keybinds() - example based tests

T['decorate_deltaview_with_next_keybinds()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- Create a real scratch buffer so buf_get/set_name work normally.
                local bufnr = vim.api.nvim_create_buf(true, true)
                vim.api.nvim_buf_set_name(bufnr, 'myfile.lua')
                _G.fixture.bufnr = bufnr

                -- Capture keymap.set calls for assertion.
                _G.fixture.keymap_set_args = {}
                vim.keymap.set = function(mode, lhs, rhs, opts)
                    _G.fixture.keymap_set_args[lhs] = { mode = mode, lhs = lhs, rhs = rhs, opts = opts }
                end

                -- Stub fnamemodify to return just the basename (simulates ':t' modifier).
                vim.fn.fnamemodify = function(path, _mod)
                    return path:match('([^/]+)$') or path
                end

                -- Stub programmatically_select_diff_from_menu so keybind tests stay isolated.
                M.programmatically_select_diff_from_menu = function(filepath)
                    _G.fixture.programmatically_selected = filepath
                end

                -- Shared state used by most cases.
                package.loaded['deltaview.state'].diffed_files = {
                    files = { 'a.lua', 'b.lua', 'c.lua' },
                    cur_idx = 2,
                }
            ]])
        end,
    },
})

-- adjacent_files is nil: nothing should happen
T['decorate_deltaview_with_next_keybinds()']['does nothing when adjacent_files is nil'] = function()
    child.lua([[
        package.loaded['deltaview.utils'].get_adjacent_files = function(_) return nil end
        local original_name = vim.api.nvim_buf_get_name(_G.fixture.bufnr)
        M.decorate_deltaview_with_next_keybinds(_G.fixture.bufnr)
        _G.fixture.name_after = vim.api.nvim_buf_get_name(_G.fixture.bufnr)
        _G.fixture.original_name = original_name
    ]])

    local original = child.lua_get('_G.fixture.original_name')
    local after = child.lua_get('_G.fixture.name_after')
    eq(original, after)
    eq(child.lua_get('next((_G.fixture.keymap_set_args))'), vim.NIL)
end

-- adjacent_files non-nil, show_verbose_nav = false: name includes [idx|total] block, no prev prefix
T['decorate_deltaview_with_next_keybinds()']['sets buffer name with navigation info when show_verbose_nav is false'] = function()
    child.lua([[
        package.loaded['deltaview.config'].options.show_verbose_nav = false
        package.loaded['deltaview.utils'].get_adjacent_files = function(_)
            return { prev = 'path/to/a.lua', next = 'path/to/c.lua' }
        end
        M.decorate_deltaview_with_next_keybinds(_G.fixture.bufnr)
        _G.fixture.name = vim.api.nvim_buf_get_name(_G.fixture.bufnr)
    ]])

    local name = child.lua_get('_G.fixture.name')
    -- Should contain the [cur|total] index block
    eq(name:find('%[2|3%]') ~= nil, true)
    -- Should contain the next file's tail
    eq(name:find('c%.lua') ~= nil, true)
    -- Should NOT contain the prev file's tail before the index block (no verbose prefix)
    local idx_pos = name:find('%[2|3%]')
    eq(name:sub(1, idx_pos - 1):find('a%.lua'), nil)
end

-- adjacent_files non-nil, show_verbose_nav = true: name is prefixed with prev filename + prev icon
T['decorate_deltaview_with_next_keybinds()']['prefixes buffer name with prev filename when show_verbose_nav is true'] = function()
    child.lua([[
        package.loaded['deltaview.config'].options.show_verbose_nav = true
        package.loaded['deltaview.utils'].get_adjacent_files = function(_)
            return { prev = 'path/to/a.lua', next = 'path/to/c.lua' }
        end
        M.decorate_deltaview_with_next_keybinds(_G.fixture.bufnr)
        _G.fixture.name = vim.api.nvim_buf_get_name(_G.fixture.bufnr)
    ]])

    local name = child.lua_get('_G.fixture.name')
    -- Both prev and next file tails should appear
    eq(name:find('a%.lua') ~= nil, true)
    eq(name:find('c%.lua') ~= nil, true)
    -- prev tail should appear before the [idx|total] block
    local prev_pos = name:find('a%.lua')
    local idx_pos = name:find('%[2|3%]')
    eq(prev_pos < idx_pos, true)
end

-- next_diff keybind is registered with the correct mode, buffer, and silent options
T['decorate_deltaview_with_next_keybinds()']['registers next_diff keybind on the correct buffer'] = function()
    child.lua([[
        package.loaded['deltaview.utils'].get_adjacent_files = function(_)
            return { prev = 'path/to/a.lua', next = 'path/to/c.lua' }
        end
        M.decorate_deltaview_with_next_keybinds(_G.fixture.bufnr)
    ]])

    -- Read serializable fields one at a time to avoid the child trying to serialize `rhs` (a function).
    eq(child.lua_get("_G.fixture.keymap_set_args[']d'].mode"), 'n')
    eq(child.lua_get("_G.fixture.keymap_set_args[']d'].lhs"), ']d')
    eq(child.lua_get("_G.fixture.keymap_set_args[']d'].opts.buffer"), child.lua_get('_G.fixture.bufnr'))
    eq(child.lua_get("_G.fixture.keymap_set_args[']d'].opts.silent"), true)
end

-- prev_diff keybind is registered with the correct mode, buffer, and silent options
T['decorate_deltaview_with_next_keybinds()']['registers prev_diff keybind on the correct buffer'] = function()
    child.lua([[
        package.loaded['deltaview.utils'].get_adjacent_files = function(_)
            return { prev = 'path/to/a.lua', next = 'path/to/c.lua' }
        end
        M.decorate_deltaview_with_next_keybinds(_G.fixture.bufnr)
    ]])

    -- Read serializable fields one at a time to avoid the child trying to serialize `rhs` (a function).
    eq(child.lua_get("_G.fixture.keymap_set_args['[d'].mode"), 'n')
    eq(child.lua_get("_G.fixture.keymap_set_args['[d'].lhs"), '[d')
    eq(child.lua_get("_G.fixture.keymap_set_args['[d'].opts.buffer"), child.lua_get('_G.fixture.bufnr'))
    eq(child.lua_get("_G.fixture.keymap_set_args['[d'].opts.silent"), true)
end

-- next_diff keybind rhs calls programmatically_select_diff_from_menu with adjacent_files.next
T['decorate_deltaview_with_next_keybinds()']['next_diff keybind navigates to the next adjacent file'] = function()
    child.lua([[
        package.loaded['deltaview.utils'].get_adjacent_files = function(_)
            return { prev = 'path/to/a.lua', next = 'path/to/c.lua' }
        end
        M.decorate_deltaview_with_next_keybinds(_G.fixture.bufnr)
        -- invoke the registered rhs directly
        _G.fixture.keymap_set_args[']d'].rhs()
    ]])

    eq(child.lua_get('_G.fixture.programmatically_selected'), 'path/to/c.lua')
end

-- prev_diff keybind rhs calls programmatically_select_diff_from_menu with adjacent_files.prev
T['decorate_deltaview_with_next_keybinds()']['prev_diff keybind navigates to the previous adjacent file'] = function()
    child.lua([[
        package.loaded['deltaview.utils'].get_adjacent_files = function(_)
            return { prev = 'path/to/a.lua', next = 'path/to/c.lua' }
        end
        M.decorate_deltaview_with_next_keybinds(_G.fixture.bufnr)
        -- invoke the registered rhs directly
        _G.fixture.keymap_set_args['[d'].rhs()
    ]])

    eq(child.lua_get('_G.fixture.programmatically_selected'), 'path/to/a.lua')
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- programmatically_select_diff_from_menu() - example based tests

T['programmatically_select_diff_from_menu()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- Happy-path defaults: in git repo, mods contains 'b.lua' at index 2.
                vim.system = function(_cmd, _opts)
                    return { wait = function() return { code = 0, stdout = '/repo', stderr = '' } end }
                end

                package.loaded['deltaview.utils'].get_sorted_diffed_files = function(_ref)
                    return _G.fixture.sorted_files or {}
                end
                package.loaded['deltaview.utils'].get_filenames_from_sortedfiles = function(_sf)
                    return _G.fixture.mods or {}
                end
                package.loaded['deltaview.utils'].git_rel_to_abs = function(p) return p end

                vim.fn.fnameescape = function(p) return p end
                vim.cmd = function(_) end

                package.loaded['deltaview.view'].deltaview_file = function(_ref)
                    return _G.fixture.deltaview_file_result
                end

                M.decorate_deltaview_with_next_keybinds = function(bufnr)
                    _G.fixture.decorate_called_with = bufnr
                end

                -- Default mods list; individual tests can override via fixture.
                _G.fixture.sorted_files = {}
                _G.fixture.mods = { 'a.lua', 'b.lua', 'c.lua' }
                _G.fixture.deltaview_file_result = 42
            ]])
        end,
    },
})

T['programmatically_select_diff_from_menu()']['notifies and returns when not in a git repository'] = function()
    child.lua([[
        vim.system = function(_cmd, _opts)
            return { wait = function() return { code = 128, stdout = '', stderr = '' } end }
        end
        M.programmatically_select_diff_from_menu('b.lua')
    ]])

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

T['programmatically_select_diff_from_menu()']['raises when filepath is not found in mods'] = function()
    child.lua([[
        local ok, _err = pcall(function()
            M.programmatically_select_diff_from_menu('not_in_list.lua')
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['programmatically_select_diff_from_menu()']['updates state and calls decorate on happy path'] = function()
    child.lua([[
        M.programmatically_select_diff_from_menu('b.lua')
    ]])

    -- state.diffed_files should be updated to the full mods list
    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.files"),
        { 'a.lua', 'b.lua', 'c.lua' })
    -- cur_idx should be the position of 'b.lua' in mods (index 2)
    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 2)
    -- decorate should have been called with the bufnr returned by deltaview_file
    eq(child.lua_get('_G.fixture.decorate_called_with'), 42)
end

T['programmatically_select_diff_from_menu()']['does not update state when deltaview_file returns nil'] = function()
    child.lua([[
        _G.fixture.deltaview_file_result = nil
        -- Preset a known cur_idx so we can confirm it is left unchanged.
        package.loaded['deltaview.state'].diffed_files.cur_idx = 99
        M.programmatically_select_diff_from_menu('b.lua')
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 99)
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

T['programmatically_select_diff_from_menu()']['notifies error when the pcall body throws'] = function()
    child.lua([[
        vim.cmd = function(_) error('disk full') end
        M.programmatically_select_diff_from_menu('b.lua')
    ]])

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- open_deltaview_quickselect_menu() - example based tests

T['open_deltaview_quickselect_menu()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- Capture ui_select arguments for assertion and to expose on_select.
                package.loaded['deltaview.selector'].ui_select = function(items, opts, on_select)
                    _G.fixture.ui_select_items = items
                    _G.fixture.ui_select_opts = opts
                    _G.fixture.captured_on_select = on_select
                end

                vim.fn.fnameescape = function(p) return p end
                vim.cmd = function(_) end
                package.loaded['deltaview.utils'].git_rel_to_abs = function(p) return p end

                package.loaded['deltaview.view'].deltaview_file = function(_ref)
                    return _G.fixture.deltaview_file_result
                end

                M.decorate_deltaview_with_next_keybinds = function(bufnr)
                    _G.fixture.decorate_called_with = bufnr
                end

                _G.fixture.deltaview_file_result = 42
            ]])
        end,
    },
})

T['open_deltaview_quickselect_menu()']['raises when ref is nil'] = function()
    child.lua([[
        local ok, _err = pcall(function()
            M.open_deltaview_quickselect_menu(nil, {}, {})
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_quickselect_menu()']['raises when mods is nil'] = function()
    child.lua([[
        local ok, _err = pcall(function()
            M.open_deltaview_quickselect_menu('HEAD', nil, {})
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_quickselect_menu()']['raises when changes_data is nil'] = function()
    child.lua([[
        local ok, _err = pcall(function()
            M.open_deltaview_quickselect_menu('HEAD', {}, nil)
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_quickselect_menu()']['calls ui_select with mods as items'] = function()
    child.lua([[
        M.open_deltaview_quickselect_menu('HEAD', { 'a.lua', 'b.lua' }, {})
    ]])

    eq(child.lua_get('_G.fixture.ui_select_items'), { 'a.lua', 'b.lua' })
end

T['open_deltaview_quickselect_menu()']['calls ui_select with prompt containing the ref'] = function()
    child.lua([[
        M.open_deltaview_quickselect_menu('mybranch', { 'a.lua' }, {})
    ]])

    local prompt = child.lua_get('_G.fixture.ui_select_opts.prompt')
    eq(prompt:find('mybranch') ~= nil, true)
end

T['open_deltaview_quickselect_menu()']['on_select: does nothing when filepath is nil'] = function()
    child.lua([[
        package.loaded['deltaview.state'].diffed_files.cur_idx = 99
        M.open_deltaview_quickselect_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        _G.fixture.captured_on_select(nil, 1)
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 99)
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

T['open_deltaview_quickselect_menu()']['on_select: updates state and calls decorate on happy path'] = function()
    child.lua([[
        M.open_deltaview_quickselect_menu('HEAD', { 'a.lua', 'b.lua', 'c.lua' }, {})
        _G.fixture.captured_on_select('b.lua', 2)
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.files"), { 'a.lua', 'b.lua', 'c.lua' })
    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 2)
    eq(child.lua_get('_G.fixture.decorate_called_with'), 42)
end

T['open_deltaview_quickselect_menu()']['on_select: does not update state when deltaview_file returns nil'] = function()
    child.lua([[
        _G.fixture.deltaview_file_result = nil
        package.loaded['deltaview.state'].diffed_files.cur_idx = 99
        M.open_deltaview_quickselect_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        _G.fixture.captured_on_select('b.lua', 2)
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 99)
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

T['open_deltaview_quickselect_menu()']['on_select: notifies error when pcall body throws'] = function()
    child.lua([[
        vim.cmd = function(_) error('disk full') end
        M.open_deltaview_quickselect_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        _G.fixture.captured_on_select('b.lua', 2)
    ]])

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- open_deltaview_fzf_lua_menu() - example based tests

T['open_deltaview_fzf_lua_menu()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- Stub builtin previewer base with a minimal class that supports :extend().
                local base_stub = {}
                base_stub.extend = function(self)
                    local sub = { super = { new = function() end } }
                    sub.__index = sub
                    return sub
                end
                package.loaded['fzf-lua.previewer.builtin'] = { base = base_stub }

                -- Stub fzf-lua to capture fzf_exec arguments.
                package.loaded['fzf-lua'] = {
                    fzf_exec = function(items, opts)
                        _G.fixture.fzf_exec_items = items
                        _G.fixture.fzf_exec_prompt = opts.prompt
                        _G.fixture.fzf_exec_title = opts.winopts and opts.winopts.title
                        _G.fixture.captured_default_action = opts.actions and opts.actions['default']
                    end
                }

                vim.fn.fnameescape = function(p) return p end
                vim.cmd = function(_) end
                package.loaded['deltaview.utils'].git_rel_to_abs = function(p) return p end
                package.loaded['deltaview.view'].deltaview_file = function(_ref)
                    return _G.fixture.deltaview_file_result
                end

                M.decorate_deltaview_with_next_keybinds = function(bufnr)
                    _G.fixture.decorate_called_with = bufnr
                end

                _G.fixture.deltaview_file_result = 42
            ]])
        end,
    },
})

T['open_deltaview_fzf_lua_menu()']['calls fzf_exec with mods as items'] = function()
    child.lua([[
        M.open_deltaview_fzf_lua_menu('HEAD', { 'a.lua', 'b.lua' }, {})
    ]])

    eq(child.lua_get('_G.fixture.fzf_exec_items'), { 'a.lua', 'b.lua' })
end

T['open_deltaview_fzf_lua_menu()']['calls fzf_exec with winopts title containing diff_target_ref'] = function()
    child.lua([[
        package.loaded['deltaview.state'].diff_target_ref = 'mybranch'
        M.open_deltaview_fzf_lua_menu('HEAD', { 'a.lua' }, {})
    ]])

    local title = child.lua_get('_G.fixture.fzf_exec_title')
    eq(title:find('mybranch') ~= nil, true)
end

T['open_deltaview_fzf_lua_menu()']['default action: does nothing when selected is nil'] = function()
    child.lua([[
        package.loaded['deltaview.state'].diffed_files.cur_idx = 99
        M.open_deltaview_fzf_lua_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        _G.fixture.captured_default_action(nil)
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 99)
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

T['open_deltaview_fzf_lua_menu()']['default action: does nothing when selected is empty'] = function()
    child.lua([[
        package.loaded['deltaview.state'].diffed_files.cur_idx = 99
        M.open_deltaview_fzf_lua_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        _G.fixture.captured_default_action({})
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 99)
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

T['open_deltaview_fzf_lua_menu()']['default action: updates state and calls decorate on happy path'] = function()
    child.lua([[
        M.open_deltaview_fzf_lua_menu('HEAD', { 'a.lua', 'b.lua', 'c.lua' }, {})
        _G.fixture.captured_default_action({ 'b.lua' })
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.files"), { 'a.lua', 'b.lua', 'c.lua' })
    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 2)
    eq(child.lua_get('_G.fixture.decorate_called_with'), 42)
end

T['open_deltaview_fzf_lua_menu()']['default action: does not update state when deltaview_file returns nil'] = function()
    child.lua([[
        _G.fixture.deltaview_file_result = nil
        package.loaded['deltaview.state'].diffed_files.cur_idx = 99
        M.open_deltaview_fzf_lua_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        _G.fixture.captured_default_action({ 'b.lua' })
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 99)
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

T['open_deltaview_fzf_lua_menu()']['default action: raises when selection not found in mods'] = function()
    child.lua([[
        M.open_deltaview_fzf_lua_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        local ok, _err = pcall(function()
            _G.fixture.captured_default_action({ 'not_in_list.lua' })
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- open_deltaview_fzf_junegunn_menu() - example based tests

T['open_deltaview_fzf_junegunn_menu()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- fzf#wrap is identity; fzf#run captures the sink* callback.
                vim.fn['fzf#wrap'] = function(config) return config end
                vim.fn['fzf#run'] = function(config)
                    _G.fixture.fzf_run_called = true
                    _G.fixture.captured_sink = config['sink*']
                end

                vim.fn.fnameescape = function(p) return p end
                vim.cmd = function(_) end
                package.loaded['deltaview.utils'].git_rel_to_abs = function(p) return p end
                package.loaded['deltaview.view'].deltaview_file = function(_ref)
                    return _G.fixture.deltaview_file_result
                end

                M.decorate_deltaview_with_next_keybinds = function(bufnr)
                    _G.fixture.decorate_called_with = bufnr
                end
                M.open_deltaview_quickselect_menu = function(_ref, _mods, _changes_data)
                    _G.fixture.quickselect_called = true
                end

                _G.fixture.deltaview_file_result = 42
            ]])
        end,
    },
})

T['open_deltaview_fzf_junegunn_menu()']['raises when ref is nil'] = function()
    child.lua([[
        local ok, _err = pcall(function()
            M.open_deltaview_fzf_junegunn_menu(nil, {}, {})
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_fzf_junegunn_menu()']['raises when mods is nil'] = function()
    child.lua([[
        local ok, _err = pcall(function()
            M.open_deltaview_fzf_junegunn_menu('HEAD', nil, {})
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_fzf_junegunn_menu()']['raises when changes_data is nil'] = function()
    child.lua([[
        local ok, _err = pcall(function()
            M.open_deltaview_fzf_junegunn_menu('HEAD', {}, nil)
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_fzf_junegunn_menu()']['calls fzf#run and registers sink callback'] = function()
    child.lua([[
        M.open_deltaview_fzf_junegunn_menu('HEAD', { 'a.lua' }, {})
        _G.fixture.captured_sink_type = type(_G.fixture.captured_sink)
    ]])

    eq(child.lua_get('_G.fixture.fzf_run_called'), true)
    eq(child.lua_get('_G.fixture.captured_sink_type'), 'function')
end

T['open_deltaview_fzf_junegunn_menu()']['warns and falls back to quickselect when fzf#run fails'] = function()
    child.lua([[
        vim.fn['fzf#run'] = function(_) error('fzf not available') end
        M.open_deltaview_fzf_junegunn_menu('HEAD', { 'a.lua' }, {})
    ]])

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
    eq(child.lua_get('_G.fixture.quickselect_called'), true)
end

-- on_select_with_key callback tests — invoke _G.fixture.captured_sink directly

T['open_deltaview_fzf_junegunn_menu()']['on_select: raises when result is nil'] = function()
    child.lua([[
        M.open_deltaview_fzf_junegunn_menu('HEAD', { 'a.lua' }, {})
        local ok, _err = pcall(function() _G.fixture.captured_sink(nil) end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_fzf_junegunn_menu()']['on_select: raises when result[1] is nil'] = function()
    child.lua([[
        M.open_deltaview_fzf_junegunn_menu('HEAD', { 'a.lua' }, {})
        local ok, _err = pcall(function() _G.fixture.captured_sink({ nil, 'a.lua' }) end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_fzf_junegunn_menu()']['on_select: raises when result[2] is nil'] = function()
    child.lua([[
        M.open_deltaview_fzf_junegunn_menu('HEAD', { 'a.lua' }, {})
        local ok, _err = pcall(function() _G.fixture.captured_sink({ 'ctrl-t', nil }) end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

-- fzf sends '' as the key when the user presses Enter without a bound --expect key
T['open_deltaview_fzf_junegunn_menu()']['on_select: when key is fzf_toggle calls quickselect and returns'] = function()
    child.lua([[
        M.open_deltaview_fzf_junegunn_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        _G.fixture.captured_sink({ 'ctrl-t', 'a.lua' })
    ]])

    eq(child.lua_get('_G.fixture.quickselect_called'), true)
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

T['open_deltaview_fzf_junegunn_menu()']['on_select: updates state and calls decorate on happy path'] = function()
    child.lua([[
        M.open_deltaview_fzf_junegunn_menu('HEAD', { 'a.lua', 'b.lua', 'c.lua' }, {})
        _G.fixture.captured_sink({ '', 'b.lua' })
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.files"), { 'a.lua', 'b.lua', 'c.lua' })
    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 2)
    eq(child.lua_get('_G.fixture.decorate_called_with'), 42)
end

T['open_deltaview_fzf_junegunn_menu()']['on_select: raises when filepath not found in mods'] = function()
    child.lua([[
        M.open_deltaview_fzf_junegunn_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        local ok, _err = pcall(function()
            _G.fixture.captured_sink({ '', 'not_in_list.lua' })
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_fzf_junegunn_menu()']['on_select: does not update state when deltaview_file returns nil'] = function()
    child.lua([[
        _G.fixture.deltaview_file_result = nil
        package.loaded['deltaview.state'].diffed_files.cur_idx = 99
        M.open_deltaview_fzf_junegunn_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        _G.fixture.captured_sink({ '', 'b.lua' })
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 99)
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

T['open_deltaview_fzf_junegunn_menu()']['on_select: notifies error when pcall body throws'] = function()
    child.lua([[
        vim.cmd = function(_) error('disk full') end
        M.open_deltaview_fzf_junegunn_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        _G.fixture.captured_sink({ '', 'b.lua' })
    ]])

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- open_deltaview_telescope_menu() - example based tests

T['open_deltaview_telescope_menu()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                package.loaded['telescope'] = {}

                package.loaded['telescope.finders'] = {
                    new_table = function(opts)
                        return { results = opts.results }
                    end,
                }

                package.loaded['telescope.config'] = {
                    values = { generic_sorter = function(_) return {} end },
                }

                package.loaded['telescope.previewers'] = {
                    new = function(_opts) return {} end,
                }

                package.loaded['telescope.actions'] = {
                    select_default = {
                        replace = function(self, handler)
                            _G.fixture.captured_select_handler = handler
                        end,
                    },
                    close = function(_bufnr) end,
                }

                package.loaded['telescope.actions.state'] = {
                    get_selected_entry = function()
                        return _G.fixture.selected_entry
                    end,
                }

                -- pickers.new invokes attach_mappings immediately so the handler is captured
                -- before :find() runs.
                package.loaded['telescope.pickers'] = {
                    new = function(_opts, picker_opts)
                        _G.fixture.results_title = picker_opts.results_title
                        _G.fixture.finder_results = picker_opts.finder and picker_opts.finder.results
                        if picker_opts.attach_mappings then
                            picker_opts.attach_mappings(0, function() end)
                        end
                        return { find = function(self) end }
                    end,
                }

                vim.fn.fnameescape = function(p) return p end
                vim.cmd = function(_) end
                package.loaded['deltaview.utils'].git_rel_to_abs = function(p) return p end
                package.loaded['deltaview.view'].deltaview_file = function(_ref)
                    return _G.fixture.deltaview_file_result
                end

                M.decorate_deltaview_with_next_keybinds = function(bufnr)
                    _G.fixture.decorate_called_with = bufnr
                end

                _G.fixture.deltaview_file_result = 42
            ]])
        end,
    },
})

T['open_deltaview_telescope_menu()']['raises when ref is nil'] = function()
    child.lua([[
        local ok, _err = pcall(function()
            M.open_deltaview_telescope_menu(nil, {}, {})
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_telescope_menu()']['raises when mods is nil'] = function()
    child.lua([[
        local ok, _err = pcall(function()
            M.open_deltaview_telescope_menu('HEAD', nil, {})
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_telescope_menu()']['raises when changes_data is nil'] = function()
    child.lua([[
        local ok, _err = pcall(function()
            M.open_deltaview_telescope_menu('HEAD', {}, nil)
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_telescope_menu()']['passes mods as finder results'] = function()
    child.lua([[
        M.open_deltaview_telescope_menu('HEAD', { 'a.lua', 'b.lua' }, {})
    ]])

    eq(child.lua_get('_G.fixture.finder_results'), { 'a.lua', 'b.lua' })
end

T['open_deltaview_telescope_menu()']['results_title contains diff_target_ref'] = function()
    child.lua([[
        package.loaded['deltaview.state'].diff_target_ref = 'mybranch'
        M.open_deltaview_telescope_menu('HEAD', { 'a.lua' }, {})
    ]])

    local title = child.lua_get('_G.fixture.results_title')
    eq(title:find('mybranch') ~= nil, true)
end

-- select_default handler tests — invoke _G.fixture.captured_select_handler directly

T['open_deltaview_telescope_menu()']['select_default: does nothing when get_selected_entry returns nil'] = function()
    child.lua([[
        package.loaded['deltaview.state'].diffed_files.cur_idx = 99
        _G.fixture.selected_entry = nil
        M.open_deltaview_telescope_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        _G.fixture.captured_select_handler()
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 99)
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

T['open_deltaview_telescope_menu()']['select_default: updates state and calls decorate on happy path'] = function()
    child.lua([[
        _G.fixture.selected_entry = { value = 'b.lua' }
        M.open_deltaview_telescope_menu('HEAD', { 'a.lua', 'b.lua', 'c.lua' }, {})
        _G.fixture.captured_select_handler()
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.files"), { 'a.lua', 'b.lua', 'c.lua' })
    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 2)
    eq(child.lua_get('_G.fixture.decorate_called_with'), 42)
end

T['open_deltaview_telescope_menu()']['select_default: raises when selection not found in mods'] = function()
    child.lua([[
        _G.fixture.selected_entry = { value = 'not_in_list.lua' }
        M.open_deltaview_telescope_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        local ok, _err = pcall(function()
            _G.fixture.captured_select_handler()
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['open_deltaview_telescope_menu()']['select_default: does not update state when deltaview_file returns nil'] = function()
    child.lua([[
        _G.fixture.deltaview_file_result = nil
        _G.fixture.selected_entry = { value = 'b.lua' }
        package.loaded['deltaview.state'].diffed_files.cur_idx = 99
        M.open_deltaview_telescope_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        _G.fixture.captured_select_handler()
    ]])

    eq(child.lua_get("package.loaded['deltaview.state'].diffed_files.cur_idx"), 99)
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

T['open_deltaview_telescope_menu()']['select_default: notifies error when pcall body throws'] = function()
    child.lua([[
        vim.cmd = function(_) error('disk full') end
        _G.fixture.selected_entry = { value = 'b.lua' }
        M.open_deltaview_telescope_menu('HEAD', { 'a.lua', 'b.lua' }, {})
        _G.fixture.captured_select_handler()
    ]])

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
    eq(child.lua_get('_G.fixture.decorate_called_with'), vim.NIL)
end

return T
