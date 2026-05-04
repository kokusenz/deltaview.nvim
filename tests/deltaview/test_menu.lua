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

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- populate_quickfix_deltamenu_items() - example based tests

T['populate_quickfix_deltamenu_items()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- Spy on setqflist; store only msgpack-serializable fields (no Lua functions)
                -- so child.lua_get can cross the RPC boundary cleanly.
                -- The quickfixtextfunc is stored separately under _G.fixture.last_qtf.
                _G.fixture.setqflist_call_count = 0
                _G.fixture.last_qtf = nil
                _G.fixture.last_title = nil
                _G.fixture.last_items = nil
                vim.fn.setqflist = function(_a, _b, c)
                    _G.fixture.setqflist_call_count = _G.fixture.setqflist_call_count + 1
                    if c then
                        _G.fixture.last_title = c.title
                        _G.fixture.last_items = c.items
                        _G.fixture.last_qtf = c.quickfixtextfunc
                    end
                end
            ]])
        end,
    },
})

T['populate_quickfix_deltamenu_items()']['raises when ref is nil'] = function()
    child.lua([[
        local ok, _ = pcall(function()
            M.populate_quickfix_deltamenu_items(nil, { 'foo.lua' }, { ['foo.lua'] = { changes = '+1,-0', status = 'M' } })
        end)
        _G.fixture.assert_failed = not ok
    ]])
    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['populate_quickfix_deltamenu_items()']['raises when mods is nil'] = function()
    child.lua([[
        local ok, _ = pcall(function()
            M.populate_quickfix_deltamenu_items('HEAD', nil, {})
        end)
        _G.fixture.assert_failed = not ok
    ]])
    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['populate_quickfix_deltamenu_items()']['raises when changes_data is nil'] = function()
    child.lua([[
        local ok, _ = pcall(function()
            M.populate_quickfix_deltamenu_items('HEAD', { 'foo.lua' }, nil)
        end)
        _G.fixture.assert_failed = not ok
    ]])
    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

T['populate_quickfix_deltamenu_items()']['calls setqflist exactly once'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('HEAD', { 'foo.lua' }, {
            ['foo.lua'] = { changes = '+1,-0', status = 'M' }
        })
    ]])
    eq(child.lua_get('_G.fixture.setqflist_call_count'), 1)
end

T['populate_quickfix_deltamenu_items()']['title includes the ref'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('my-branch', { 'foo.lua' }, {
            ['foo.lua'] = { changes = '+1,-0', status = 'M' }
        })
    ]])
    local title = child.lua_get('_G.fixture.last_title')
    eq(type(title), 'string')
    eq(title:find('my-branch', 1, true) ~= nil, true)
end

T['populate_quickfix_deltamenu_items()']['title includes the viewconfig separator'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('HEAD', { 'foo.lua' }, {
            ['foo.lua'] = { changes = '+1,-0', status = 'M' }
        })
    ]])
    local title = child.lua_get('_G.fixture.last_title')
    -- top-level stub returns { vs = '|' }
    eq(title:find('|') ~= nil, true)
end

T['populate_quickfix_deltamenu_items()']['modified file: filename is git_rel_to_abs path'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('HEAD', { 'src/foo.lua' }, {
            ['src/foo.lua'] = { changes = '+2,-1', status = 'M' }
        })
    ]])
    local filename = child.lua_get('_G.fixture.last_items[1].filename')
    -- git_rel_to_abs stub returns '/repo/' .. path
    eq(filename, '/repo/src/foo.lua')
end

T['populate_quickfix_deltamenu_items()']['deleted file: filename has /tmp/deltaview://deleted/ prefix'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('HEAD', { 'old.lua' }, {
            ['old.lua'] = { changes = '+0,-5', status = 'D' }
        })
    ]])
    local filename = child.lua_get('_G.fixture.last_items[1].filename')
    eq(filename, '/tmp/deltaview://deleted//repo/old.lua')
end

T['populate_quickfix_deltamenu_items()']['deleted file: user_data.abs_path is git_rel_to_abs without /tmp prefix'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('HEAD', { 'old.lua' }, {
            ['old.lua'] = { changes = '+0,-5', status = 'D' }
        })
    ]])
    local abs_path = child.lua_get('_G.fixture.last_items[1].user_data.abs_path')
    -- abs_path must be the real path, not the /tmp sentinel
    eq(abs_path, '/repo/old.lua')
end

T['populate_quickfix_deltamenu_items()']['user_data.deltaview is true'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('HEAD', { 'foo.lua' }, {
            ['foo.lua'] = { changes = '+1,-0', status = 'M' }
        })
    ]])
    eq(child.lua_get('_G.fixture.last_items[1].user_data.deltaview'), true)
end

T['populate_quickfix_deltamenu_items()']['user_data.bufname is the relative path'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('HEAD', { 'src/foo.lua' }, {
            ['src/foo.lua'] = { changes = '+1,-0', status = 'M' }
        })
    ]])
    eq(child.lua_get('_G.fixture.last_items[1].user_data.bufname'), 'src/foo.lua')
end

T['populate_quickfix_deltamenu_items()']['user_data.show_delta_on_entry is true'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('HEAD', { 'foo.lua' }, {
            ['foo.lua'] = { changes = '+1,-0', status = 'M' }
        })
    ]])
    eq(child.lua_get('_G.fixture.last_items[1].user_data.show_delta_on_entry'), true)
end

T['populate_quickfix_deltamenu_items()']['user_data.ref matches the given ref'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('v1.2.3', { 'foo.lua' }, {
            ['foo.lua'] = { changes = '+1,-0', status = 'M' }
        })
    ]])
    eq(child.lua_get('_G.fixture.last_items[1].user_data.ref'), 'v1.2.3')
end

T['populate_quickfix_deltamenu_items()']['user_data.status comes from changes_data'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('HEAD', { 'foo.lua' }, {
            ['foo.lua'] = { changes = '+0,-3', status = 'D' }
        })
    ]])
    eq(child.lua_get('_G.fixture.last_items[1].user_data.status'), 'D')
end

T['populate_quickfix_deltamenu_items()']['user_data.changes comes from changes_data'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('HEAD', { 'foo.lua' }, {
            ['foo.lua'] = { changes = '+7,-2', status = 'M' }
        })
    ]])
    eq(child.lua_get('_G.fixture.last_items[1].user_data.changes'), '+7,-2')
end

T['populate_quickfix_deltamenu_items()']['quickfixtextfunc formats deltaview entries as status bufname > changes'] = function()
    child.lua([[
        M.populate_quickfix_deltamenu_items('HEAD', { 'foo.lua' }, {
            ['foo.lua'] = { changes = '+3,-1', status = 'M' }
        })
        local qtf = _G.fixture.last_qtf

        -- Mock getqflist so the function has items to format
        local fake_items = {
            {
                user_data = {
                    deltaview = true,
                    bufname = 'foo.lua',
                    status = 'M',
                    changes = '+3,-1',
                }
            }
        }
        vim.fn.getqflist = function(_opts) return { items = fake_items } end

        _G.fixture.qtf_result = qtf({ id = 1, start_idx = 1, end_idx = 1 })
    ]])
    local result = child.lua_get('_G.fixture.qtf_result')
    eq(result, { 'M foo.lua > +3,-1' })
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup_quickfix_deltaview_on_entry() - example based tests

-- Shared helper: creates a qflist containing one deltaview entry for the given path.
-- The abs_path in user_data is used by get_delta_entry to match the buffer by name.
local setup_autocmd_qflist_lua = [[
    local abs_path, show_delta_on_entry, status = ...
    show_delta_on_entry = show_delta_on_entry == nil and true or show_delta_on_entry
    status = status or 'M'
    vim.fn.setqflist({}, ' ', {
        nr = '$',
        title = 'DeltaView Menu test',
        items = {{
            filename = abs_path,
            text = 'test entry',
            user_data = {
                deltaview = true,
                bufname = 'foo.lua',
                abs_path = abs_path,
                show_delta_on_entry = show_delta_on_entry,
                ref = 'HEAD',
                status = status,
                changes = '+1,-0',
            }
        }}
    })
]]

T['setup_quickfix_deltaview_on_entry()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- Spies for view, utils, and help so autocmd callback side-effects can be observed
                _G.fixture.undo_called = false
                package.loaded['deltaview.utils'].undo_deltamenu_qf_list = function()
                    _G.fixture.undo_called = true
                end

                _G.fixture.deltaview_file_args = nil
                package.loaded['deltaview.view'].deltaview_file = function(ref)
                    _G.fixture.deltaview_file_args = ref
                    return 42
                end

                _G.fixture.delta_path_args = nil
                package.loaded['deltaview.view'].delta_path = function(ref, ctx, path)
                    _G.fixture.delta_path_args = { ref = ref, ctx = ctx, path = path }
                    return 42
                end

                _G.fixture.register_keybind_calls = {}
                package.loaded['deltaview.help'].register_keybind = function(bufnr, key, _desc)
                    table.insert(_G.fixture.register_keybind_calls, { bufnr = bufnr, key = key })
                    if #_G.fixture.register_keybind_calls >= 3 then
                        _G.fixture.done = true
                    end
                end
            ]])
        end,
    },
})

T['setup_quickfix_deltaview_on_entry()']['registers a BufWinEnter autocmd'] = function()
    local count_before = child.lua_get([[
        #vim.api.nvim_get_autocmds({ event = 'BufWinEnter', pattern = '*' })
    ]])
    child.lua([[M.setup_quickfix_deltaview_on_entry()]])
    local count_after = child.lua_get([[
        #vim.api.nvim_get_autocmds({ event = 'BufWinEnter', pattern = '*' })
    ]])
    eq(count_after, count_before + 1)
end

T['setup_quickfix_deltaview_on_entry()']['is idempotent: second call does not register a second autocmd'] = function()
    child.lua([[M.setup_quickfix_deltaview_on_entry()]])
    local count_after_first = child.lua_get([[
        #vim.api.nvim_get_autocmds({ event = 'BufWinEnter', pattern = '*' })
    ]])
    child.lua([[M.setup_quickfix_deltaview_on_entry()]])
    local count_after_second = child.lua_get([[
        #vim.api.nvim_get_autocmds({ event = 'BufWinEnter', pattern = '*' })
    ]])
    eq(count_after_first, count_after_second)
end

T['setup_quickfix_deltaview_on_entry()']['callback: skips buffers with non-empty buftype'] = function()
    child.lua([[
        M.setup_quickfix_deltaview_on_entry()
        -- scratch buffer has buftype='nofile', should be ignored by the callback
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = buf })
    ]])
    -- Neither undo nor deltaview_file should have been called
    eq(child.lua_get('_G.fixture.undo_called'), false)
    eq(child.lua_get('_G.fixture.deltaview_file_args'), vim.NIL)
end

T['setup_quickfix_deltaview_on_entry()']['callback: calls undo_deltamenu_qf_list when buffer is not a deltaview entry'] = function()
    child.lua([[
        M.setup_quickfix_deltaview_on_entry()
        -- qflist is empty, so buffer will not match any entry
        vim.fn.setqflist({})
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, '/some/unrelated/file.lua')
        vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = buf })
    ]])
    eq(child.lua_get('_G.fixture.undo_called'), true)
    eq(child.lua_get('_G.fixture.deltaview_file_args'), vim.NIL)
end

T['setup_quickfix_deltaview_on_entry()']['callback: does nothing when show_delta_on_entry is false'] = function()
    child.lua(setup_autocmd_qflist_lua, { '/repo/foo.lua', false, 'M' })
    child.lua([[
        M.setup_quickfix_deltaview_on_entry()
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, '/repo/foo.lua')
        vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = buf })
    ]])
    -- show_delta_on_entry=false: skip, neither undo nor view should be called
    eq(child.lua_get('_G.fixture.undo_called'), false)
    eq(child.lua_get('_G.fixture.deltaview_file_args'), vim.NIL)
end

T['setup_quickfix_deltaview_on_entry()']['callback: calls view.deltaview_file for a modified file'] = function()
    child.lua(setup_autocmd_qflist_lua, { '/repo/foo.lua', true, 'M' })
    child.lua([[
        M.setup_quickfix_deltaview_on_entry()
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, '/repo/foo.lua')
        vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = buf })
        vim.wait(300, function() return _G.fixture.done end)
    ]])
    eq(child.lua_get('_G.fixture.deltaview_file_args'), 'HEAD')
    eq(child.lua_get('_G.fixture.delta_path_args'), vim.NIL)
end

T['setup_quickfix_deltaview_on_entry()']['callback: calls view.delta_path for a deleted file'] = function()
    child.lua(setup_autocmd_qflist_lua, { '/repo/old.lua', true, 'D' })
    child.lua([[
        M.setup_quickfix_deltaview_on_entry()
        local buf = vim.api.nvim_create_buf(true, false)
        -- deleted file buffers carry the /tmp/deltaview://deleted/ sentinel in their name
        vim.api.nvim_buf_set_name(buf, '/tmp/deltaview://deleted//repo/old.lua')
        vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = buf })
        vim.wait(300, function() return _G.fixture.done end)
    ]])
    local delta_path_args = child.lua_get('_G.fixture.delta_path_args')
    eq(delta_path_args.ref, 'HEAD')
    eq(delta_path_args.path, '/repo/old.lua')
    eq(child.lua_get('_G.fixture.deltaview_file_args'), vim.NIL)
end

T['setup_quickfix_deltaview_on_entry()']['callback: registers three help keybinds after opening diff view'] = function()
    child.lua(setup_autocmd_qflist_lua, { '/repo/foo.lua', true, 'M' })
    child.lua([[
        M.setup_quickfix_deltaview_on_entry()
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, '/repo/foo.lua')
        vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = buf })
        vim.wait(300, function() return _G.fixture.done end)
    ]])
    eq(child.lua_get('#_G.fixture.register_keybind_calls'), 3)
    -- every keybind call should receive the bufnr returned by deltaview_file (42)
    eq(child.lua_get('_G.fixture.register_keybind_calls[1].bufnr'), 42)
end

T['setup_quickfix_deltaview_on_entry()']['callback: notifies on error from view function'] = function()
    child.lua(setup_autocmd_qflist_lua, { '/repo/foo.lua', true, 'M' })
    child.lua([[
        -- Make deltaview_file throw so the pcall catches it
        package.loaded['deltaview.view'].deltaview_file = function(_)
            error('boom')
        end
        _G.fixture.done = false
        vim.notify = function(msg, _level)
            _G.fixture.notified = msg
            _G.fixture.done = true
        end
        M.setup_quickfix_deltaview_on_entry()
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, '/repo/foo.lua')
        vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = buf })
        vim.wait(300, function() return _G.fixture.done end)
    ]])
    local notified = child.lua_get('_G.fixture.notified')
    eq(type(notified), 'string')
    eq(notified:find('boom') ~= nil, true)
end

return T
