local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- Utility

-- usage: add the following to a pre case
-- child.lua(test_logging)
local test_logging = [[
    _G.test_logs = {}
    _G.captured_prints = {}
    local original_print = print
    print = function(...)
      local args = {...}
      local msg = table.concat(vim.tbl_map(tostring, args), ' ')
      table.insert(_G.captured_prints, msg)
      original_print(...)  -- Still call original for child's output
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
-- Test suite

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[M = require('deltaview')]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- `:DeltaView` integration

local setup_tmpdir_git_repo = [[
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    vim.fn.system('git -C ' .. tmpdir .. ' init')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.email "test@test.com"')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.name "Test"')
    local f = io.open(tmpdir .. '/test.lua', 'w')
    f:write('local x = 1\nlocal y = 2\n')
    f:close()
    vim.fn.system('git -C ' .. tmpdir .. ' add test.lua')
    vim.fn.system('git -C ' .. tmpdir .. ' commit -m "initial"')
    local f2 = io.open(tmpdir .. '/test.lua', 'w')
    f2:write('local x = 1\nlocal y = 99\n')
    f2:close()
    vim.cmd('cd ' .. tmpdir)
    vim.cmd('edit ' .. tmpdir .. '/test.lua')
]]

T['DeltaView integration'] = new_set({
    hooks = {
        pre_case = function()
            child.lua(setup_tmpdir_git_repo)
        end,
    },
})

T['DeltaView integration']['happy path: creates a delta buffer for a tracked file with changes'] = function()
    child.cmd('DeltaView HEAD')
    local has_diff_data  = child.lua_get('vim.b[vim.api.nvim_get_current_buf()].delta_diff_data_set ~= nil')
    local has_parsed     = child.lua_get('vim.b[vim.api.nvim_get_current_buf()].parsed_git_data ~= nil')
    local buf_on_window  = child.lua_get('vim.api.nvim_win_get_buf(0) == vim.api.nvim_get_current_buf()')
    local name           = child.lua_get('vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())')
    eq(has_diff_data, true)
    eq(has_parsed, true)
    eq(buf_on_window, true)
    eq(name:find('HEAD',     1, true) ~= nil, true)
    eq(name:find('test.lua', 1, true) ~= nil, true)
    eq(name:match('%d+')    ~= nil, true)
end

return T
