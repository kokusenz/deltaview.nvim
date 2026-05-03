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

-- Installs a require override in the child that makes specific modules appear unavailable.
-- `blocked` is a list of module names that should fail to load.
-- Modules NOT in the list are passed through to the original require.
local block_modules_lua = [[
    local blocked_set = {}
    for _, name in ipairs({...}) do blocked_set[name] = true end
    local _orig_require = require
    require = function(name)
        if blocked_set[name] then
            error("module '" .. name .. "' not found (blocked by test)", 2)
        end
        return _orig_require(name)
    end
]]

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                package.loaded['deltaview.config'] = {
                    options = { fzf_picker = nil },
                    viewconfig = function() return { vs = '|' } end,
                }
                package.loaded['deltaview.picker'] = {
                    open_deltaview_fzf_lua_menu = function()
                        _G.fixture.called = 'fzf_lua'
                    end,
                    open_deltaview_telescope_menu = function()
                        _G.fixture.called = 'telescope'
                    end,
                    open_vim_ui_select = function()
                        _G.fixture.called = 'ui_select'
                    end,
                }
                package.loaded['deltaview.utils'] = {
                    get_sorted_diffed_files = function(_) return {} end,
                    get_filenames_from_sortedfiles = function(_) return {} end,
                    git_rel_to_abs = function(path) return '/repo/' .. path end,
                    undo_deltamenu_qf_list = function() end,
                }
                package.loaded['deltaview.view'] = {
                    deltaview_file = function() return 1 end,
                    delta_path = function() return 1 end,
                }
                package.loaded['deltaview.state'] = { default_context = 3 }
                package.loaded['deltaview.help'] = {
                    register_keybind = function() end,
                }

                vim.notify = function(msg, _level)
                    _G.fixture.notified = msg
                end

                M = require('deltaview.menu')
            ]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- choose_deltaview_menu() - example based tests

T['choose_deltaview_menu()'] = new_set()

-- fzf_picker = 'fzf-lua', fzf-lua is available
T['choose_deltaview_menu()']['calls fzf_lua picker when fzf_picker=fzf-lua and fzf-lua is available'] = function()
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = 'fzf-lua'
        package.loaded['fzf-lua'] = {}  -- simulate fzf-lua installed
        M.choose_deltaview_menu()
    ]])

    eq(child.lua_get('_G.fixture.called'), 'fzf_lua')
    eq(child.lua_get('_G.fixture.notified'), vim.NIL)
end

-- fzf_picker = 'fzf-lua', fzf-lua NOT available → warns and falls through to default.
-- In the default path, with neither fzf-lua nor telescope, falls back to vim.cmd('copen').
T['choose_deltaview_menu()']['warns and falls back to default when fzf_picker=fzf-lua but fzf-lua is missing'] = function()
    child.lua(block_modules_lua, { 'fzf-lua', 'telescope' })
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = 'fzf-lua'
        _G.fixture.copen_called = false
        vim.cmd = function(cmd) if cmd == 'copen' then _G.fixture.copen_called = true end end
        M.choose_deltaview_menu()
    ]])

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
    eq(child.lua_get('_G.fixture.copen_called'), true)
end

-- fzf_picker = 'fzf-lua', fzf-lua NOT available, but telescope IS available in default fallback
T['choose_deltaview_menu()']['falls back to telescope in default path when fzf-lua missing but telescope available'] = function()
    child.lua(block_modules_lua, { 'fzf-lua' })
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = 'fzf-lua'
        package.loaded['telescope'] = {}  -- telescope installed
        M.choose_deltaview_menu()
    ]])

    eq(child.lua_get('_G.fixture.called'), 'telescope')
end

-- fzf_picker = 'telescope', telescope is available
T['choose_deltaview_menu()']['calls telescope picker when fzf_picker=telescope and telescope is available'] = function()
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = 'telescope'
        package.loaded['telescope'] = {}  -- simulate telescope installed
        M.choose_deltaview_menu()
    ]])

    eq(child.lua_get('_G.fixture.called'), 'telescope')
    eq(child.lua_get('_G.fixture.notified'), vim.NIL)
end

-- fzf_picker = 'telescope', telescope NOT available → warns and falls through to default.
-- Neither fzf-lua nor telescope available in default, so falls back to vim.cmd('copen').
T['choose_deltaview_menu()']['warns and falls back to default when fzf_picker=telescope but telescope is missing'] = function()
    child.lua(block_modules_lua, { 'fzf-lua', 'telescope' })
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = 'telescope'
        _G.fixture.copen_called = false
        vim.cmd = function(cmd) if cmd == 'copen' then _G.fixture.copen_called = true end end
        M.choose_deltaview_menu()
    ]])

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
    eq(child.lua_get('_G.fixture.copen_called'), true)
end

-- fzf_picker = 'telescope', telescope NOT available, but fzf-lua IS available in the default fallback
T['choose_deltaview_menu()']['falls back to fzf_lua in default path when telescope missing but fzf-lua available'] = function()
    child.lua(block_modules_lua, { 'telescope' })
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = 'telescope'
        package.loaded['fzf-lua'] = {}  -- fzf-lua installed
        M.choose_deltaview_menu()
    ]])

    eq(child.lua_get('_G.fixture.called'), 'fzf_lua')
end

-- fzf_picker = 'quickfix' → calls vim.cmd('copen') directly
T['choose_deltaview_menu()']['calls copen when fzf_picker=quickfix'] = function()
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = 'quickfix'
        _G.fixture.copen_called = false
        vim.cmd = function(cmd) if cmd == 'copen' then _G.fixture.copen_called = true end end
        M.choose_deltaview_menu()
    ]])

    eq(child.lua_get('_G.fixture.copen_called'), true)
    eq(child.lua_get('_G.fixture.notified'), vim.NIL)
end

-- fzf_picker = 'ui_select' → calls picker.open_vim_ui_select()
T['choose_deltaview_menu()']['calls ui_select picker when fzf_picker=ui_select'] = function()
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = 'ui_select'
        M.choose_deltaview_menu()
    ]])

    eq(child.lua_get('_G.fixture.called'), 'ui_select')
    eq(child.lua_get('_G.fixture.notified'), vim.NIL)
end

-- default path (nil/unknown picker), fzf-lua available → uses fzf-lua
T['choose_deltaview_menu()']['default path: uses fzf_lua when fzf-lua is available'] = function()
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = nil
        package.loaded['fzf-lua'] = {}  -- fzf-lua installed
        M.choose_deltaview_menu()
    ]])

    eq(child.lua_get('_G.fixture.called'), 'fzf_lua')
end

-- default path, fzf-lua NOT available, telescope available → uses telescope
T['choose_deltaview_menu()']['default path: uses telescope when fzf-lua missing but telescope available'] = function()
    child.lua(block_modules_lua, { 'fzf-lua' })
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = nil
        package.loaded['telescope'] = {}  -- telescope installed
        M.choose_deltaview_menu()
    ]])

    eq(child.lua_get('_G.fixture.called'), 'telescope')
end

-- default path, neither fzf-lua nor telescope available → falls back to vim.cmd('copen')
T['choose_deltaview_menu()']['default path: falls back to copen when no picker is available'] = function()
    child.lua(block_modules_lua, { 'fzf-lua', 'telescope' })
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = nil
        _G.fixture.copen_called = false
        vim.cmd = function(cmd) if cmd == 'copen' then _G.fixture.copen_called = true end end
        M.choose_deltaview_menu()
    ]])

    eq(child.lua_get('_G.fixture.copen_called'), true)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- create_diff_menu_pane() - example based tests

-- Helper: builds a list of sorted_file entries (the shape utils.get_sorted_diffed_files returns)
-- and a flat list of filenames (the shape utils.get_filenames_from_sortedfiles returns).
local function make_files(n)
    local sorted, names = {}, {}
    for i = 1, n do
        local name = 'file' .. i .. '.lua'
        table.insert(sorted, { name = name, added = i, removed = 0, status = 'M' })
        table.insert(names, name)
    end
    return sorted, names
end

T['create_diff_menu_pane()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- Happy-path defaults: we are inside a git repo, git rev-parse succeeds.
                vim.system = function(_cmd, _opts)
                    return {
                        wait = function()
                            return { code = 0, stdout = '/repo', stderr = '' }
                        end
                    }
                end

                -- Stub utils to return whatever fixture data the test sets up.
                package.loaded['deltaview.utils'].get_sorted_diffed_files = function(_ref)
                    return _G.fixture.sorted_files or {}
                end
                package.loaded['deltaview.utils'].get_filenames_from_sortedfiles = function(_sf)
                    return _G.fixture.mods or {}
                end

                -- Stub the sub-functions so create_diff_menu_pane orchestration is tested in isolation.
                M.setup_quickfix_deltaview_on_entry = function()
                    _G.fixture.setup_called = true
                end
                M.populate_quickfix_deltamenu_items = function(_ref, _mods, _cd)
                    _G.fixture.populate_called = true
                end
                M.choose_deltaview_menu = function()
                    _G.fixture.called = 'choose_menu'
                end
            ]])
        end,
    },
})

T['create_diff_menu_pane()']['notifies and returns when not in a git repository'] = function()
    child.lua([[
        vim.system = function(_cmd, _opts)
            return { wait = function() return { code = 128, stdout = '', stderr = '' } end }
        end
        M.create_diff_menu_pane('HEAD')
    ]])

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
    eq(child.lua_get('_G.fixture.called'), vim.NIL)
end

T['create_diff_menu_pane()']['raises when ref is nil'] = function()
    child.lua([[
        local ok, _err = pcall(function() M.create_diff_menu_pane(nil) end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['create_diff_menu_pane()']['notifies and returns when there are no modified files'] = function()
    child.lua([[
        _G.fixture.sorted_files = {}
        _G.fixture.mods = {}
        M.create_diff_menu_pane('HEAD')
    ]])

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
    eq(child.lua_get('_G.fixture.called'), vim.NIL)
end

T['create_diff_menu_pane()']['calls setup, populate, and choose_menu when there are modified files'] = function()
    local sorted, names = make_files(3)
    child.lua([[
        local sorted, names = ...
        _G.fixture.sorted_files = sorted
        _G.fixture.mods = names
        M.create_diff_menu_pane('HEAD')
    ]], { sorted, names })

    eq(child.lua_get('_G.fixture.setup_called'), true)
    eq(child.lua_get('_G.fixture.populate_called'), true)
    eq(child.lua_get('_G.fixture.called'), 'choose_menu')
end

return T
