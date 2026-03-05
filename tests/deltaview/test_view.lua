local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ─── Utility ─────────────────────────────────────────────────────────────────

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

-- ─── Test suite ──────────────────────────────────────────────────────────────

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[M = require('deltaview.view')]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ─── deltaview_file() ────────────────────────────────────────────────────────

T['deltaview_file()'] = new_set()

T['deltaview_file()']['should open a buffer when '] = function()
    child.lua([[
        -- do stuff
    ]])

    local result = child.lua_get([[(function()
        return true
    end)()]])

    eq(result, true)
end

-- ─── get_cursor_placement_current_buffer() ───────────────────────────────────

T['get_cursor_placement_current_buffer()'] = new_set()

T['get_cursor_placement_current_buffer()']['returns the current window handle and cursor position'] = function()
    local cursor = { 2, 3 }

    child.lua([[
        local buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'line1', 'line2', 'line3' })
        vim.api.nvim_set_current_buf(buf)
        local winnr = vim.api.nvim_get_current_win()
        local cursor = ...
        vim.api.nvim_win_set_cursor(winnr, cursor)
        _G.fixture.winnr = winnr
        _G.fixture.cursor = cursor
    ]], { cursor })

    child.lua([[
        local cursor_placement = M.get_cursor_placement_current_buffer()
        _G.fixture.cursor_placement = cursor_placement
    ]])

    local winnr = child.lua_get([[_G.fixture.winnr]])
    local cursor_placement = child.lua_get([[_G.fixture.cursor_placement]])

    eq(cursor_placement.winnr, winnr)
    eq(cursor_placement.cursor, cursor)
end

return T
