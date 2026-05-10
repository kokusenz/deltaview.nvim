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

-- default path, both unavailable → falls back to ui_select
T['choose_deltaview_menu()']['default path: uses ui_select when both fzf-lua and telescope unavailable'] = function()
    child.lua(block_modules_lua, { 'fzf-lua', 'telescope' })
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = nil
        M.choose_deltaview_menu({})
    ]])

    eq(child.lua_get('_G.fixture.called'), 'ui_select')
end

-- fzf_picker='fzf-lua', both unavailable → notifies + ui_select
T['choose_deltaview_menu()']['fzf_picker=fzf-lua: notifies and falls back to ui_select when both unavailable'] = function()
    child.lua(block_modules_lua, { 'fzf-lua', 'telescope' })
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = 'fzf-lua'
        M.choose_deltaview_menu({})
    ]])

    eq(child.lua_get('_G.fixture.called'), 'ui_select')
    eq(type(child.lua_get('_G.fixture.notified')), 'string')
end

-- fzf_picker='telescope', both unavailable → notifies + ui_select
T['choose_deltaview_menu()']['fzf_picker=telescope: notifies and falls back to ui_select when both unavailable'] = function()
    child.lua(block_modules_lua, { 'fzf-lua', 'telescope' })
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = 'telescope'
        M.choose_deltaview_menu({})
    ]])

    eq(child.lua_get('_G.fixture.called'), 'ui_select')
    eq(type(child.lua_get('_G.fixture.notified')), 'string')
end

-- deltaview_qf_list argument is passed through to the selected picker function
T['choose_deltaview_menu()']['passes deltaview_qf_list to the selected picker function'] = function()
    child.lua([[
        package.loaded['deltaview.config'].options.fzf_picker = 'ui_select'
        package.loaded['deltaview.picker'].open_vim_ui_select = function(dv_list, _fn)
            _G.fixture.picker_dv_list = dv_list
            _G.fixture.called = 'ui_select'
        end
        local test_list = { { filename = '/a.lua', user_data = { deltaview = true, bufname = 'a.lua' } } }
        M.choose_deltaview_menu(test_list)
    ]])

    local list = child.lua_get([[_G.fixture.picker_dv_list]])
    eq(#list, 1)
    eq(list[1].filename, '/a.lua')
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

-- choose_deltaview_menu receives an entry with fully-populated user_data for a modified file
T['create_diff_menu_pane()']['choose_deltaview_menu receives correct entry user_data for a modified file'] = function()
    child.lua([[
        _G.fixture.sorted_files = { { name = 'a.lua', added = 10, removed = 5, status = 'M' } }
        _G.fixture.mods = { 'a.lua' }
        _G.fixture.choose_args = nil
        M.choose_deltaview_menu = function(dv_list)
            _G.fixture.called = 'choose_menu'
            _G.fixture.choose_args = dv_list
        end
        M.create_diff_menu_pane('HEAD')
    ]])

    local args = child.lua_get([[_G.fixture.choose_args]])
    eq(#args, 1)
    local ud = args[1].user_data
    eq(ud.deltaview, true)
    eq(ud.bufname, 'a.lua')
    eq(ud.abs_path, '/repo/a.lua')
    eq(ud.ref, 'HEAD')
    eq(ud.status, 'M')
    eq(ud.changes, '+10,-5')
    eq(ud.show_delta_on_entry, true)
    eq(args[1].filename, '/repo/a.lua')
end

-- deleted-file entry carries the /tmp/deltaview://deleted/ sentinel in its filename
-- so neovim does not try to open the (non-existent) file from disk
T['create_diff_menu_pane()']['deleted file entry uses /tmp/deltaview://deleted/ prefix in filename'] = function()
    child.lua([[
        _G.fixture.sorted_files = { { name = 'old.lua', added = 0, removed = 20, status = 'D' } }
        _G.fixture.mods = { 'old.lua' }
        _G.fixture.choose_args = nil
        M.choose_deltaview_menu = function(dv_list)
            _G.fixture.called = 'choose_menu'
            _G.fixture.choose_args = dv_list
        end
        M.create_diff_menu_pane('HEAD')
    ]])

    local args = child.lua_get([[_G.fixture.choose_args]])
    eq(#args, 1)
    local entry = args[1]
    -- filename carries the sentinel prefix so the autocmd callback can recognise deleted files
    eq(entry.filename, '/tmp/deltaview://deleted//repo/old.lua')
    -- abs_path is the real path without the prefix, used when opening the diff view
    eq(entry.user_data.abs_path, '/repo/old.lua')
    eq(entry.user_data.status, 'D')
    eq(entry.user_data.changes, '+0,-20')
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- populate_quickfix_deltamenu_items() - example based tests

T['populate_quickfix_deltamenu_items()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- Happy-path git stub (same pattern as create_diff_menu_pane suite)
                vim.system = function(_cmd, _opts)
                    return {
                        wait = function()
                            return { code = 0, stdout = '/repo', stderr = '' }
                        end
                    }
                end

                -- diff_target_ref is read via require('deltaview.state') inside the function
                package.loaded['deltaview.state'].diff_target_ref = 'HEAD'

                package.loaded['deltaview.utils'].get_sorted_diffed_files = function(_ref)
                    return _G.fixture.sorted_files or {}
                end
                package.loaded['deltaview.utils'].get_filenames_from_sortedfiles = function(_sf)
                    return _G.fixture.mods or {}
                end
            ]])
        end,
    },
})

T['populate_quickfix_deltamenu_items()']['notifies and returns when there are no modified files'] = function()
    child.lua([[
        _G.fixture.sorted_files = {}
        _G.fixture.mods = {}
        M.populate_quickfix_deltamenu_items()
    ]])

    eq(type(child.lua_get('_G.fixture.notified')), 'string')
end

-- title format: 'DeltaView Menu  |  <vs> <ref>'
-- config.viewconfig().vs = '|' (top-level pre_case); state.diff_target_ref = 'HEAD'
T['populate_quickfix_deltamenu_items()']['sets qflist title including ref and viewconfig separator'] = function()
    child.lua([[
        _G.fixture.sorted_files = { { name = 'a.lua', added = 1, removed = 0, status = 'M' } }
        _G.fixture.mods = { 'a.lua' }
        M.populate_quickfix_deltamenu_items()
    ]])

    local title = child.lua_get([[vim.fn.getqflist({ title = 1 }).title]])
    eq(title, 'DeltaView Menu  |  | HEAD')
end

T['populate_quickfix_deltamenu_items()']['sets qflist item with correct user_data for a modified file'] = function()
    child.lua([[
        _G.fixture.sorted_files = { { name = 'a.lua', added = 10, removed = 5, status = 'M' } }
        _G.fixture.mods = { 'a.lua' }
        M.populate_quickfix_deltamenu_items()
    ]])

    local ud = child.lua_get([[vim.fn.getqflist({ items = 1 }).items[1].user_data]])
    eq(ud.deltaview, true)
    eq(ud.bufname, 'a.lua')
    eq(ud.abs_path, '/repo/a.lua')
    eq(ud.ref, 'HEAD')
    eq(ud.status, 'M')
    eq(ud.changes, '+10,-5')
    eq(ud.show_delta_on_entry, true)
end

T['populate_quickfix_deltamenu_items()']['deleted file item has /tmp/deltaview://deleted/ prefix in filename'] = function()
    child.lua([[
        _G.fixture.sorted_files = { { name = 'old.lua', added = 0, removed = 20, status = 'D' } }
        _G.fixture.mods = { 'old.lua' }
        M.populate_quickfix_deltamenu_items()
        -- getqflist returns bufnr, not filename; resolve via nvim_buf_get_name
        local raw = vim.fn.getqflist({ items = 1 }).items[1]
        _G.fixture.item_filename = vim.api.nvim_buf_get_name(raw.bufnr)
        _G.fixture.item_ud       = raw.user_data
    ]])

    eq(child.lua_get('_G.fixture.item_filename'), '/tmp/deltaview://deleted//repo/old.lua')
    eq(child.lua_get('_G.fixture.item_ud.abs_path'), '/repo/old.lua')
    eq(child.lua_get('_G.fixture.item_ud.status'), 'D')
end

-- quickfixtextfunc is the function neovim calls to render each quickfix line.
-- Spy on setqflist to capture it, use the real qflist id for the internal getqflist call.
T['populate_quickfix_deltamenu_items()']['quickfixtextfunc formats deltaview item as status path changes'] = function()
    child.lua([[
        _G.fixture.sorted_files = { { name = 'a.lua', added = 10, removed = 5, status = 'M' } }
        _G.fixture.mods = { 'a.lua' }

        local captured_qftf = nil
        local orig_setqflist = vim.fn.setqflist
        vim.fn.setqflist = function(list, action, opts)
            if opts and opts.quickfixtextfunc then
                captured_qftf = opts.quickfixtextfunc
            end
            orig_setqflist(list, action, opts)
        end

        M.populate_quickfix_deltamenu_items()

        -- Call the quickfixtextfunc with the real qflist id so its internal
        -- vim.fn.getqflist({id=...}) hits the actual populated list.
        local qf_id = vim.fn.getqflist({ id = 0 }).id
        _G.fixture.qftf_result = captured_qftf({ id = qf_id, start_idx = 1, end_idx = 1 })
    ]])

    local result = child.lua_get([[_G.fixture.qftf_result]])
    eq(result, { 'M a.lua > +10,-5' })
end

-- quickfixtextfunc must skip entries that do not have user_data.deltaview = true
T['populate_quickfix_deltamenu_items()']['quickfixtextfunc skips non-deltaview items'] = function()
    child.lua([[
        _G.fixture.sorted_files = { { name = 'a.lua', added = 2, removed = 0, status = 'M' } }
        _G.fixture.mods = { 'a.lua' }

        local captured_qftf = nil
        local orig_setqflist = vim.fn.setqflist
        vim.fn.setqflist = function(list, action, opts)
            if opts and opts.quickfixtextfunc then
                captured_qftf = opts.quickfixtextfunc
            end
            orig_setqflist(list, action, opts)
        end

        M.populate_quickfix_deltamenu_items()

        -- Override getqflist so the quickfixtextfunc sees a mixed list
        -- (one deltaview entry + one non-deltaview entry).
        local orig_getqflist = vim.fn.getqflist
        vim.fn.getqflist = function(_opts)
            return {
                items = {
                    { user_data = { deltaview = true,  status = 'M', bufname = 'a.lua',       changes = '+2,-0' } },
                    { user_data = { deltaview = false, status = 'M', bufname = 'ignored.lua', changes = '+1,-0' } },
                }
            }
        end
        _G.fixture.qftf_result = captured_qftf({ id = 1, start_idx = 1, end_idx = 2 })
        vim.fn.getqflist = orig_getqflist
    ]])

    local result = child.lua_get([[_G.fixture.qftf_result]])
    eq(result, { 'M a.lua > +2,-0' })
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

-- After the first BufWinEnter for a deltaview entry, clear_delta_entry marks that entry's
-- show_delta_on_entry as false so the diff view is not re-opened on the next visit.
T['setup_quickfix_deltaview_on_entry()']['callback: clears show_delta_on_entry for the entry after first visit'] = function()
    child.lua(setup_autocmd_qflist_lua, { '/repo/foo.lua', true, 'M' })
    child.lua([[
        M.setup_quickfix_deltaview_on_entry()
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, '/repo/foo.lua')
        vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = buf })
        -- _G.fixture.done is set by the register_keybind spy after 3 calls,
        -- which happen after the scheduled clear_delta_entry has already run.
        vim.wait(300, function() return _G.fixture.done end)
    ]])

    local show = child.lua_get([[vim.fn.getqflist({ items = 1 }).items[1].user_data.show_delta_on_entry]])
    eq(show, false)
end

return T
