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

local PlaceCursorDeltaBufferEntry = {}

--- @class place_cursor_delta_buffer_entry__property_cases
PlaceCursorDeltaBufferEntry.place_cursor_delta_buffer_entry__property_cases = {
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
                                formatted_diff_line_num = 3, -- should NOT be used
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
                                formatted_diff_line_num = 20, -- should be used
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
    -- cursor row doesn't match any new_line_num in the diff; fallback to first line of first hunk fires.
    {
        name = 'cursor row not in diff, falls back to first line of first hunk',
        cursor_placement = { winnr = 0, cursor = { 99, 0 } },
        buf_contents = { 'line1', 'line2', 'line3' },
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
                                diff_line_num = 1,
                                formatted_diff_line_num = 5,
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
                old_path = nil,
                new_path = nil,
                language = nil
            },
        },
    },
    -- filepath is set but matches no entry in the diff set; notify should fire and set_restview should not.
    {
        name = 'filepath does not match any diff entry',
        cursor_placement = { winnr = 0, cursor = { 1, 0 }, filepath = 'baz.lua' },
        buf_contents = { 'line1' },
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
                                diff_line_num = 0,
                                formatted_diff_line_num = 0,
                                line_type = 'context'
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
                old_path = 'foo.lua',
                new_path = 'foo.lua',
                language = nil
            },
        },
    },
}

PlaceCursorDeltaBufferEntry.properties = {}

-- For a given cursor_placement and delta_diff_data_set, verifies that set_restview is called
-- with formatted_diff_line_num + 1 when the cursor row matches a line's new_line_num.
PlaceCursorDeltaBufferEntry.properties.cursor_placed_on_matching_line = [[(function()
    local cursor_placement = _G.fixture.cursor_placement
    local bufnr = _G.fixture.bufnr

    local called_with = nil
    M.set_restview = function(winnr, og_winline, target_row, target_col)
        called_with = { winnr = winnr, og_winline = og_winline, target_row = target_row, target_col = target_col }
    end

    -- assume: filepath must be nil (fail-open) or match a file in the diff set
    if cursor_placement.filepath ~= nil then
        local filepath_in_diff = false
        for _, diff_data in ipairs(vim.b[bufnr].delta_diff_data_set) do
            if diff_data.new_path == cursor_placement.filepath then
                filepath_in_diff = true
                break
            end
        end
        if not filepath_in_diff then return true end
    end

    -- assume: cursor row must match a new_line_num in the applicable diff entry
    local cursor_row_in_diff = false
    for _, diff_data in ipairs(vim.b[bufnr].delta_diff_data_set) do
        if cursor_placement.filepath == nil or diff_data.new_path == cursor_placement.filepath then
            for _, hunk in ipairs(diff_data.hunks) do
                for _, line in ipairs(hunk.lines) do
                    if line.new_line_num == cursor_placement.cursor[1] then
                        cursor_row_in_diff = true
                        break
                    end
                end
                if cursor_row_in_diff then break end
            end
            break
        end
    end
    if not cursor_row_in_diff then return true end

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

-- when filepath is nil, it will still allow the user to try matching. It will only fail if filepath is non nil AND doesn't match.
PlaceCursorDeltaBufferEntry.properties.fails_open = [[(function()
    local cursor_placement = _G.fixture.cursor_placement
    local bufnr = _G.fixture.bufnr

    local notify_called = false
    vim.notify = function(args)
        notify_called = true
    end

    M.set_restview = function() end
    vim.api.nvim_win_set_cursor = function() end

    M.place_cursor_delta_buffer_entry(bufnr, cursor_placement.winnr, cursor_placement, 1)

    if notify_called == true then
        if _G.fixture.cursor_placement.filepath == nil then
            return false
        end
        local found = false
        for _, diff_data in ipairs(_G.fixture.delta_diff_data_set) do
            if diff_data.new_path == _G.fixture.cursor_placement.filepath then
                found = true
            end
        end
        if found then
            return false
        end
    end
    return true
end)()]]

T['place_cursor_delta_buffer_entry() properties'] = new_set()


for func_name, func in pairs(PlaceCursorDeltaBufferEntry.properties) do
    for _, case in ipairs(PlaceCursorDeltaBufferEntry.place_cursor_delta_buffer_entry__property_cases) do
        T['place_cursor_delta_buffer_entry() properties'][func_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.cursor_placement = ...]], { case.cursor_placement })
            child.lua([[
            local bufnr = vim.api.nvim_create_buf(true, true)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, ...)
            vim.api.nvim_set_current_buf(bufnr)
            _G.fixture.bufnr = bufnr
        ]], { case.buf_contents })
            child.lua([[_G.fixture.delta_diff_data_set = ...]], { case.delta_diff_data_set })
            child.lua([[vim.b[_G.fixture.bufnr].delta_diff_data_set = _G.fixture.delta_diff_data_set]])
            local result = child.lua_get(func)
            eq(result, true)
        end
    end
end

-- place_cursor_delta_buffer_entry() - example based tests

T['place_cursor_delta_buffer_entry() example'] = new_set()

T['place_cursor_delta_buffer_entry() example']['calls win_set_cursor manually with fallback values when filepath is nil or matched but cursor row cannot be matched'] = function()
    local case
    for _, c in ipairs(PlaceCursorDeltaBufferEntry.place_cursor_delta_buffer_entry__property_cases) do
        if c.name == 'cursor row not in diff, falls back to first line of first hunk' then
            case = c
            break
        end
    end

    child.lua([[_G.fixture.cursor_placement = ...]], { case.cursor_placement })
    child.lua([[
        local bufnr = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, ...)
        vim.api.nvim_set_current_buf(bufnr)
        _G.fixture.bufnr = bufnr
    ]], { case.buf_contents })
    child.lua([[_G.fixture.delta_diff_data_set = ...]], { case.delta_diff_data_set })
    child.lua([[vim.b[_G.fixture.bufnr].delta_diff_data_set = _G.fixture.delta_diff_data_set]])

    local result = child.lua_get([[(function()
        local cursor_placement = _G.fixture.cursor_placement
        local bufnr = _G.fixture.bufnr

        local win_set_cursor_called_with = nil
        vim.api.nvim_win_set_cursor = function(winnr, pos)
            win_set_cursor_called_with = { winnr = winnr, pos = pos }
        end
        M.set_restview = function() end

        M.place_cursor_delta_buffer_entry(bufnr, cursor_placement.winnr, cursor_placement, 1)

        if win_set_cursor_called_with == nil then
            return 'nvim_win_set_cursor was not called'
        end

        local diff_data_set = vim.b[bufnr].delta_diff_data_set
        local expected_row = diff_data_set[1].hunks[1].lines[1].formatted_diff_line_num + 1
        if win_set_cursor_called_with.pos[1] ~= expected_row then
            return string.format('expected pos[1]=%d, got %d', expected_row, win_set_cursor_called_with.pos[1])
        end
        if win_set_cursor_called_with.pos[2] ~= 0 then
            return string.format('expected pos[2]=0, got %d', win_set_cursor_called_with.pos[2])
        end

        return true
    end)()]])

    eq(result, true)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup_cursor_placement_tracking() - property based tests

-- fuzzable stuff is the delta_diff_data_set and the cursor position (nvim_win_get_cursor)
-- we can actually seriously fuzzy the cursors by hitting every single possible spot

local SetupCursorPlacementTracking = {}
SetupCursorPlacementTracking.get_cursors_set = function(buf_contents)
    local set = {}
    for i, v in ipairs(buf_contents) do
        for j = 1, #v, 1 do
            table.insert(set, { i, j - 1 })
        end
    end
    return set
end

--- @class setup_cursor_placement_tracking__property_cases
SetupCursorPlacementTracking.setup_cursor_placement_tracking__property_cases = {
    {
        name = 'no deleted lines',
        buf_contents = { 'line1', 'line2', 'line3' },
        get_cursors_set = SetupCursorPlacementTracking.get_cursors_set,
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'line1',
                                old_line_num = 1,
                                new_line_num = 1,
                                diff_line_num = 0,
                                formatted_diff_line_num = 0,
                                line_type = 'context'
                            },
                            {
                                content = 'line2',
                                old_line_num = nil,
                                new_line_num = 2,
                                diff_line_num = 1,
                                formatted_diff_line_num = 1,
                                line_type = 'added'
                            },
                            {
                                content = 'line3',
                                old_line_num = 3,
                                new_line_num = 3,
                                diff_line_num = 2,
                                formatted_diff_line_num = 2,
                                line_type = 'context'
                            }
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
    {
        -- row 1 (fdln=0) is removed → cursor_placement nil; rows 2,3 are added/context → non-nil
        name = 'has a removed line',
        buf_contents = { '-removed', '+added', 'context' },
        get_cursors_set = SetupCursorPlacementTracking.get_cursors_set,
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = '-removed',
                                old_line_num = 1,
                                new_line_num = nil,
                                diff_line_num = 0,
                                formatted_diff_line_num = 0,
                                line_type = 'removed'
                            },
                            {
                                content = '+added',
                                old_line_num = nil,
                                new_line_num = 1,
                                diff_line_num = 1,
                                formatted_diff_line_num = 1,
                                line_type = 'added'
                            },
                            {
                                content = 'context',
                                old_line_num = 2,
                                new_line_num = 2,
                                diff_line_num = 2,
                                formatted_diff_line_num = 2,
                                line_type = 'context'
                            }
                        },
                        old_start = 1,
                        old_count = 2,
                        new_start = 1,
                        new_count = 2,
                        header = '@@ -1,2 +1,2 @@',
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
        -- rows 1 and 4 are not covered by any diff line → cursor_placement nil; rows 2,3 → non-nil
        name = 'buffer rows outside diff coverage',
        buf_contents = { '~', 'line1', 'line2', '~' },
        get_cursors_set = SetupCursorPlacementTracking.get_cursors_set,
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'line1',
                                old_line_num = 1,
                                new_line_num = 1,
                                diff_line_num = 1,
                                formatted_diff_line_num = 1,
                                line_type = 'context'
                            },
                            {
                                content = 'line2',
                                old_line_num = nil,
                                new_line_num = 2,
                                diff_line_num = 2,
                                formatted_diff_line_num = 2,
                                line_type = 'added'
                            }
                        },
                        old_start = 1,
                        old_count = 1,
                        new_start = 1,
                        new_count = 2,
                        header = '@@ -1 +1,2 @@',
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
        -- hunk 1 covers rows 1,2; rows 3,4 are gap (not diff lines); hunk 2 covers rows 5,6
        name = 'multiple hunks with gap between',
        buf_contents = { 'h1l1', 'h1l2', '....', '....', 'h2l1', 'h2l2' },
        get_cursors_set = SetupCursorPlacementTracking.get_cursors_set,
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'h1l1',
                                old_line_num = 1,
                                new_line_num = 1,
                                diff_line_num = 0,
                                formatted_diff_line_num = 0,
                                line_type = 'context'
                            },
                            {
                                content = 'h1l2',
                                old_line_num = nil,
                                new_line_num = 2,
                                diff_line_num = 1,
                                formatted_diff_line_num = 1,
                                line_type = 'added'
                            }
                        },
                        old_start = 1,
                        old_count = 1,
                        new_start = 1,
                        new_count = 2,
                        header = '@@ -1 +1,2 @@',
                        context = nil
                    },
                    {
                        lines = {
                            {
                                content = 'h2l1',
                                old_line_num = 5,
                                new_line_num = nil,
                                diff_line_num = 4,
                                formatted_diff_line_num = 4,
                                line_type = 'removed'
                            },
                            {
                                content = 'h2l2',
                                old_line_num = nil,
                                new_line_num = 5,
                                diff_line_num = 5,
                                formatted_diff_line_num = 5,
                                line_type = 'added'
                            }
                        },
                        old_start = 5,
                        old_count = 1,
                        new_start = 5,
                        new_count = 1,
                        header = '@@ -5 +5 @@',
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
        -- new_path is set: cursor_placement.filepath should match it for all matched rows
        name = 'filepath populated from new_path',
        buf_contents = { 'line1', 'line2', 'line3' },
        get_cursors_set = SetupCursorPlacementTracking.get_cursors_set,
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'line1',
                                old_line_num = 1,
                                new_line_num = 1,
                                diff_line_num = 0,
                                formatted_diff_line_num = 0,
                                line_type = 'context'
                            },
                            {
                                content = 'line2',
                                old_line_num = nil,
                                new_line_num = 2,
                                diff_line_num = 1,
                                formatted_diff_line_num = 1,
                                line_type = 'added'
                            },
                            {
                                content = 'line3',
                                old_line_num = 3,
                                new_line_num = 3,
                                diff_line_num = 2,
                                formatted_diff_line_num = 2,
                                line_type = 'context'
                            }
                        },
                        old_start = 1,
                        old_count = 3,
                        new_start = 1,
                        new_count = 3,
                        header = '@@ -1,3 +1,3 @@',
                        context = nil
                    }
                },
                old_path = 'src/foo.lua',
                new_path = 'src/foo.lua',
                language = nil
            }
        },
    },
}

SetupCursorPlacementTracking.properties = {}
SetupCursorPlacementTracking.properties.cursor_populated_for_all_added_or_context_positions = [[(function()
    local cursors_set = _G.fixture.cursors_set
    local bufnr = _G.fixture.bufnr
    local winnr = _G.fixture.winnr
    M.setup_cursor_placement_tracking(bufnr, winnr)
    for _, cursor in ipairs(cursors_set) do
        vim.api.nvim_win_set_cursor(0, cursor)
        vim.api.nvim_exec_autocmds('CursorMoved', { buffer = bufnr })

        -- find which diff line (if any) this cursor row maps to
        local diff_line = nil
        local diff_filepath = nil
        for _, diff_data in ipairs(_G.fixture.delta_diff_data_set) do
            for _, hunk in ipairs(diff_data.hunks) do
                for _, line in ipairs(hunk.lines) do
                    if line.formatted_diff_line_num + 1 == cursor[1] then
                        diff_line = line
                        diff_filepath = diff_data.new_path
                    end
                end
            end
        end

        if diff_line == nil then
            -- not a diff line at all: cursor_placement should be nil
            if M.cursor_placement ~= nil then
                return false
            end
        elseif diff_line.new_line_num == nil then
            -- removed line: cursor_placement should be nil
            if M.cursor_placement ~= nil then
                return false
            end
        else
            -- added/context line: cursor_placement should be populated with correct values
            if M.cursor_placement == nil then
                return false
            end
            if M.cursor_placement.cursor[1] ~= diff_line.new_line_num then
                return false
            end
            if M.cursor_placement.cursor[2] ~= cursor[2] then
                return false
            end
            if M.cursor_placement.filepath ~= diff_filepath then
                return false
            end
        end
    end
    return true
end)()]]


T['setup_cursor_placement_tracking() properties'] = new_set()
for func_name, func in pairs(SetupCursorPlacementTracking.properties) do
    for _, case in ipairs(SetupCursorPlacementTracking.setup_cursor_placement_tracking__property_cases) do
        T['setup_cursor_placement_tracking() properties'][func_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.cursors_set = ...]], { case.get_cursors_set(case.buf_contents) })
            child.lua([[
            local bufnr = vim.api.nvim_create_buf(true, true)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, ...)
            vim.api.nvim_set_current_buf(bufnr)
            _G.fixture.bufnr = bufnr
            _G.fixture.winnr = vim.api.nvim_get_current_win()
        ]], { case.buf_contents })
            child.lua([[_G.fixture.delta_diff_data_set = ...]], { case.delta_diff_data_set })
            child.lua([[vim.b[_G.fixture.bufnr].delta_diff_data_set = _G.fixture.delta_diff_data_set]])
            local result = child.lua_get(func)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_delta_buffer_cursor_exit_strategy() - property based tests

local GetDeltaBufferCursorExitStrategy = {}

GetDeltaBufferCursorExitStrategy.get_cursors_set = function(buf_contents)
    local set = {}
    for i, v in ipairs(buf_contents) do
        for j = 1, #v, 1 do
            table.insert(set, { i, j - 1 })
        end
    end
    return set
end

--- @class get_delta_buffer_cursor_exit_strategy__property_cases
GetDeltaBufferCursorExitStrategy.get_delta_buffer_cursor_exit_strategy__property_cases = {
    {
        -- alternative_bufnr is provided; all lines have new_line_num → property fires for all cursor spots
        name = 'with alternative_bufnr, no filepath',
        use_alternative_bufnr = true,
        buf_contents = { 'line1', 'line2', 'line3' },
        get_cursors_set = GetDeltaBufferCursorExitStrategy.get_cursors_set,
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'line1',
                                old_line_num = 1,
                                new_line_num = 1,
                                diff_line_num = 0,
                                formatted_diff_line_num = 0,
                                line_type = 'context'
                            },
                            {
                                content = 'line2',
                                old_line_num = nil,
                                new_line_num = 2,
                                diff_line_num = 1,
                                formatted_diff_line_num = 1,
                                line_type = 'added'
                            },
                            {
                                content = 'line3',
                                old_line_num = 3,
                                new_line_num = 3,
                                diff_line_num = 2,
                                formatted_diff_line_num = 2,
                                line_type = 'context'
                            }
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
    {
        -- filepath is set, no alternative_bufnr; vim.cmd is mocked so 'e filepath' succeeds
        name = 'with filepath, no alternative_bufnr',
        use_alternative_bufnr = false,
        buf_contents = { 'line1', 'line2', 'line3' },
        get_cursors_set = GetDeltaBufferCursorExitStrategy.get_cursors_set,
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'line1',
                                old_line_num = 1,
                                new_line_num = 1,
                                diff_line_num = 0,
                                formatted_diff_line_num = 0,
                                line_type = 'context'
                            },
                            {
                                content = 'line2',
                                old_line_num = nil,
                                new_line_num = 2,
                                diff_line_num = 1,
                                formatted_diff_line_num = 1,
                                line_type = 'added'
                            },
                            {
                                content = 'line3',
                                old_line_num = 3,
                                new_line_num = 3,
                                diff_line_num = 2,
                                formatted_diff_line_num = 2,
                                line_type = 'context'
                            }
                        },
                        old_start = 1,
                        old_count = 3,
                        new_start = 1,
                        new_count = 3,
                        header = '@@ -1,3 +1,3 @@',
                        context = nil
                    }
                },
                old_path = 'src/foo.lua',
                new_path = 'src/foo.lua',
                language = nil
            }
        },
    },
    {
        -- both filepath and alternative_bufnr provided; alternative_bufnr takes precedence in view.lua
        name = 'with both filepath and alternative_bufnr',
        use_alternative_bufnr = true,
        buf_contents = { 'line1', 'line2' },
        get_cursors_set = GetDeltaBufferCursorExitStrategy.get_cursors_set,
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = 'line1',
                                old_line_num = 1,
                                new_line_num = 1,
                                diff_line_num = 0,
                                formatted_diff_line_num = 0,
                                line_type = 'context'
                            },
                            {
                                content = 'line2',
                                old_line_num = nil,
                                new_line_num = 2,
                                diff_line_num = 1,
                                formatted_diff_line_num = 1,
                                line_type = 'added'
                            }
                        },
                        old_start = 1,
                        old_count = 1,
                        new_start = 1,
                        new_count = 2,
                        header = '@@ -1 +1,2 @@',
                        context = nil
                    }
                },
                old_path = 'src/bar.lua',
                new_path = 'src/bar.lua',
                language = nil
            }
        },
    },
    {
        -- mix of removed and added lines with alternative_bufnr;
        -- removed line row → cursor_placement nil → property vacuous;
        -- added/context rows → property fires and should return true
        name = 'has removed line, with alternative_bufnr',
        use_alternative_bufnr = true,
        buf_contents = { '-removed', '+added', 'context' },
        get_cursors_set = GetDeltaBufferCursorExitStrategy.get_cursors_set,
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            {
                                content = '-removed',
                                old_line_num = 1,
                                new_line_num = nil,
                                diff_line_num = 0,
                                formatted_diff_line_num = 0,
                                line_type = 'removed'
                            },
                            {
                                content = '+added',
                                old_line_num = nil,
                                new_line_num = 1,
                                diff_line_num = 1,
                                formatted_diff_line_num = 1,
                                line_type = 'added'
                            },
                            {
                                content = 'context',
                                old_line_num = 2,
                                new_line_num = 2,
                                diff_line_num = 2,
                                formatted_diff_line_num = 2,
                                line_type = 'context'
                            }
                        },
                        old_start = 1,
                        old_count = 2,
                        new_start = 1,
                        new_count = 2,
                        header = '@@ -1,2 +1,2 @@',
                        context = nil
                    }
                },
                old_path = nil,
                new_path = nil,
                language = nil
            }
        },
    },
}

GetDeltaBufferCursorExitStrategy.properties = {}
GetDeltaBufferCursorExitStrategy.properties.strategy_returns_true_when_cursor_placed_and_navigation_possible =
[[(function()
    local cursors_set = _G.fixture.cursors_set
    local bufnr = _G.fixture.bufnr
    local winnr = _G.fixture.winnr
    local alternative_bufnr = _G.fixture.alternative_bufnr
    local delta_diff_data_set = _G.fixture.delta_diff_data_set

    -- setup_cursor_placement_tracking is tested separately; mock it so we control cursor_placement directly
    M.setup_cursor_placement_tracking = function() end
    M.set_restview = function() end
    vim.fn.winline = function() return 1 end
    -- mock vim.cmd so 'e filepath' doesn't attempt to open a real file
    local orig_cmd = vim.cmd
    vim.cmd = function() end

    local strategy = M.get_delta_buffer_cursor_exit_strategy(bufnr, winnr, alternative_bufnr)

    for _, cursor in ipairs(cursors_set) do
        -- mirror view.lua's row_lookup logic to determine what cursor_placement should be
        local diff_line = nil
        local diff_filepath = nil
        for _, diff_data in ipairs(delta_diff_data_set) do
            for _, hunk in ipairs(diff_data.hunks) do
                for _, line in ipairs(hunk.lines) do
                    if line.formatted_diff_line_num + 1 == cursor[1] then
                        diff_line = line
                        diff_filepath = diff_data.new_path
                    end
                end
            end
        end

        if diff_line ~= nil and diff_line.new_line_num ~= nil then
            M.cursor_placement = {
                winnr = winnr,
                cursor = { diff_line.new_line_num, cursor[2] },
                filepath = diff_filepath,
            }
        else
            M.cursor_placement = nil
        end

        -- save before strategy() clears it
        local cp = M.cursor_placement
        local result = strategy()

        -- property: strategy returns true when cursor is placed and navigation is possible
        if cp ~= nil and (alternative_bufnr ~= nil or cp.filepath ~= nil) then
            if result ~= true then
                vim.cmd = orig_cmd
                return false
            end
        end
    end

    vim.cmd = orig_cmd
    return true
end)()]]

T['get_delta_buffer_cursor_exit_strategy() properties'] = new_set()
for func_name, func in pairs(GetDeltaBufferCursorExitStrategy.properties) do
    for _, case in ipairs(GetDeltaBufferCursorExitStrategy.get_delta_buffer_cursor_exit_strategy__property_cases) do
        T['get_delta_buffer_cursor_exit_strategy() properties'][func_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.cursors_set = ...]], { case.get_cursors_set(case.buf_contents) })
            child.lua([[
                local bufnr = vim.api.nvim_create_buf(true, true)
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, ...)
                vim.api.nvim_set_current_buf(bufnr)
                _G.fixture.bufnr = bufnr
                _G.fixture.winnr = vim.api.nvim_get_current_win()
            ]], { case.buf_contents })
            child.lua([[_G.fixture.delta_diff_data_set = ...]], { case.delta_diff_data_set })
            child.lua([[vim.b[_G.fixture.bufnr].delta_diff_data_set = _G.fixture.delta_diff_data_set]])
            if case.use_alternative_bufnr then
                child.lua([[_G.fixture.alternative_bufnr = vim.api.nvim_create_buf(true, true)]])
            else
                child.lua([[_G.fixture.alternative_bufnr = nil]])
            end
            local result = child.lua_get(func)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- set_restview() - property based tests

local SetRestview = {}

SetRestview.get_inputs = function(buf_contents)
    local set = {}
    -- starting at 0 and ending 1 over for edge cases
    for winline = -1, #buf_contents + 1, 1 do
        for row, line in ipairs(buf_contents) do
            for col = -1, #line + 1, 1 do
                table.insert(set, { target_row = row - 1, target_col = col, og_winline = winline })
            end
        end
    end
    table.insert(set, { target_row = 9999, target_col = 9999, og_winline = 9999 })
    table.insert(set, { target_row = -9999, target_col = -9999, og_winline = -9999 })
    return set
end

--- @class set_restview__property_cases
SetRestview.set_restview__property_cases = {
    {
        name = 'short buffer',
        buf_contents = { 'line1', 'line2', 'line3' },
        get_inputs = SetRestview.get_inputs
    },
    {
        name = 'longer buffer with varied line lengths',
        buf_contents = {
            'short',
            'a longer line here for variety',
            'x',
            'another moderately long line of content',
            'tiny',
            'medium length content here',
            'ab',
            'the longest line with many more characters included here for wrapping',
        },
        get_inputs = SetRestview.get_inputs
    },
}

SetRestview.properties = {}

-- Note that the "last row bug" documented in the comments of the function is not being reflected here
-- this may be due to different rendering with mini.test vs real terminal rendering.
-- who knows, I can't even RCA that bug. but this test will pass regardless of that bug
SetRestview.properties.winline_matches_og_winline_after_set_restview = [[(function()
    local inputs = _G.fixture.inputs
    local bufnr = _G.fixture.bufnr
    local winnr = _G.fixture.winnr

    for _, input in ipairs(inputs) do
        local target_row = input.target_row
        local target_col = input.target_col
        local og_winline = input.og_winline

        -- assume: target_row within buffer bounds
        local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
        if target_row < 1 or target_row > buf_line_count then goto continue end

        -- assume: target_col non-negative
        if target_col < 0 then goto continue end

        -- assume: og_winline within [1, window height]
        local win_height = vim.api.nvim_win_get_height(winnr)
        if og_winline < 1 or og_winline > win_height then goto continue end

        -- assume: enough rows above target_row to scroll back og_winline-1 screen lines
        -- (without wrapping, each buffer row is 1 screen line, so target_row >= og_winline is required)
        if og_winline > target_row then goto continue end

        M.set_restview(winnr, og_winline, target_row, target_col)

        local actual_winline = vim.api.nvim_win_call(winnr, function()
            return vim.fn.winline()
        end)

        if actual_winline ~= og_winline then
            return false
        end

        ::continue::
    end

    return true
end)()]]

T['set_restview() properties'] = new_set()
for func_name, func in pairs(SetRestview.properties) do
    for _, case in ipairs(SetRestview.set_restview__property_cases) do
        T['set_restview() properties'][func_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.inputs = ...]], { case.get_inputs(case.buf_contents) })
            child.lua([[
                local bufnr = vim.api.nvim_create_buf(true, true)
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, ...)
                vim.api.nvim_set_current_buf(bufnr)
                _G.fixture.bufnr = bufnr
                _G.fixture.winnr = vim.api.nvim_get_current_win()
            ]], { case.buf_contents })
            local result = child.lua_get(func)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup_hunk_navigation() - example based tests

T['setup_hunk_navigation()'] = new_set()

T['setup_hunk_navigation()']['binds config.options.keyconfig.next_hunk to jump_to_hunk'] = function()
    child.lua([[
        local bufnr = vim.api.nvim_create_buf(true, true)
        _G.fixture.bufnr = bufnr
        _G.fixture.keymap_set_args = {}

        M.jump_to_hunk = function(bufnr, forward)
            _G.fixture.jump_to_hunk_called = true
            _G.fixture.jump_to_hunk_called_with = {bufnr = bufnr, forward = forward}
        end
        vim.keymap.set = function(modes, lhs, rhs, opts)
            _G.fixture.keymap_set_args[lhs] = { modes = modes, lhs = lhs, rhs = rhs, opts = opts }
        end
        M.setup_hunk_navigation(bufnr)
        -- run the code
    ]])

    local expected_binds = { '<Tab>', '<S-Tab>' }
    local expected_forward = { true, false }
    for idx, b in ipairs(expected_binds) do
        local bufnr = child.lua_get([[_G.fixture.bufnr]], {b})
        local modes = child.lua_get([[_G.fixture.keymap_set_args[...].modes]], {b})
        local lhs = child.lua_get([[_G.fixture.keymap_set_args[...].lhs]], {b})
        --local rhs = child.lua_get([[_G.fixture.keymap_set_args.rhs]])
        local buffer = child.lua_get([[_G.fixture.keymap_set_args[...].opts.buffer]], {b})
        local silent = child.lua_get([[_G.fixture.keymap_set_args[...].opts.silent]], {b})

        eq(modes, 'n')
        eq(lhs, b)
        eq(buffer, bufnr)
        eq(silent, true)

        child.lua([[_G.fixture.keymap_set_args[...].rhs()]], {b})
        local called = child.lua_get([[_G.fixture.jump_to_hunk_called]], {b})
        local called_with = child.lua_get([[_G.fixture.jump_to_hunk_called_with]], {b})
        eq(called, true)
        eq(called_with.bufnr, bufnr)
        eq(called_with.forward, expected_forward[idx])
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- jump_to_hunk() - property based tests

local JumpToHunk = {}

--- Fuzz cursor row (all buffer rows) and direction (forward + backward).
--- Column is always 0 since it does not affect hunk-navigation logic.
JumpToHunk.get_cursor_placements = function(buf_contents)
    local set = {}
    for i = 1, #buf_contents do
        table.insert(set, { cursor = { i, 0 }, forward = true })
        table.insert(set, { cursor = { i, 0 }, forward = false })
    end
    return set
end

--- @class jump_to_hunk__property_cases
JumpToHunk.jump_to_hunk__property_cases = {
    {
        -- Single file, one delta hunk spanning all 7 buffer rows, two parsed hunks.
        -- Because lines are indexed 1..7 matching buffer rows 1..7, the cursor-as-index
        -- assumption in jump_to_hunk holds perfectly here.
        -- Parsed hunk 1: added1 (new=2, old=nil).
        -- Parsed hunk 2: added2 + removed (new=5/nil, old=nil/4).
        name = 'single file, two parsed hunks',
        buf_contents = { 'ctx', 'added1', 'ctx', 'ctx', 'added2', 'removed', 'ctx' },
        get_cursor_placements = JumpToHunk.get_cursor_placements,
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            { content = 'ctx',     old_line_num = 1,   new_line_num = 1,   diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'context' },
                            { content = 'added1',  old_line_num = nil, new_line_num = 2,   diff_line_num = 1, formatted_diff_line_num = 1, line_type = 'added' },
                            { content = 'ctx',     old_line_num = 2,   new_line_num = 3,   diff_line_num = 2, formatted_diff_line_num = 2, line_type = 'context' },
                            { content = 'ctx',     old_line_num = 3,   new_line_num = 4,   diff_line_num = 3, formatted_diff_line_num = 3, line_type = 'context' },
                            { content = 'added2',  old_line_num = nil, new_line_num = 5,   diff_line_num = 4, formatted_diff_line_num = 4, line_type = 'added' },
                            { content = 'removed', old_line_num = 4,   new_line_num = nil, diff_line_num = 5, formatted_diff_line_num = 5, line_type = 'removed' },
                            { content = 'ctx',     old_line_num = 5,   new_line_num = 6,   diff_line_num = 6, formatted_diff_line_num = 6, line_type = 'context' },
                        },
                        old_start = 1,
                        old_count = 6,
                        new_start = 1,
                        new_count = 6,
                        header = '@@ -1,6 +1,6 @@',
                        context = nil
                    }
                },
                old_path = nil,
                new_path = nil,
                language = nil
            }
        },
        --- @type DiffData[]
        parsed_git_data = {
            {
                hunks = {
                    {
                        lines = {
                            { content = 'added1', old_line_num = nil, new_line_num = 2, diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'added' },
                        },
                        old_start = 2,
                        old_count = 0,
                        new_start = 2,
                        new_count = 1,
                        header = '@@ -2,0 +2,1 @@',
                        context = nil
                    },
                    {
                        lines = {
                            { content = 'added2',  old_line_num = nil, new_line_num = 5,   diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'added' },
                            { content = 'removed', old_line_num = 4,   new_line_num = nil, diff_line_num = 1, formatted_diff_line_num = 1, line_type = 'removed' },
                        },
                        old_start = 4,
                        old_count = 1,
                        new_start = 5,
                        new_count = 1,
                        header = '@@ -4,1 +5,1 @@',
                        context = nil
                    },
                },
                old_path = nil,
                new_path = nil,
                language = nil
            }
        },
    },
    {
        -- Single file, one delta hunk, one parsed hunk (contiguous added block).
        -- added1 and added2 are adjacent so parsed_git_data merges them into one hunk.
        -- From any cursor at or past the hunk start, forward always cycles back to row 2.
        name = 'single file, contiguous added block (one parsed hunk)',
        buf_contents = { 'ctx', 'added1', 'added2', 'ctx', 'ctx' },
        get_cursor_placements = JumpToHunk.get_cursor_placements,
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            { content = 'ctx',    old_line_num = 1,   new_line_num = 1, diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'context' },
                            { content = 'added1', old_line_num = nil, new_line_num = 2, diff_line_num = 1, formatted_diff_line_num = 1, line_type = 'added' },
                            { content = 'added2', old_line_num = nil, new_line_num = 3, diff_line_num = 2, formatted_diff_line_num = 2, line_type = 'added' },
                            { content = 'ctx',    old_line_num = 2,   new_line_num = 4, diff_line_num = 3, formatted_diff_line_num = 3, line_type = 'context' },
                            { content = 'ctx',    old_line_num = 3,   new_line_num = 5, diff_line_num = 4, formatted_diff_line_num = 4, line_type = 'context' },
                        },
                        old_start = 1,
                        old_count = 3,
                        new_start = 1,
                        new_count = 5,
                        header = '@@ -1,3 +1,5 @@',
                        context = nil
                    }
                },
                old_path = nil,
                new_path = nil,
                language = nil
            }
        },
        --- @type DiffData[]
        parsed_git_data = {
            {
                hunks = {
                    {
                        lines = {
                            { content = 'added1', old_line_num = nil, new_line_num = 2, diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'added' },
                            { content = 'added2', old_line_num = nil, new_line_num = 3, diff_line_num = 1, formatted_diff_line_num = 1, line_type = 'added' },
                        },
                        old_start = 2,
                        old_count = 0,
                        new_start = 2,
                        new_count = 2,
                        header = '@@ -2,0 +2,2 @@',
                        context = nil
                    },
                },
                old_path = nil,
                new_path = nil,
                language = nil
            }
        },
    },
    {
        -- Single file, removed lines only.
        -- The parsed hunk starts with a removed line (new_line_num=nil, old_line_num=2).
        -- Exercises the old_line_num matching branch of the algorithm.
        name = 'single file, removed lines only',
        buf_contents = { 'ctx', 'removed1', 'removed2', 'ctx' },
        get_cursor_placements = JumpToHunk.get_cursor_placements,
        --- @type DiffData[]
        delta_diff_data_set = {
            {
                hunks = {
                    {
                        lines = {
                            { content = 'ctx',      old_line_num = 1, new_line_num = 1,   diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'context' },
                            { content = 'removed1', old_line_num = 2, new_line_num = nil, diff_line_num = 1, formatted_diff_line_num = 1, line_type = 'removed' },
                            { content = 'removed2', old_line_num = 3, new_line_num = nil, diff_line_num = 2, formatted_diff_line_num = 2, line_type = 'removed' },
                            { content = 'ctx',      old_line_num = 4, new_line_num = 2,   diff_line_num = 3, formatted_diff_line_num = 3, line_type = 'context' },
                        },
                        old_start = 1,
                        old_count = 4,
                        new_start = 1,
                        new_count = 2,
                        header = '@@ -1,4 +1,2 @@',
                        context = nil
                    }
                },
                old_path = nil,
                new_path = nil,
                language = nil
            }
        },
        --- @type DiffData[]
        parsed_git_data = {
            {
                hunks = {
                    {
                        lines = {
                            { content = 'removed1', old_line_num = 2, new_line_num = nil, diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'removed' },
                            { content = 'removed2', old_line_num = 3, new_line_num = nil, diff_line_num = 1, formatted_diff_line_num = 1, line_type = 'removed' },
                        },
                        old_start = 2,
                        old_count = 2,
                        new_start = 2,
                        new_count = 0,
                        header = '@@ -2,2 +2,0 @@',
                        context = nil
                    },
                },
                old_path = nil,
                new_path = nil,
                language = nil
            }
        },
    },
    -- TODO; currently, this function doesn't work well when delta_diff_data_set has multiple hunks. Due to the way Delta.text_diff works, with producing 1 hunk, this is functionally not a bug, but when we develop for Delta.git_diff, this will most likely bug out. Then, we should root cause the bug and figure it out, and uncomment this test
    -- {
    --     -- Two files, each with a 3-line hunk.
    --     -- jump_to_hunk uses cursor[1] as an index into each hunk's lines[] array directly.
    --     -- File2's hunk has only 3 elements (indices 1..3), but cursors at rows 4..6 produce
    --     -- line_start=5..7 — past the end — so file2's loop body never executes.
    --     -- Consequence: forward navigation from any row in file2 always cycles back to file1's
    --     -- hunk start (row 2). This case documents that cross-file jump behavior.
    --     name = 'two files (cross-file cycling from file2 rows)',
    --     buf_contents = { 'f1_ctx', 'f1_added', 'f1_ctx', 'f2_ctx', 'f2_added', 'f2_ctx' },
    --     get_cursor_placements = JumpToHunk.get_cursor_placements,
    --     --- @type DiffData[]
    --     delta_diff_data_set = {
    --         {
    --             hunks = {
    --                 {
    --                     lines = {
    --                         { content = 'f1_ctx',   old_line_num = 1,   new_line_num = 1, diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'context' },
    --                         { content = 'f1_added', old_line_num = nil, new_line_num = 2, diff_line_num = 1, formatted_diff_line_num = 1, line_type = 'added' },
    --                         { content = 'f1_ctx',   old_line_num = 2,   new_line_num = 3, diff_line_num = 2, formatted_diff_line_num = 2, line_type = 'context' },
    --                     },
    --                     old_start = 1, old_count = 2, new_start = 1, new_count = 3,
    --                     header = '@@ -1,2 +1,3 @@', context = nil
    --                 }
    --             },
    --             old_path = 'file1.lua', new_path = 'file1.lua', language = nil
    --         },
    --         {
    --             hunks = {
    --                 {
    --                     lines = {
    --                         { content = 'f2_ctx',   old_line_num = 1,   new_line_num = 1, diff_line_num = 0, formatted_diff_line_num = 3, line_type = 'context' },
    --                         { content = 'f2_added', old_line_num = nil, new_line_num = 2, diff_line_num = 1, formatted_diff_line_num = 4, line_type = 'added' },
    --                         { content = 'f2_ctx',   old_line_num = 2,   new_line_num = 3, diff_line_num = 2, formatted_diff_line_num = 5, line_type = 'context' },
    --                     },
    --                     old_start = 1, old_count = 2, new_start = 1, new_count = 3,
    --                     header = '@@ -1,2 +1,3 @@', context = nil
    --                 }
    --             },
    --             old_path = 'file2.lua', new_path = 'file2.lua', language = nil
    --         },
    --     },
    --     --- @type DiffData[]
    --     parsed_git_data = {
    --         {
    --             hunks = {
    --                 {
    --                     lines = {
    --                         { content = 'f1_added', old_line_num = nil, new_line_num = 2, diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'added' },
    --                     },
    --                     old_start = 2, old_count = 0, new_start = 2, new_count = 1,
    --                     header = '@@ -2,0 +2,1 @@', context = nil
    --                 },
    --             },
    --             old_path = 'file1.lua', new_path = 'file1.lua', language = nil
    --         },
    --         {
    --             hunks = {
    --                 {
    --                     lines = {
    --                         { content = 'f2_added', old_line_num = nil, new_line_num = 2, diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'added' },
    --                     },
    --                     old_start = 2, old_count = 0, new_start = 2, new_count = 1,
    --                     header = '@@ -2,0 +2,1 @@', context = nil
    --                 },
    --             },
    --             old_path = 'file2.lua', new_path = 'file2.lua', language = nil
    --         },
    --     },
    -- },
}

JumpToHunk.properties = {}

JumpToHunk.properties.cursor_lands_on_valid_parsed_hunk_start = [[(function()
    local cursor_placements = _G.fixture.cursor_placements
    local bufnr = _G.fixture.bufnr
    local winnr = _G.fixture.winnr
    local delta_diff_data_set = vim.b[bufnr].delta_diff_data_set
    local parsed_git_data = vim.b[bufnr].parsed_git_data

    -- build the set of all valid hunk-start rows:
    -- a row is valid if it corresponds to a delta_diff_data_set line whose
    -- (new_line_num, old_line_num) matches the first line of some parsed_git_data hunk
    local hunk_start_rows = {}
    for di, diff_data in ipairs(delta_diff_data_set) do
        for _, hunk in ipairs(diff_data.hunks) do
            for _, line in ipairs(hunk.lines) do
                for _, pg_hunk in ipairs(parsed_git_data[di].hunks) do
                    local pf = pg_hunk.lines[1]
                    if pf.new_line_num == line.new_line_num and
                       pf.old_line_num == line.old_line_num then
                        hunk_start_rows[line.formatted_diff_line_num + 1] = true
                    end
                end
            end
        end
    end

    local current_cursor = nil
    M.get_cursor_placement_current_buffer = function()
        return { winnr = winnr, cursor = current_cursor }
    end

    -- mock side-effectful calls that are not under test
    local orig_nvim_echo = vim.api.nvim_echo
    local orig_defer_fn = vim.defer_fn
    vim.api.nvim_echo = function() end
    vim.defer_fn = function() end

    local result = true
    for _, placement in ipairs(cursor_placements) do
        current_cursor = placement.cursor
        vim.api.nvim_win_set_cursor(winnr, placement.cursor)
        M.jump_to_hunk(bufnr, placement.forward)
        local new_row = vim.api.nvim_win_get_cursor(winnr)[1]
        if not hunk_start_rows[new_row] then
            result = false
            break
        end
    end

    vim.api.nvim_echo = orig_nvim_echo
    vim.defer_fn = orig_defer_fn
    return result
end)()]]

T['jump_to_hunk() properties'] = new_set()
for func_name, func in pairs(JumpToHunk.properties) do
    for _, case in ipairs(JumpToHunk.jump_to_hunk__property_cases) do
        T['jump_to_hunk() properties'][func_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.cursor_placements = ...]], { case.get_cursor_placements(case.buf_contents) })
            child.lua([[
                local bufnr = vim.api.nvim_create_buf(true, true)
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, ...)
                vim.api.nvim_set_current_buf(bufnr)
                _G.fixture.bufnr = bufnr
                _G.fixture.winnr = vim.api.nvim_get_current_win()
            ]], { case.buf_contents })
            child.lua([[vim.b[_G.fixture.bufnr].delta_diff_data_set = ...]], { case.delta_diff_data_set })
            child.lua([[vim.b[_G.fixture.bufnr].parsed_git_data = ...]], { case.parsed_git_data })
            local result = child.lua_get(func)
            eq(result, true)
        end
    end
end

return T
