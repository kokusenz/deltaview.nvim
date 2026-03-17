local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- utility

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

-- Restores the original require (called between cases via pre_case restart).
-- Not needed explicitly since child.restart() resets state, but useful if reusing state.

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                package.loaded['deltaview.config'] = {
                    options = {
                        fzf_picker = nil,
                        fzf_threshold = 10,
                    },
                }
                package.loaded['deltaview.picker'] = {
                    open_deltaview_fzf_lua_menu = function(_ref, _mods, _changes_data)
                        _G.fixture.called = 'fzf_lua'
                    end,
                    open_deltaview_telescope_menu = function(_ref, _mods, _changes_data)
                        _G.fixture.called = 'telescope'
                    end,
                    open_deltaview_fzf_junegunn_menu = function(_ref, _mods, _changes_data)
                        _G.fixture.called = 'fzf_junegunn'
                    end,
                    open_deltaview_quickselect_menu = function(_ref, _mods, _changes_data)
                        _G.fixture.called = 'quickselect'
                    end,
                }
                -- Stub unused deps so menu.lua can be required
                package.loaded['deltaview.utils'] = {
                    get_sorted_diffed_files = function(_) return {} end,
                    get_filenames_from_sortedfiles = function(_) return {} end,
                }
                package.loaded['deltaview.view'] = {}
                package.loaded['deltaview.state'] = {}

                vim.notify = function(msg, _level)
                    _G.fixture.notified = msg
                end

                M = require('deltaview.menu')
            ]])
            child.lua([[_G.fixture = {}]])
        end,
        post_once = child.stop,
    },
})

-- Shared test inputs
local ref = 'HEAD'
local mods = { 'foo.lua', 'bar.lua' }
local changes_data = { ['foo.lua'] = { '+1,-0' }, ['bar.lua'] = { '+3,-2' } }

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- choose_deltaview_fzf_menu() - example based tests

T['choose_deltaview_fzf_menu()'] = new_set()

-- fzf_picker = 'fzf-lua', fzf-lua is available
T['choose_deltaview_fzf_menu()']['calls fzf_lua picker when fzf_picker=fzf-lua and fzf-lua is available'] = function()
    child.lua([[
        local ref, mods, changes_data = ...
        package.loaded['deltaview.config'].options.fzf_picker = 'fzf-lua'
        package.loaded['fzf-lua'] = {}  -- simulate fzf-lua installed
        M.choose_deltaview_fzf_menu(ref, mods, changes_data)
    ]], { ref, mods, changes_data })

    eq(child.lua_get('_G.fixture.called'), 'fzf_lua')
    eq(child.lua_get('_G.fixture.notified'), vim.NIL)
end

-- fzf_picker = 'fzf-lua', fzf-lua NOT available → warns and falls through to default.
-- In the default path, with neither fzf-lua nor telescope, falls back to fzf_junegunn.
T['choose_deltaview_fzf_menu()']['warns and falls back to default when fzf_picker=fzf-lua but fzf-lua is missing'] = function()
    child.lua(block_modules_lua, { 'fzf-lua', 'telescope' })
    child.lua([[
        local ref, mods, changes_data = ...
        package.loaded['deltaview.config'].options.fzf_picker = 'fzf-lua'
        M.choose_deltaview_fzf_menu(ref, mods, changes_data)
    ]], { ref, mods, changes_data })

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
    eq(child.lua_get('_G.fixture.called'), 'fzf_junegunn')
end

-- fzf_picker = 'fzf-lua', fzf-lua NOT available, but telescope IS available in default fallback
T['choose_deltaview_fzf_menu()']['falls back to telescope in default path when fzf-lua missing but telescope available'] = function()
    child.lua(block_modules_lua, { 'fzf-lua' })
    child.lua([[
        local ref, mods, changes_data = ...
        package.loaded['deltaview.config'].options.fzf_picker = 'fzf-lua'
        package.loaded['telescope'] = {}  -- telescope installed
        M.choose_deltaview_fzf_menu(ref, mods, changes_data)
    ]], { ref, mods, changes_data })

    eq(child.lua_get('_G.fixture.called'), 'telescope')
end

-- fzf_picker = 'telescope', telescope is available
T['choose_deltaview_fzf_menu()']['calls telescope picker when fzf_picker=telescope and telescope is available'] = function()
    child.lua([[
        local ref, mods, changes_data = ...
        package.loaded['deltaview.config'].options.fzf_picker = 'telescope'
        package.loaded['telescope'] = {}  -- simulate telescope installed
        M.choose_deltaview_fzf_menu(ref, mods, changes_data)
    ]], { ref, mods, changes_data })

    eq(child.lua_get('_G.fixture.called'), 'telescope')
    eq(child.lua_get('_G.fixture.notified'), vim.NIL)
end

-- fzf_picker = 'telescope', telescope NOT available → warns and falls through to default.
-- Neither fzf-lua nor telescope available in default, so falls back to fzf_junegunn.
T['choose_deltaview_fzf_menu()']['warns and falls back to default when fzf_picker=telescope but telescope is missing'] = function()
    child.lua(block_modules_lua, { 'fzf-lua', 'telescope' })
    child.lua([[
        local ref, mods, changes_data = ...
        package.loaded['deltaview.config'].options.fzf_picker = 'telescope'
        M.choose_deltaview_fzf_menu(ref, mods, changes_data)
    ]], { ref, mods, changes_data })

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
    eq(child.lua_get('_G.fixture.called'), 'fzf_junegunn')
end

-- fzf_picker = 'telescope', telescope NOT available, but fzf-lua IS available in the default fallback
T['choose_deltaview_fzf_menu()']['falls back to fzf_lua in default path when telescope missing but fzf-lua available'] = function()
    child.lua(block_modules_lua, { 'telescope' })
    child.lua([[
        local ref, mods, changes_data = ...
        package.loaded['deltaview.config'].options.fzf_picker = 'telescope'
        package.loaded['fzf-lua'] = {}  -- fzf-lua installed
        M.choose_deltaview_fzf_menu(ref, mods, changes_data)
    ]], { ref, mods, changes_data })

    eq(child.lua_get('_G.fixture.called'), 'fzf_lua')
end

-- fzf_picker = 'fzf' always calls fzf_junegunn (it handles its own fallback internally)
T['choose_deltaview_fzf_menu()']['calls fzf_junegunn picker when fzf_picker=fzf'] = function()
    child.lua([[
        local ref, mods, changes_data = ...
        package.loaded['deltaview.config'].options.fzf_picker = 'fzf'
        M.choose_deltaview_fzf_menu(ref, mods, changes_data)
    ]], { ref, mods, changes_data })

    eq(child.lua_get('_G.fixture.called'), 'fzf_junegunn')
    eq(child.lua_get('_G.fixture.notified'), vim.NIL)
end

-- default path (nil/unknown picker), fzf-lua available → uses fzf-lua
T['choose_deltaview_fzf_menu()']['default path: uses fzf_lua when fzf-lua is available'] = function()
    child.lua([[
        local ref, mods, changes_data = ...
        package.loaded['deltaview.config'].options.fzf_picker = nil
        package.loaded['fzf-lua'] = {}  -- fzf-lua installed
        M.choose_deltaview_fzf_menu(ref, mods, changes_data)
    ]], { ref, mods, changes_data })

    eq(child.lua_get('_G.fixture.called'), 'fzf_lua')
end

-- default path, fzf-lua NOT available, telescope available → uses telescope
T['choose_deltaview_fzf_menu()']['default path: uses telescope when fzf-lua missing but telescope available'] = function()
    child.lua(block_modules_lua, { 'fzf-lua' })
    child.lua([[
        local ref, mods, changes_data = ...
        package.loaded['deltaview.config'].options.fzf_picker = nil
        package.loaded['telescope'] = {}  -- telescope installed
        M.choose_deltaview_fzf_menu(ref, mods, changes_data)
    ]], { ref, mods, changes_data })

    eq(child.lua_get('_G.fixture.called'), 'telescope')
end

-- default path, neither fzf-lua nor telescope available → falls back to fzf_junegunn
T['choose_deltaview_fzf_menu()']['default path: falls back to fzf_junegunn when no picker is available'] = function()
    child.lua(block_modules_lua, { 'fzf-lua', 'telescope' })
    child.lua([[
        local ref, mods, changes_data = ...
        package.loaded['deltaview.config'].options.fzf_picker = nil
        M.choose_deltaview_fzf_menu(ref, mods, changes_data)
    ]], { ref, mods, changes_data })

    eq(child.lua_get('_G.fixture.called'), 'fzf_junegunn')
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- create_diff_menu_pane() - example based tests

-- Helper: builds a list of sorted_file entries (the shape utils.get_sorted_diffed_files returns)
-- and a flat list of filenames (the shape utils.get_filenames_from_sortedfiles returns).
local function make_files(n)
    local sorted, names = {}, {}
    for i = 1, n do
        local name = 'file' .. i .. '.lua'
        table.insert(sorted, { name = name, added = i, removed = 0 })
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

                -- Stub choose_deltaview_fzf_menu so threshold tests don't invoke picker logic.
                M.choose_deltaview_fzf_menu = function(_ref, _mods, _changes_data)
                    _G.fixture.called = 'choose_fzf_menu'
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

T['create_diff_menu_pane()']['opens quickselect when mods count is below threshold'] = function()
    local sorted, names = make_files(3)
    child.lua([[
        local sorted, names = ...
        _G.fixture.sorted_files = sorted
        _G.fixture.mods = names
        package.loaded['deltaview.config'].options.fzf_threshold = 6
        M.create_diff_menu_pane('HEAD')
    ]], { sorted, names })

    eq(child.lua_get('_G.fixture.called'), 'quickselect')
end

T['create_diff_menu_pane()']['opens fzf menu when mods count equals threshold'] = function()
    local sorted, names = make_files(6)
    child.lua([[
        local sorted, names = ...
        _G.fixture.sorted_files = sorted
        _G.fixture.mods = names
        package.loaded['deltaview.config'].options.fzf_threshold = 6
        M.create_diff_menu_pane('HEAD')
    ]], { sorted, names })

    eq(child.lua_get('_G.fixture.called'), 'choose_fzf_menu')
end

T['create_diff_menu_pane()']['opens fzf menu when mods count exceeds threshold'] = function()
    local sorted, names = make_files(10)
    child.lua([[
        local sorted, names = ...
        _G.fixture.sorted_files = sorted
        _G.fixture.mods = names
        package.loaded['deltaview.config'].options.fzf_threshold = 6
        M.create_diff_menu_pane('HEAD')
    ]], { sorted, names })

    eq(child.lua_get('_G.fixture.called'), 'choose_fzf_menu')
end

return T
