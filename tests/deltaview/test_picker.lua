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
