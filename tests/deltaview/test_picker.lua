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

                -- Default: empty quickfix list so functions return early unless a test overrides this.
                vim.fn.getqflist = function(_opts) return { size = 0, items = {} } end
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

-- Shared helper: install a 2-entry deltaview quickfix list.
-- Use as: child.lua(setup_qflist)
local setup_qflist = [[
    vim.fn.getqflist = function(_opts)
        return {
            size = 2,
            items = {
                { user_data = { deltaview = true, bufname = 'a.lua', status = 'M', changes = '10', ref = 'HEAD' } },
                { user_data = { deltaview = true, bufname = 'b.lua', status = 'A', changes = '5',  ref = 'main' } },
            },
        }
    end
]]

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- open_vim_ui_select() - example based tests

T['open_vim_ui_select()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                vim.ui = {
                    select = function(items, opts, on_choice)
                        _G.fixture.select_items  = items
                        _G.fixture.select_prompt = opts and opts.prompt
                        _G.fixture.on_choice     = on_choice
                    end,
                }
                vim.cmd = function(cmd) _G.fixture.last_cmd = cmd end
            ]])
        end,
    },
})

T['open_vim_ui_select()']['returns early when quickfix list is empty'] = function()
    child.lua([[M.open_vim_ui_select()]])

    eq(child.lua_get('_G.fixture.select_items'), vim.NIL)
end

T['open_vim_ui_select()']['calls vim.ui.select with mods from quickfix list'] = function()
    child.lua(setup_qflist)
    child.lua([[M.open_vim_ui_select()]])

    eq(child.lua_get('_G.fixture.select_items'), { 'a.lua', 'b.lua' })
end

T['open_vim_ui_select()']['on_choice: does nothing when choice is nil'] = function()
    child.lua(setup_qflist)
    child.lua([[
        M.open_vim_ui_select()
        _G.fixture.on_choice(nil)
    ]])

    eq(child.lua_get('_G.fixture.last_cmd'), vim.NIL)
end

T['open_vim_ui_select()']['on_choice: runs cc with correct idx on selection'] = function()
    child.lua(setup_qflist)
    child.lua([[
        M.open_vim_ui_select()
        _G.fixture.on_choice('b.lua')
    ]])

    eq(child.lua_get('_G.fixture.last_cmd'), 'cc 2')
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
                        _G.fixture.fzf_exec_items  = items
                        _G.fixture.fzf_exec_prompt = opts.prompt
                        _G.fixture.fzf_exec_title  = opts.winopts and opts.winopts.title
                        _G.fixture.captured_default_action = opts.actions and opts.actions['default']
                    end
                }

                vim.fn.fnameescape = function(p) return p end
                vim.cmd = function(cmd) _G.fixture.last_cmd = cmd end
            ]])
        end,
    },
})

T['open_deltaview_fzf_lua_menu()']['returns early when quickfix list is empty'] = function()
    child.lua([[M.open_deltaview_fzf_lua_menu()]])

    eq(child.lua_get('_G.fixture.fzf_exec_items'), vim.NIL)
end

T['open_deltaview_fzf_lua_menu()']['calls fzf_exec with mods from quickfix list'] = function()
    child.lua(setup_qflist)
    child.lua([[M.open_deltaview_fzf_lua_menu()]])

    eq(child.lua_get('_G.fixture.fzf_exec_items'), { 'a.lua', 'b.lua' })
end

T['open_deltaview_fzf_lua_menu()']['calls fzf_exec with winopts title containing diff_target_ref'] = function()
    child.lua([[package.loaded['deltaview.state'].diff_target_ref = 'mybranch']])
    child.lua(setup_qflist)
    child.lua([[M.open_deltaview_fzf_lua_menu()]])

    local title = child.lua_get('_G.fixture.fzf_exec_title')
    eq(title:find('mybranch') ~= nil, true)
end

T['open_deltaview_fzf_lua_menu()']['default action: does nothing when selected is nil'] = function()
    child.lua(setup_qflist)
    child.lua([[
        M.open_deltaview_fzf_lua_menu()
        _G.fixture.captured_default_action(nil)
    ]])

    eq(child.lua_get('_G.fixture.last_cmd'), vim.NIL)
end

T['open_deltaview_fzf_lua_menu()']['default action: does nothing when selected is empty'] = function()
    child.lua(setup_qflist)
    child.lua([[
        M.open_deltaview_fzf_lua_menu()
        _G.fixture.captured_default_action({})
    ]])

    eq(child.lua_get('_G.fixture.last_cmd'), vim.NIL)
end

T['open_deltaview_fzf_lua_menu()']['default action: runs cc with correct idx on selection'] = function()
    child.lua(setup_qflist)
    child.lua([[
        M.open_deltaview_fzf_lua_menu()
        _G.fixture.captured_default_action({ 'b.lua' })
    ]])

    eq(child.lua_get('_G.fixture.last_cmd'), 'cc 2')
end

T['open_deltaview_fzf_lua_menu()']['default action: raises when selection not in quickfix list'] = function()
    child.lua(setup_qflist)
    child.lua([[
        M.open_deltaview_fzf_lua_menu()
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
                        _G.fixture.results_title  = picker_opts.results_title
                        _G.fixture.finder_results = picker_opts.finder and picker_opts.finder.results
                        if picker_opts.attach_mappings then
                            picker_opts.attach_mappings(0, function() end)
                        end
                        return { find = function(self) end }
                    end,
                }

                vim.fn.fnameescape = function(p) return p end
                vim.cmd = function(cmd) _G.fixture.last_cmd = cmd end
            ]])
        end,
    },
})

T['open_deltaview_telescope_menu()']['returns early when quickfix list is empty'] = function()
    child.lua([[M.open_deltaview_telescope_menu()]])

    eq(child.lua_get('_G.fixture.finder_results'), vim.NIL)
end

T['open_deltaview_telescope_menu()']['passes mods from quickfix list as finder results'] = function()
    child.lua(setup_qflist)
    child.lua([[M.open_deltaview_telescope_menu()]])

    eq(child.lua_get('_G.fixture.finder_results'), { 'a.lua', 'b.lua' })
end

T['open_deltaview_telescope_menu()']['results_title contains diff_target_ref'] = function()
    child.lua([[package.loaded['deltaview.state'].diff_target_ref = 'mybranch']])
    child.lua(setup_qflist)
    child.lua([[M.open_deltaview_telescope_menu()]])

    local title = child.lua_get('_G.fixture.results_title')
    eq(title:find('mybranch') ~= nil, true)
end

T['open_deltaview_telescope_menu()']['select_default: does nothing when get_selected_entry returns nil'] = function()
    child.lua(setup_qflist)
    child.lua([[
        _G.fixture.selected_entry = nil
        M.open_deltaview_telescope_menu()
        _G.fixture.captured_select_handler()
    ]])

    eq(child.lua_get('_G.fixture.last_cmd'), vim.NIL)
end

T['open_deltaview_telescope_menu()']['select_default: runs cc with correct idx on selection'] = function()
    child.lua(setup_qflist)
    child.lua([[
        _G.fixture.selected_entry = { value = 'b.lua' }
        M.open_deltaview_telescope_menu()
        _G.fixture.captured_select_handler()
    ]])

    eq(child.lua_get('_G.fixture.last_cmd'), 'cc 2')
end

T['open_deltaview_telescope_menu()']['select_default: raises when selection not in quickfix list'] = function()
    child.lua(setup_qflist)
    child.lua([[
        _G.fixture.selected_entry = { value = 'not_in_list.lua' }
        M.open_deltaview_telescope_menu()
        local ok, _err = pcall(function()
            _G.fixture.captured_select_handler()
        end)
        _G.fixture.assert_failed = not ok
    ]])

    eq(child.lua_get('_G.fixture.assert_failed'), true)
end

return T
