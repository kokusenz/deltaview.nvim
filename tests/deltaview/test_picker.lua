local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- utility

-- usage: add the following to a pre_case hook
-- child.lua(test_logging)
local test_logging = [[
    _G.test_logs = {}
    _G.captured_prints = {}
    local original_print = print
    print = function(...)
      local args = {...}
      local msg = table.concat(vim.tbl_map(tostring, args), ' ')
      table.insert(_G.captured_prints, msg)
      original_print(...)
    end
]]

-- usage: add the following to the new_set
-- post_case = print_test_logging
local print_test_logging = function()
    local captured_prints = child.lua_get('_G.captured_prints')
    if captured_prints and #captured_prints > 0 then
        print('\n=== Child Neovim Print Statements ===')
        for i, msg in ipairs(captured_prints) do
            print(string.format('[%d] %s', i, msg))
        end
        print('=== End Print Statements ===\n')
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                package.loaded['deltaview.utils'] = {
                    git_rel_to_abs = function(p) return p end,
                }
                package.loaded['deltaview.state'] = {
                    diff_target_ref = 'HEAD',
                    default_context = 5,
                }
                package.loaded['deltaview.view'] = {
                    open_git_diff_buffer_for_path = function(...) return nil end,
                }

                vim.fn.fnamemodify = function(p, _mod) return p end

                vim.notify = function(msg, _level)
                    _G.fixture.notified = msg
                end

                M = require('deltaview.picker')
            ]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_qf_map() filtering - property based tests (via open_vim_ui_select)
--
-- get_qf_map is private; its filtering behaviour is verified by stubbing vim.ui.select and
-- inspecting the mods list that open_vim_ui_select passes to it.

local GetQfMap = {}

-- Seven input shapes covering: empty, single dv, single non-dv, two dv, mixed (dv/non-dv/dv),
-- all non-dv, and an entry with no user_data field.  Each carries its expected mods list.
GetQfMap.get_inputs = function()
    return {
        -- 1. empty list → nothing to filter
        { list = {}, expected_mods = {} },
        -- 2. single deltaview entry
        {
            list = {
                { filename = '/abs/a.lua', user_data = { deltaview = true, bufname = 'a.lua', status = 'M', changes = '1', ref = 'HEAD' } },
            },
            expected_mods = { 'a.lua' },
        },
        -- 3. single non-deltaview entry
        {
            list = {
                { filename = '/abs/x.lua', user_data = { deltaview = false, bufname = 'x.lua', status = 'M', changes = '1', ref = 'HEAD' } },
            },
            expected_mods = {},
        },
        -- 4. two deltaview entries → both included in order
        {
            list = {
                { filename = '/abs/a.lua', user_data = { deltaview = true, bufname = 'a.lua', status = 'M', changes = '10', ref = 'HEAD' } },
                { filename = '/abs/b.lua', user_data = { deltaview = true, bufname = 'b.lua', status = 'A', changes = '5',  ref = 'main' } },
            },
            expected_mods = { 'a.lua', 'b.lua' },
        },
        -- 5. mixed: deltaview, non-deltaview, deltaview → non-dv entry is excluded
        {
            list = {
                { filename = '/abs/a.lua', user_data = { deltaview = true,  bufname = 'a.lua', status = 'M', changes = '10', ref = 'HEAD' } },
                { filename = '/abs/x.lua', user_data = { deltaview = false, bufname = 'x.lua', status = 'M', changes = '1',  ref = 'HEAD' } },
                { filename = '/abs/b.lua', user_data = { deltaview = true,  bufname = 'b.lua', status = 'A', changes = '5',  ref = 'main' } },
            },
            expected_mods = { 'a.lua', 'b.lua' },
        },
        -- 6. all non-deltaview → mods is empty
        {
            list = {
                { filename = '/abs/x.lua', user_data = { deltaview = false, bufname = 'x.lua' } },
                { filename = '/abs/y.lua', user_data = { deltaview = false, bufname = 'y.lua' } },
            },
            expected_mods = {},
        },
        -- 7. entry with no user_data field → treated as non-deltaview
        {
            list = { { filename = '/abs/z.lua' } },
            expected_mods = {},
        },
    }
end

GetQfMap.property_cases = {
    { name = 'seven input shapes' },
}

GetQfMap.properties = {}

GetQfMap.properties.only_deltaview_entries_are_included = [[(function()
    local inputs = _G.fixture.inputs
    for _, input in ipairs(inputs) do
        local captured_mods = nil
        vim.ui.select = function(items, _opts, _on_choice)
            captured_mods = items
        end
        M.open_vim_ui_select(input.list, function() end)
        local expected = input.expected_mods
        if #captured_mods ~= #expected then return false end
        for i, v in ipairs(expected) do
            if captured_mods[i] ~= v then return false end
        end
    end
    return true
end)()]]

T['get_qf_map() properties'] = new_set()
for func_name, func in pairs(GetQfMap.properties) do
    for _, case in ipairs(GetQfMap.property_cases) do
        T['get_qf_map() properties'][func_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.inputs = ...]], { GetQfMap.get_inputs() })
            local result = child.lua_get(func)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- open_vim_ui_select() - example based tests

T['open_vim_ui_select()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                _G.dv_list = {
                    { filename = '/abs/a.lua', user_data = { deltaview = true, bufname = 'a.lua', status = 'M', changes = '10', ref = 'HEAD' } },
                    { filename = '/abs/b.lua', user_data = { deltaview = true, bufname = 'b.lua', status = 'A', changes = '5',  ref = 'main' } },
                }
                vim.cmd = function(cmd) _G.fixture.vim_cmd = cmd end
            ]])
        end,
    }
})

T['open_vim_ui_select()']['passes deltaview bufnames as items to vim.ui.select'] = function()
    child.lua([[
        vim.ui.select = function(items, _opts, _on_choice)
            _G.fixture.select_items = items
        end
        M.open_vim_ui_select(_G.dv_list, function() end)
    ]])
    local items = child.lua_get([[_G.fixture.select_items]])
    eq(items, { 'a.lua', 'b.lua' })
end

T['open_vim_ui_select()']['uses DeltaView Menu as prompt'] = function()
    child.lua([[
        vim.ui.select = function(_items, opts, _on_choice)
            _G.fixture.select_opts = opts
        end
        M.open_vim_ui_select(_G.dv_list, function() end)
    ]])
    local prompt = child.lua_get([[_G.fixture.select_opts.prompt]])
    eq(prompt, 'DeltaView Menu')
end

T['open_vim_ui_select()']['format_item returns status, filename and changes'] = function()
    child.lua([[
        vim.ui.select = function(_items, opts, _on_choice)
            _G.fixture.format_item = opts.format_item
        end
        M.open_vim_ui_select(_G.dv_list, function() end)
    ]])
    local formatted = child.lua_get([[_G.fixture.format_item('a.lua')]])
    eq(formatted, ' M a.lua > 10 ')
end

T['open_vim_ui_select()']['callback with nil choice does not open file or call open_dv_func'] = function()
    child.lua([[
        vim.ui.select = function(_items, _opts, on_choice)
            _G.fixture.on_choice = on_choice
        end
        _G.fixture.open_dv_called = false
        M.open_vim_ui_select(_G.dv_list, function() _G.fixture.open_dv_called = true end)
        _G.fixture.on_choice(nil)
    ]])
    local cmd = child.lua_get([[_G.fixture.vim_cmd]])
    local called = child.lua_get([[_G.fixture.open_dv_called]])
    eq(cmd, vim.NIL)
    eq(called, false)
end

T['open_vim_ui_select()']['callback with valid choice opens file via vim.cmd e'] = function()
    child.lua([[
        vim.ui.select = function(_items, _opts, on_choice)
            _G.fixture.on_choice = on_choice
        end
        M.open_vim_ui_select(_G.dv_list, function() end)
        _G.fixture.on_choice('a.lua')
    ]])
    local cmd = child.lua_get([[_G.fixture.vim_cmd]])
    eq(cmd, 'e /abs/a.lua')
end

T['open_vim_ui_select()']['callback with valid choice calls open_dv_func with entry user_data'] = function()
    child.lua([[
        vim.ui.select = function(_items, _opts, on_choice)
            _G.fixture.on_choice = on_choice
        end
        _G.fixture.open_dv_userdata = nil
        M.open_vim_ui_select(_G.dv_list, function(ud) _G.fixture.open_dv_userdata = ud end)
        _G.fixture.on_choice('a.lua')
    ]])
    local ud = child.lua_get([[_G.fixture.open_dv_userdata]])
    eq(ud.bufname, 'a.lua')
    eq(ud.status, 'M')
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- open_deltaview_fzf_lua_menu() - example based tests

T['open_deltaview_fzf_lua_menu()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                _G.dv_list = {
                    { filename = '/abs/a.lua', user_data = { deltaview = true, bufname = 'a.lua', status = 'M', changes = '10', ref = 'HEAD' } },
                    { filename = '/abs/b.lua', user_data = { deltaview = true, bufname = 'b.lua', status = 'A', changes = '5',  ref = 'main' } },
                }
                vim.cmd = function(cmd) _G.fixture.vim_cmd = cmd end

                -- builtin.base:extend() returns a table the module adds methods to directly;
                -- super.new is called inside DeltaviewPreviewer:new so it must be a no-op stub.
                package.loaded['fzf-lua.previewer.builtin'] = {
                    base = {
                        extend = function(_self)
                            return { super = { new = function() end } }
                        end
                    }
                }
                package.loaded['fzf-lua'] = {
                    fzf_exec = function(mods, opts)
                        _G.fixture.fzf_mods = mods
                        _G.fixture.fzf_opts = opts
                    end
                }
            ]])
        end,
    }
})

T['open_deltaview_fzf_lua_menu()']['passes deltaview bufnames to fzf_exec'] = function()
    child.lua([[M.open_deltaview_fzf_lua_menu(_G.dv_list, function() end)]])
    local mods = child.lua_get([[_G.fixture.fzf_mods]])
    eq(mods, { 'a.lua', 'b.lua' })
end

T['open_deltaview_fzf_lua_menu()']['winopts title includes diff_target_ref'] = function()
    child.lua([[M.open_deltaview_fzf_lua_menu(_G.dv_list, function() end)]])
    local title = child.lua_get([[_G.fixture.fzf_opts.winopts.title]])
    eq(title, 'comparing to HEAD')
end

T['open_deltaview_fzf_lua_menu()']['default action with nil selected is a no-op'] = function()
    child.lua([[
        _G.fixture.open_dv_called = false
        M.open_deltaview_fzf_lua_menu(_G.dv_list, function() _G.fixture.open_dv_called = true end)
        _G.fixture.fzf_opts.actions['default'](nil)
    ]])
    local cmd = child.lua_get([[_G.fixture.vim_cmd]])
    local called = child.lua_get([[_G.fixture.open_dv_called]])
    eq(cmd, vim.NIL)
    eq(called, false)
end

T['open_deltaview_fzf_lua_menu()']['default action with empty selected table is a no-op'] = function()
    child.lua([[
        _G.fixture.open_dv_called = false
        M.open_deltaview_fzf_lua_menu(_G.dv_list, function() _G.fixture.open_dv_called = true end)
        _G.fixture.fzf_opts.actions['default']({})
    ]])
    local cmd = child.lua_get([[_G.fixture.vim_cmd]])
    local called = child.lua_get([[_G.fixture.open_dv_called]])
    eq(cmd, vim.NIL)
    eq(called, false)
end

T['open_deltaview_fzf_lua_menu()']['default action opens file via vim.cmd e'] = function()
    child.lua([[
        M.open_deltaview_fzf_lua_menu(_G.dv_list, function() end)
        _G.fixture.fzf_opts.actions['default']({ 'a.lua' })
    ]])
    local cmd = child.lua_get([[_G.fixture.vim_cmd]])
    eq(cmd, 'e /abs/a.lua')
end

T['open_deltaview_fzf_lua_menu()']['default action calls open_dv_func with entry user_data'] = function()
    child.lua([[
        _G.fixture.open_dv_userdata = nil
        M.open_deltaview_fzf_lua_menu(_G.dv_list, function(ud) _G.fixture.open_dv_userdata = ud end)
        _G.fixture.fzf_opts.actions['default']({ 'b.lua' })
    ]])
    local ud = child.lua_get([[_G.fixture.open_dv_userdata]])
    eq(ud.bufname, 'b.lua')
    eq(ud.status, 'A')
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- open_deltaview_telescope_menu() - example based tests

T['open_deltaview_telescope_menu()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                _G.dv_list = {
                    { filename = '/abs/a.lua', user_data = { deltaview = true, bufname = 'a.lua', status = 'M', changes = '10', ref = 'HEAD' } },
                    { filename = '/abs/b.lua', user_data = { deltaview = true, bufname = 'b.lua', status = 'A', changes = '5',  ref = 'main' } },
                }
                vim.cmd = function(cmd) _G.fixture.vim_cmd = cmd end

                package.loaded['telescope.pickers'] = {
                    new = function(_opts, picker_opts)
                        _G.fixture.picker_opts = picker_opts
                        return { find = function() end }
                    end
                }
                package.loaded['telescope.finders'] = {
                    new_table = function(opts)
                        _G.fixture.finder_results = opts.results
                        return {}
                    end
                }
                package.loaded['telescope.config'] = {
                    values = { generic_sorter = function() return {} end }
                }
                -- select_default:replace(fn) stores the action; close() is a no-op stub.
                package.loaded['telescope.actions'] = {
                    select_default = {
                        replace = function(_self, fn)
                            _G.fixture.select_default_fn = fn
                        end
                    },
                    close = function() end,
                }
                -- get_selected_entry() returns whatever the test sets in _G.fixture.selected_entry.
                package.loaded['telescope.actions.state'] = {
                    get_selected_entry = function()
                        return _G.fixture.selected_entry
                    end
                }
                package.loaded['telescope.previewers'] = {
                    new = function(_opts) return {} end
                }
            ]])
        end,
    }
})

T['open_deltaview_telescope_menu()']['finder receives deltaview bufnames as results'] = function()
    child.lua([[M.open_deltaview_telescope_menu(_G.dv_list, function() end)]])
    local results = child.lua_get([[_G.fixture.finder_results]])
    eq(results, { 'a.lua', 'b.lua' })
end

T['open_deltaview_telescope_menu()']['prompt_title is DeltaView Menu'] = function()
    child.lua([[M.open_deltaview_telescope_menu(_G.dv_list, function() end)]])
    local title = child.lua_get([[_G.fixture.picker_opts.prompt_title]])
    eq(title, 'DeltaView Menu')
end

T['open_deltaview_telescope_menu()']['results_title includes diff_target_ref'] = function()
    child.lua([[M.open_deltaview_telescope_menu(_G.dv_list, function() end)]])
    local title = child.lua_get([[_G.fixture.picker_opts.results_title]])
    eq(title, 'comparing to HEAD')
end

T['open_deltaview_telescope_menu()']['attach_mappings returns true'] = function()
    child.lua([[M.open_deltaview_telescope_menu(_G.dv_list, function() end)]])
    local result = child.lua_get([[_G.fixture.picker_opts.attach_mappings(nil, nil)]])
    eq(result, true)
end

T['open_deltaview_telescope_menu()']['default action with nil selection is a no-op'] = function()
    child.lua([[
        _G.fixture.open_dv_called = false
        _G.fixture.selected_entry = nil
        M.open_deltaview_telescope_menu(_G.dv_list, function() _G.fixture.open_dv_called = true end)
        _G.fixture.picker_opts.attach_mappings(nil, nil)
        _G.fixture.select_default_fn()
    ]])
    local cmd = child.lua_get([[_G.fixture.vim_cmd]])
    local called = child.lua_get([[_G.fixture.open_dv_called]])
    eq(cmd, vim.NIL)
    eq(called, false)
end

T['open_deltaview_telescope_menu()']['default action opens file via vim.cmd e'] = function()
    child.lua([[
        _G.fixture.selected_entry = { value = 'a.lua' }
        M.open_deltaview_telescope_menu(_G.dv_list, function() end)
        _G.fixture.picker_opts.attach_mappings(nil, nil)
        _G.fixture.select_default_fn()
    ]])
    local cmd = child.lua_get([[_G.fixture.vim_cmd]])
    eq(cmd, 'e /abs/a.lua')
end

T['open_deltaview_telescope_menu()']['default action calls open_dv_func with entry user_data'] = function()
    child.lua([[
        _G.fixture.selected_entry = { value = 'b.lua' }
        _G.fixture.open_dv_userdata = nil
        M.open_deltaview_telescope_menu(_G.dv_list, function(ud) _G.fixture.open_dv_userdata = ud end)
        _G.fixture.picker_opts.attach_mappings(nil, nil)
        _G.fixture.select_default_fn()
    ]])
    local ud = child.lua_get([[_G.fixture.open_dv_userdata]])
    eq(ud.bufname, 'b.lua')
    eq(ud.status, 'A')
end

return T
