local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- utility

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
-- setup

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                package.loaded['deltaview.utils'] = {
                    read_file_lines = function(_path) return {} end,
                }
                package.loaded['deltaview.config'] = {
                    options = {
                        line_numbers = false,
                        keyconfig = { next_hunk = '<Tab>', prev_hunk = '<S-Tab>' },
                    },
                    viewconfig = function() return { vs = 'vs', segment = '§' } end,
                }
                _G.Delta = {
                    parse = { get_diff_data_git = function(_) return {} end },
                    text_diff = function(_s1, _s2, _lang, _opts) return nil end,
                    highlight_delta_artifacts = function(_bufnr) end,
                    syntax_highlight_diff_set = function(_bufnr) end,
                    diff_highlight_diff = function(_bufnr) end,
                    setup_delta_statuscolumn = function(_bufnr) end,
                }
                vim.fn.systemlist = function(_) return { '/repo' } end
                -- mocking shell functions, assuming success here.
                vim.system = function(cmd, _opts)
                    local stdout = ''
                    if _cmd[1] == 'git' and _cmd[2] == 'rev-parse' and _cmd[3] == '--show-toplevel' then
                        stdout = '/home/exampleuser/example'
                    elseif _cmd[1] == 'git' and _cmd[2] == 'diff' and _cmd[3] == '-U0' then
                        local single_file_git_diff = table.concat({
                            "diff --git a/foo.lua b/foo.lua",
                            "index abc1234..def5678 100644",
                            "--- a/foo.lua",
                            "+++ b/foo.lua",
                            "@@ -1,3 +1,3 @@",
                            " local x = 1",
                            "-local y = 2",
                            "+local y = 10",
                            " local z = 3",
                        }, "\n")
                        stdout = singel_file_git_diff
                    end

                    return {
                        wait = function()
                            return { code = 0, stdout = stdout, stderr = '' }
                        end
                    }
                end
            ]])
            child.lua([[M = require('deltaview.view')]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- deltaview_file()

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

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- open_git_diff_buffer()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_cursor_placement_current_buffer() - example based tests

T['get_cursor_placement_current_buffer()'] = new_set()

T['get_cursor_placement_current_buffer()']['returns the current window handle and cursor position'] = function()
    local cursor = { 2, 3 }
    local window = 1000

    child.lua([[
        local buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'line1', 'line2', 'line3' })
        local winnr, cursor = ...
        vim.api.nvim_set_current_win(winnr)
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_win_set_cursor(winnr, cursor)
        _G.fixture.winnr = winnr
        _G.fixture.cursor = cursor
    ]], { window, cursor })

    child.lua([[
        local cursor_placement = M.get_cursor_placement_current_buffer()
        _G.fixture.cursor_placement = cursor_placement
    ]])

    local cursor_placement = child.lua_get([[_G.fixture.cursor_placement]])

    eq(cursor_placement.winnr, window)
    eq(cursor_placement.cursor, cursor)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- place_cursor_delta_buffer_entry() - property based tests

--- @class place_cursor_delta_buffer_entry__property_cases
local place_cursor_delta_buffer_entry__property_cases = {
    {
        name = 'added line, cursor at top',
        cursor_placement = { winnr = 0, cursor = { 1, 0 } },
        buf_contents = { 'line1', 'line2', 'line3' },
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'line 1',
                                old_line_num = 1,
                                new_line_num = 1,
                                diff_line_num = 1,
                                formatted_diff_line_num = 1,
                                line_type = 'context'
                            },
                            {
                                content = 'line 2',
                                old_line_num = nil,
                                new_line_num = 2,
                                diff_line_num = 2,
                                formatted_diff_line_num = 2,
                                line_type = 'added'
                            },
                            {
                                content = 'line 3',
                                old_line_num = 3,
                                new_line_num = 3,
                                diff_line_num = 3,
                                formatted_diff_line_num = 3,
                                line_type = 'context'
                            }
                        },
                        old_start = 1,
                        old_count = 1,
                        new_start = 1,
                        new_count = 1,
                        header = '@@ -1,2 +1,3 @@',
                        context = nil
                    }
                },
                old_path = nil,
                new_path = nil,
                language = nil
            }
        },
    },
    {
        name = 'formatted_diff_line_num offset from new_line_num',
        cursor_placement = { winnr = 0, cursor = { 2, 0 } },
        buf_contents = { 'line1', 'line2', 'line3' },
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'line 1',
                                old_line_num = 1,
                                new_line_num = 1,
                                diff_line_num = 1,
                                formatted_diff_line_num = 8,
                                line_type = 'context'
                            },
                            {
                                content = 'line 2',
                                old_line_num = 2,
                                new_line_num = nil,
                                diff_line_num = 2,
                                formatted_diff_line_num = 9,
                                line_type = 'removed'
                            },
                            {
                                content = 'line 2',
                                old_line_num = nil,
                                new_line_num = 2,
                                diff_line_num = 3,
                                formatted_diff_line_num = 10,
                                line_type = 'added'
                            },
                            {
                                content = 'line 3',
                                old_line_num = 3,
                                new_line_num = 3,
                                diff_line_num = 4,
                                formatted_diff_line_num = 11,
                                line_type = 'context'
                            },
                        },
                        old_start = 1,
                        old_count = 3,
                        new_start = 1,
                        new_count = 3,
                        header = '@@ -1,3 +1,3 @@',
                        context = nil
                    }
                },
                old_path = nil,
                new_path = nil,
                language = nil
            }
        },
    },
    -- cursor matches a line in the second hunk, ensuring iteration does not stop at the first hunk.
    {
        name = 'cursor in second hunk',
        cursor_placement = { winnr = 0, cursor = { 8, 0 } },
        buf_contents = { 'l1', 'l2', 'l3', 'l4', 'l5', 'l6', 'l7', 'l8', 'l9' },
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'line 2 added',
                                old_line_num = nil,
                                new_line_num = 2,
                                diff_line_num = 2,
                                formatted_diff_line_num = 3,
                                line_type = 'added'
                            },
                        },
                        old_start = 1,
                        old_count = 1,
                        new_start = 1,
                        new_count = 2,
                        header = '@@ -1,1 +1,2 @@',
                        context = nil
                    },
                    {
                        lines = {
                            {
                                content = 'line 8 old',
                                old_line_num = 7,
                                new_line_num = nil,
                                diff_line_num = 8,
                                formatted_diff_line_num = 14,
                                line_type = 'removed'
                            },
                            {
                                content = 'line 8 new',
                                old_line_num = nil,
                                new_line_num = 8,
                                diff_line_num = 9,
                                formatted_diff_line_num = 15,
                                line_type = 'added'
                            },
                        },
                        old_start = 7,
                        old_count = 1,
                        new_start = 8,
                        new_count = 1,
                        header = '@@ -7,1 +8,1 @@',
                        context = nil
                    },
                },
                old_path = nil,
                new_path = nil,
                language = nil
            }
        },
    },
    -- when cursor_placement.filepath is set, only the matching diff entry should be used.
    {
        name = 'filepath specified and matches diff entry',
        cursor_placement = { winnr = 0, cursor = { 3, 0 }, filepath = 'foo.lua' },
        buf_contents = { 'line1', 'line2', 'line3' },
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'line 3 added',
                                old_line_num = nil,
                                new_line_num = 3,
                                diff_line_num = 3,
                                formatted_diff_line_num = 5,
                                line_type = 'added'
                            },
                        },
                        old_start = 2,
                        old_count = 1,
                        new_start = 2,
                        new_count = 2,
                        header = '@@ -2,1 +2,2 @@',
                        context = nil
                    },
                },
                old_path = 'foo.lua',
                new_path = 'foo.lua',
                language = nil
            }
        },
    },
    -- when multiple files are in the diff, filepath must select the correct one and not use
    -- a line from the first file even when new_line_num happens to match.
    {
        name = 'multiple files, filepath routes to second file',
        cursor_placement = { winnr = 0, cursor = { 2, 0 }, filepath = 'bar.lua' },
        buf_contents = { 'line1', 'line2' },
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'line 2 in foo',
                                old_line_num = nil,
                                new_line_num = 2,
                                diff_line_num = 2,
                                formatted_diff_line_num = 3,  -- should NOT be used
                                line_type = 'added'
                            },
                        },
                        old_start = 1,
                        old_count = 1,
                        new_start = 1,
                        new_count = 2,
                        header = '@@ -1,1 +1,2 @@',
                        context = nil
                    },
                },
                old_path = 'foo.lua',
                new_path = 'foo.lua',
                language = nil
            },
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'line 2 in bar old',
                                old_line_num = 1,
                                new_line_num = nil,
                                diff_line_num = 2,
                                formatted_diff_line_num = 19,
                                line_type = 'removed'
                            },
                            {
                                content = 'line 2 in bar new',
                                old_line_num = nil,
                                new_line_num = 2,
                                diff_line_num = 3,
                                formatted_diff_line_num = 20,  -- should be used
                                line_type = 'added'
                            },
                        },
                        old_start = 1,
                        old_count = 1,
                        new_start = 1,
                        new_count = 1,
                        header = '@@ -1,1 +1,1 @@',
                        context = nil
                    },
                },
                old_path = 'bar.lua',
                new_path = 'bar.lua',
                language = nil
            },
        },
    },
}

-- For a given cursor_placement and delta_diff_data_set, verifies that set_restview is called
-- with formatted_diff_line_num + 1 when the cursor row matches a line's new_line_num.
local cursor_placed_on_matching_line = [[(function()
    local cursor_placement = _G.fixture.cursor_placement
    local bufnr = _G.fixture.bufnr

    local called_with = nil
    M.set_restview = function(winnr, og_winline, target_row, target_col)
        called_with = { winnr = winnr, og_winline = og_winline, target_row = target_row, target_col = target_col }
    end

    M.place_cursor_delta_buffer_entry(bufnr, cursor_placement.winnr, cursor_placement, 1)

    if called_with == nil then
        return 'set_restview was not called'
    end

    -- find the expected formatted_diff_line_num + 1 for the matching cursor row
    local expected_row = nil
    local diff_data_set = vim.b[bufnr].delta_diff_data_set
    for _, diff_data in ipairs(diff_data_set) do
        if cursor_placement.filepath == nil or diff_data.new_path == cursor_placement.filepath then
            for _, hunk in ipairs(diff_data.hunks) do
                for _, line in ipairs(hunk.lines) do
                    if line.new_line_num == cursor_placement.cursor[1] then
                        expected_row = line.formatted_diff_line_num + 1
                        break
                    end
                end
                if expected_row then break end
            end
            break
        end
    end

    if expected_row == nil then
        return 'no matching line found in diff data for cursor row ' .. tostring(cursor_placement.cursor[1])
    end

    if called_with.target_row ~= expected_row then
        return string.format('expected target_row=%d, got %d', expected_row, called_with.target_row)
    end

    return true
end)()]]

T['place_cursor_delta_buffer_entry() properties'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                local bufnr = vim.api.nvim_create_buf(true, true)
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line1', 'line2', 'line3' })
                vim.api.nvim_set_current_buf(bufnr)
                _G.fixture.bufnr = bufnr
            ]])
        end
    },
})

for _, case in ipairs(place_cursor_delta_buffer_entry__property_cases) do
    T['place_cursor_delta_buffer_entry() properties']['cursor_placed_on_matching_line: ' .. case.name] = function()
        child.lua([[_G.fixture.cursor_placement = ...]], { case.cursor_placement })
        child.lua([[
            local bufnr = vim.api.nvim_create_buf(true, true)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, ...)
            vim.api.nvim_set_current_buf(bufnr)
            _G.fixture.bufnr = bufnr
        ]], { case.buf_contents })
        child.lua([[_G.fixture.delta_diff_data_set = ...]], { case.delta_diff_data_set })
        child.lua([[vim.b[_G.fixture.bufnr].delta_diff_data_set = _G.fixture.delta_diff_data_set]])
        local result = child.lua_get(cursor_placed_on_matching_line)
        eq(result, true)
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup_cursor_placement_tracking()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_delta_buffer_cursor_exit_strategy()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- set_restview()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup_hunk_navigation()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- jump_to_hunk()

return T
