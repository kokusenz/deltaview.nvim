local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- utility

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
            child.lua([[M = require('deltaview.utils')]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- diff_data_sets_changed_lines_match() - property based tests

local DiffDataSetsChangedLinesMatch = {}

--- @class diff_data_sets_changed_lines_match__case
--- @field name string
--- @field a_lua string   Lua expression (as string) evaluating to a DiffData[]
--- @field b_lua string   Lua expression (as string) evaluating to a DiffData[]
--- @field expected boolean

-- Each case provides:
--   a_lua / b_lua  — Lua source for the two DiffData[] tables passed to the function
--   expected       — the boolean the function must return

--- Helper to build a single-hunk DiffData[] from a flat list of line descriptors.
--- Used inline inside a_lua / b_lua strings to keep cases concise.
local function make_diff_data(lines_desc)
    -- lines_desc: array of { content, old_line_num, new_line_num, line_type }
    local lines = {}
    for i, d in ipairs(lines_desc) do
        table.insert(lines, {
            content               = d.content,
            old_line_num          = d.old_line_num,
            new_line_num          = d.new_line_num,
            diff_line_num         = i - 1,
            formatted_diff_line_num = i - 1,
            line_type             = d.line_type,
        })
    end
    return { { hunks = { { lines = lines } }, old_path = 'a', new_path = 'a', language = nil } }
end

DiffDataSetsChangedLinesMatch.cases = {
    {
        -- Both tables are empty — no changed lines on either side.
        name = 'match: both tables have no changed lines',
        a = make_diff_data({}),
        b = make_diff_data({}),
        expected = true,
    },
    {
        -- Identical single removed + single added line on both sides.
        name = 'match: single removed and added line, identical on both sides',
        a = make_diff_data({
            { content = '-old', old_line_num = 2, new_line_num = nil, line_type = 'removed' },
            { content = '+new', old_line_num = nil, new_line_num = 2, line_type = 'added' },
        }),
        b = make_diff_data({
            { content = '-old', old_line_num = 2, new_line_num = nil, line_type = 'removed' },
            { content = '+new', old_line_num = nil, new_line_num = 2, line_type = 'added' },
        }),
        expected = true,
    },
    {
        -- Context lines are ignored; only changed lines matter.
        -- a has context lines surrounding the change, b has none — still matches.
        name = 'match: context lines are ignored, changed lines agree',
        a = { {
            hunks = { { lines = {
                { content = ' ctx',  old_line_num = 1, new_line_num = 1, diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'context' },
                { content = '-old',  old_line_num = 2, new_line_num = nil, diff_line_num = 1, formatted_diff_line_num = 1, line_type = 'removed' },
                { content = '+new',  old_line_num = nil, new_line_num = 2, diff_line_num = 2, formatted_diff_line_num = 2, line_type = 'added' },
                { content = ' ctx2', old_line_num = 3, new_line_num = 3, diff_line_num = 3, formatted_diff_line_num = 3, line_type = 'context' },
            } } },
            old_path = 'a', new_path = 'a', language = nil,
        } },
        b = make_diff_data({
            { content = '-old', old_line_num = 2, new_line_num = nil, line_type = 'removed' },
            { content = '+new', old_line_num = nil, new_line_num = 2, line_type = 'added' },
        }),
        expected = true,
    },
    {
        -- a has the change split across two hunks; b has it in one hunk.
        -- Structural difference (hunk count) must not affect the result.
        name = 'match: same changed lines split across different hunk structures',
        a = { {
            hunks = {
                { lines = {
                    { content = '-old', old_line_num = 2, new_line_num = nil, diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'removed' },
                } },
                { lines = {
                    { content = '+new', old_line_num = nil, new_line_num = 2, diff_line_num = 1, formatted_diff_line_num = 1, line_type = 'added' },
                } },
            },
            old_path = 'a', new_path = 'a', language = nil,
        } },
        b = make_diff_data({
            { content = '-old', old_line_num = 2, new_line_num = nil, line_type = 'removed' },
            { content = '+new', old_line_num = nil, new_line_num = 2, line_type = 'added' },
        }),
        expected = true,
    },
    {
        -- BUG scenario (view.lua:64): git diff and vim.text_diff disagree on line numbers.
        -- git diff says the change is at old=2/new=2; vim text diff says old=5/new=6.
        -- The validator must detect this and return false.
        name = 'mismatch: old_line_num and new_line_num differ between the two tables',
        a = make_diff_data({
            { content = '-old', old_line_num = 2, new_line_num = nil, line_type = 'removed' },
            { content = '+new', old_line_num = nil, new_line_num = 2, line_type = 'added' },
        }),
        b = make_diff_data({
            { content = '-old', old_line_num = 5, new_line_num = nil, line_type = 'removed' },
            { content = '+new', old_line_num = nil, new_line_num = 6, line_type = 'added' },
        }),
        expected = false,
    },
    {
        -- a has two changed lines, b has one — count mismatch must return false.
        name = 'mismatch: different number of changed lines',
        a = make_diff_data({
            { content = '-old',  old_line_num = 2, new_line_num = nil, line_type = 'removed' },
            { content = '-old2', old_line_num = 3, new_line_num = nil, line_type = 'removed' },
        }),
        b = make_diff_data({
            { content = '-old', old_line_num = 2, new_line_num = nil, line_type = 'removed' },
        }),
        expected = false,
    },
    {
        -- Line numbers agree but content differs — must return false.
        name = 'mismatch: content differs on a changed line',
        a = make_diff_data({
            { content = '-old_a', old_line_num = 1, new_line_num = nil, line_type = 'removed' },
        }),
        b = make_diff_data({
            { content = '-old_b', old_line_num = 1, new_line_num = nil, line_type = 'removed' },
        }),
        expected = false,
    },
    {
        -- Same line numbers and content, but line_type disagrees ('added' vs 'removed').
        name = 'mismatch: line_type differs',
        a = make_diff_data({
            { content = 'x', old_line_num = nil, new_line_num = 1, line_type = 'added' },
        }),
        b = make_diff_data({
            { content = 'x', old_line_num = 1, new_line_num = nil, line_type = 'removed' },
        }),
        expected = false,
    },
}

DiffDataSetsChangedLinesMatch.properties = {}

-- Single property: the function must return `expected` for every case.
DiffDataSetsChangedLinesMatch.properties.return_value_matches_expected = [[(function()
    local a        = _G.fixture.a
    local b        = _G.fixture.b
    local expected = _G.fixture.expected

    local result = M.diff_data_sets_changed_lines_match(a, b)
    return result == expected
end)()]]

T['diff_data_sets_changed_lines_match() properties'] = new_set()
for func_name, func in pairs(DiffDataSetsChangedLinesMatch.properties) do
    for _, case in ipairs(DiffDataSetsChangedLinesMatch.cases) do
        T['diff_data_sets_changed_lines_match() properties'][func_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.a        = ...]], { case.a })
            child.lua([[_G.fixture.b        = ...]], { case.b })
            child.lua([[_G.fixture.expected = ...]], { case.expected })
            local result = child.lua_get(func)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_separated_diff_data_set_into_hunks_wo_context() - property based tests

local GetSeparated = {}

--- Build a DiffData[] (one file, one hunk) from a list of line_type strings.
local function make_diff_data_from_types(line_types)
    local lines = {}
    local old_n, new_n = 1, 1
    for i, lt in ipairs(line_types) do
        local line = {
            content                 = lt .. '_' .. i,
            diff_line_num           = i - 1,
            formatted_diff_line_num = i - 1,
            line_type               = lt,
        }
        if lt == 'removed' then
            line.old_line_num = old_n; old_n = old_n + 1
            line.new_line_num = nil
        elseif lt == 'added' then
            line.old_line_num = nil
            line.new_line_num = new_n; new_n = new_n + 1
        else -- context
            line.old_line_num = old_n; old_n = old_n + 1
            line.new_line_num = new_n; new_n = new_n + 1
        end
        table.insert(lines, line)
    end
    return { {
        hunks    = { { lines = lines } },
        old_path = 'a', new_path = 'b', language = nil,
    } }
end

--- Returns every line-type sequence of length 0..4 as a DiffData[] input.
--- Produces 1+3+9+27+81 = 121 inputs, covering all-context, all-changed,
--- mixed, boundary-only context, and every intermediate pattern.
GetSeparated.get_exhaustive_single_hunk_inputs = function()
    local types  = { 'added', 'removed', 'context' }
    local inputs = { make_diff_data_from_types({}) }

    local function gen(seq)
        if #seq >= 4 then return end
        for _, t in ipairs(types) do
            local next_seq = {}
            for _, v in ipairs(seq) do table.insert(next_seq, v) end
            table.insert(next_seq, t)
            table.insert(inputs, make_diff_data_from_types(next_seq))
            gen(next_seq)
        end
    end
    gen({})

    return inputs
end

--- @class get_separated__case
--- @field name string
--- @field get_inputs fun(): DiffData[][]  -- list of DiffData[] inputs to iterate per property

GetSeparated.cases = {
    {
        -- Exhaustive: all permutations of line types up to length 4 in a single hunk.
        -- Covers all-context (all lines dropped), all-changed (passed through), mixed,
        -- context at boundaries, and consecutive-context runs that create multiple splits.
        name       = 'exhaustive: single-hunk line type sequences of length 0-4',
        get_inputs = GetSeparated.get_exhaustive_single_hunk_inputs,
    },
    {
        -- Two DiffData entries in one set; each has a hunk with mixed lines.
        -- Verifies that output[idx] is populated correctly for each file independently.
        name       = 'multi-file: two files with mixed line types',
        get_inputs = function()
            return { {
                {
                    hunks = { { lines = {
                        { content = 'ctx',  old_line_num = 1,   new_line_num = 1,   diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'context' },
                        { content = 'add',  old_line_num = nil, new_line_num = 2,   diff_line_num = 1, formatted_diff_line_num = 1, line_type = 'added'   },
                    } } },
                    old_path = 'a', new_path = 'b', language = nil,
                },
                {
                    hunks = { { lines = {
                        { content = 'rem',  old_line_num = 1,   new_line_num = nil, diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'removed' },
                        { content = 'ctx2', old_line_num = 2,   new_line_num = 1,   diff_line_num = 1, formatted_diff_line_num = 1, line_type = 'context' },
                    } } },
                    old_path = 'c', new_path = 'd', language = nil,
                },
            } }
        end,
    },
    {
        -- One file with two hunks; first hunk has a context gap that triggers a split,
        -- second hunk has no context (passes through).
        -- Verifies that each hunk in a file is processed independently.
        name       = 'multi-hunk: one file with two hunks, first has a context gap',
        get_inputs = function()
            return { { {
                hunks = {
                    { lines = {
                        { content = 'a1', old_line_num = nil, new_line_num = 1,   diff_line_num = 0, formatted_diff_line_num = 0, line_type = 'added'   },
                        { content = 'c1', old_line_num = 2,   new_line_num = 2,   diff_line_num = 1, formatted_diff_line_num = 1, line_type = 'context' },
                        { content = 'r1', old_line_num = 3,   new_line_num = nil, diff_line_num = 2, formatted_diff_line_num = 2, line_type = 'removed' },
                    } },
                    { lines = {
                        { content = 'r2', old_line_num = 10,  new_line_num = nil, diff_line_num = 3, formatted_diff_line_num = 3, line_type = 'removed' },
                        { content = 'a2', old_line_num = nil, new_line_num = 10,  diff_line_num = 4, formatted_diff_line_num = 4, line_type = 'added'   },
                    } },
                },
                old_path = 'x', new_path = 'y', language = nil,
            } } }
        end,
    },
    {
        -- Edge case: empty diff data set — no files, no hunks.
        name       = 'empty: empty diff data set',
        get_inputs = function() return { {} } end,
    },
}

GetSeparated.properties = {}

-- No line in any output hunk may have line_type == 'context'.
GetSeparated.properties.no_context_lines_in_output = [[(function()
    for _, input in ipairs(_G.fixture.inputs) do
        local output = M.get_separated_diff_data_set_into_hunks_wo_context(input)
        for _, diff_data in ipairs(output) do
            for _, hunk in ipairs(diff_data.hunks) do
                for _, line in ipairs(hunk.lines) do
                    if line.line_type == 'context' then return false end
                end
            end
        end
    end
    return true
end)()]]

-- Every added/removed line from the input appears in the output with the same
-- content, old_line_num, new_line_num, and line_type (order preserved).
GetSeparated.properties.changed_lines_preserved = [[(function()
    for _, input in ipairs(_G.fixture.inputs) do
        local output = M.get_separated_diff_data_set_into_hunks_wo_context(input)
        if not M.diff_data_sets_changed_lines_match(input, output) then
            return false
        end
    end
    return true
end)()]]

-- The output has exactly as many DiffData entries as the input.
GetSeparated.properties.output_length_equals_input_length = [[(function()
    for _, input in ipairs(_G.fixture.inputs) do
        local output = M.get_separated_diff_data_set_into_hunks_wo_context(input)
        if #output ~= #input then return false end
    end
    return true
end)()]]

-- Applying the function twice must be a no-op: f(f(x)) == f(x).
-- The output already has no context lines, so a second pass cannot split hunks further.
GetSeparated.properties.idempotent = [[(function()
    for _, input in ipairs(_G.fixture.inputs) do
        local output1 = M.get_separated_diff_data_set_into_hunks_wo_context(input)
        local output2 = M.get_separated_diff_data_set_into_hunks_wo_context(output1)

        if not M.diff_data_sets_changed_lines_match(output1, output2) then
            return false
        end

        -- Per-file hunk count must be identical; a second pass must not create new splits.
        if #output1 ~= #output2 then return false end
        for i = 1, #output1 do
            if #output1[i].hunks ~= #output2[i].hunks then return false end
        end
    end
    return true
end)()]]

T['get_separated_diff_data_set_into_hunks_wo_context() properties'] = new_set()
for func_name, func in pairs(GetSeparated.properties) do
    for _, case in ipairs(GetSeparated.cases) do
        local test_name = func_name .. ': ' .. case.name
        T['get_separated_diff_data_set_into_hunks_wo_context() properties'][test_name] = function()
            child.lua([[_G.fixture.inputs = ...]], { case.get_inputs() })
            local result = child.lua_get(func)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_untracked_files() - example based tests

T['get_untracked_files()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- Stub vim.system so we control what git returns
                vim.system = function(_cmd, _opts)
                    return {
                        wait = function()
                            return _G.fixture.system_result or
                                { code = 0, stdout = '', stderr = '' }
                        end
                    }
                end
                vim.notify = function() end
            ]])
        end,
    },
})

T['get_untracked_files()']['returns list of files from newline-separated output'] = function()
    child.lua([[
        _G.fixture.system_result = { code = 0, stdout = 'src/foo.lua\nsrc/bar.lua\nREADME.md\n', stderr = '' }
    ]])
    local result = child.lua_get([[M.get_untracked_files()]])
    eq(result, { 'src/foo.lua', 'src/bar.lua', 'README.md' })
end

T['get_untracked_files()']['returns empty table when git output is empty'] = function()
    child.lua([[
        _G.fixture.system_result = { code = 0, stdout = '', stderr = '' }
    ]])
    local result = child.lua_get([[M.get_untracked_files()]])
    eq(result, {})
end


T['get_untracked_files()']['code == 1 is not treated as a hard error (returns files)'] = function()
    -- code 1 means no matches for ls-files patterns, not a git failure
    child.lua([[
        _G.fixture.system_result = { code = 1, stdout = 'untracked.lua\n', stderr = '' }
    ]])
    local result = child.lua_get([[M.get_untracked_files()]])
    eq(result, { 'untracked.lua' })
end

T['get_untracked_files()']['strips blank trailing lines, does not include empty strings'] = function()
    child.lua([[
        _G.fixture.system_result = { code = 0, stdout = 'a.lua\n\nb.lua\n\n', stderr = '' }
    ]])
    local result = child.lua_get([[M.get_untracked_files()]])
    eq(result, { 'a.lua', 'b.lua' })
end

T['get_untracked_files()']['calls git with -C flag when git_root is provided'] = function()
    child.lua([[
        _G.fixture.captured_cmd = nil
        vim.system = function(cmd, _opts)
            _G.fixture.captured_cmd = cmd
            return { wait = function() return { code = 0, stdout = '', stderr = '' } end }
        end
    ]])
    child.lua([[M.get_untracked_files('/some/repo')]])
    local cmd = child.lua_get([[_G.fixture.captured_cmd]])
    eq(cmd[1], 'git')
    eq(cmd[2], '-C')
    eq(cmd[3], '/some/repo')
end

T['get_untracked_files()']['calls git without -C flag when git_root is not provided'] = function()
    child.lua([[
        _G.fixture.captured_cmd = nil
        vim.system = function(cmd, _opts)
            _G.fixture.captured_cmd = cmd
            return { wait = function() return { code = 0, stdout = '', stderr = '' } end }
        end
    ]])
    child.lua([[M.get_untracked_files()]])
    local cmd = child.lua_get([[_G.fixture.captured_cmd]])
    eq(cmd[1], 'git')
    eq(cmd[2], 'ls-files')
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_diffed_files() - example based tests

T['get_diffed_files()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                vim.system = function(_cmd, _opts)
                    return {
                        wait = function()
                            return _G.fixture.system_result or
                                { code = 0, stdout = '', stderr = '' }
                        end
                    }
                end
                vim.notify = function() end
            ]])
        end,
    },
})

T['get_diffed_files()']['returns list of files from newline-separated output'] = function()
    child.lua([[
        _G.fixture.system_result = { code = 0, stdout = 'lua/foo.lua\nlua/bar.lua\n', stderr = '' }
    ]])
    local result = child.lua_get([[M.get_diffed_files('HEAD')]])
    eq(result, { 'lua/foo.lua', 'lua/bar.lua' })
end

T['get_diffed_files()']['returns empty table when git output is empty'] = function()
    child.lua([[
        _G.fixture.system_result = { code = 0, stdout = '', stderr = '' }
    ]])
    local result = child.lua_get([[M.get_diffed_files('HEAD')]])
    eq(result, {})
end

T['get_diffed_files()']['returns empty table and notifies on git error'] = function()
    child.lua([[
        _G.fixture.system_result = { code = 128, stdout = '', stderr = '' }
        _G.fixture.notify_called = false
        vim.notify = function(_msg, _level)
            _G.fixture.notify_called = true
        end
    ]])
    local result = child.lua_get([[M.get_diffed_files('HEAD')]])
    local notify_called = child.lua_get([[_G.fixture.notify_called]])
    eq(result, {})
    eq(notify_called, true)
end

T['get_diffed_files()']['code == 1 is not a hard error (returns files normally)'] = function()
    child.lua([[
        _G.fixture.system_result = { code = 1, stdout = 'changed.lua\n', stderr = '' }
    ]])
    local result = child.lua_get([[M.get_diffed_files('HEAD')]])
    eq(result, { 'changed.lua' })
end


T['get_diffed_files()']['captures the ref passed to the git command'] = function()
    child.lua([[
        _G.fixture.captured_cmd = nil
        vim.system = function(cmd, _opts)
            _G.fixture.captured_cmd = cmd
            return { wait = function() return { code = 0, stdout = 'src/main.lua\n', stderr = '' } end }
        end
    ]])
    child.lua_get([[M.get_diffed_files('main~3')]])
    local cmd = child.lua_get([[_G.fixture.captured_cmd]])
    eq(cmd[2], 'diff')
    eq(cmd[3], 'main~3')
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_diffed_and_untracked_files() - property based tests

local GetDiffedAndUntracked = {}

--- @class get_diffed_and_untracked__case
--- @field name string
--- @field diffed string[]   list returned by M.get_diffed_files
--- @field untracked string[] list returned by M.get_untracked_files

GetDiffedAndUntracked.cases = {
    {
        -- No files in either list — result must be empty.
        name      = 'empty: both diffed and untracked are empty',
        diffed    = {},
        untracked = {},
    },
    {
        -- Only diffed files — all must map to true, nothing maps to false.
        name      = 'diffed-only: several tracked files, no untracked',
        diffed    = { 'lua/a.lua', 'lua/b.lua', 'README.md' },
        untracked = {},
    },
    {
        -- Only untracked files — all must map to false, nothing maps to true.
        name      = 'untracked-only: several untracked files, no diffed',
        diffed    = {},
        untracked = { 'new_a.lua', 'new_b.lua' },
    },
    {
        -- Disjoint sets — diffed files get true, untracked files get false, no collisions.
        name      = 'disjoint: diffed and untracked have no overlap',
        diffed    = { 'tracked.lua', 'tracked2.lua' },
        untracked = { 'new.lua', 'another_new.lua' },
    },
    {
        -- Full overlap — every untracked file is also diffed; they were staged mid-session.
        -- The diffed value (true) must win; the untracked entry must NOT overwrite it to false.
        name      = 'full overlap: all untracked files also appear in diffed',
        diffed    = { 'overlap.lua', 'also_overlap.lua' },
        untracked = { 'overlap.lua', 'also_overlap.lua' },
    },
    {
        -- Partial overlap — some files are in both lists, some only in one.
        name      = 'partial overlap: some files appear in both lists',
        diffed    = { 'shared.lua', 'only_diffed.lua' },
        untracked = { 'shared.lua', 'only_untracked.lua' },
    },
    {
        -- Single file, diffed only.
        name      = 'single diffed file',
        diffed    = { 'single.lua' },
        untracked = {},
    },
    {
        -- Single file, untracked only.
        name      = 'single untracked file',
        diffed    = {},
        untracked = { 'single.lua' },
    },
}

GetDiffedAndUntracked.properties = {}

-- Every file from get_diffed_files must appear in the result mapped to true.
GetDiffedAndUntracked.properties.diffed_files_map_to_true = [[(function()
    local diffed    = _G.fixture.diffed
    local result    = M.get_diffed_and_untracked_files('HEAD')
    for _, f in ipairs(diffed) do
        if result[f] ~= true then return false end
    end
    return true
end)()]]

-- Every file from get_untracked_files that is NOT in get_diffed_files must map to false.
GetDiffedAndUntracked.properties.untracked_only_files_map_to_false = [[(function()
    local diffed    = _G.fixture.diffed
    local untracked = _G.fixture.untracked

    -- build a fast lookup for diffed files
    local diffed_set = {}
    for _, f in ipairs(diffed) do diffed_set[f] = true end

    local result = M.get_diffed_and_untracked_files('HEAD')
    for _, f in ipairs(untracked) do
        if not diffed_set[f] then
            if result[f] ~= false then return false end
        end
    end
    return true
end)()]]

-- No key appears more than once (Lua tables are maps so this is guaranteed, but we
-- also verify that an overlap file keeps the true value and not false).
GetDiffedAndUntracked.properties.overlap_files_stay_true = [[(function()
    local diffed    = _G.fixture.diffed
    local untracked = _G.fixture.untracked

    local diffed_set = {}
    for _, f in ipairs(diffed) do diffed_set[f] = true end

    local result = M.get_diffed_and_untracked_files('HEAD')
    for _, f in ipairs(untracked) do
        if diffed_set[f] then
            -- file is in both lists; the diffed value (true) must win
            if result[f] ~= true then return false end
        end
    end
    return true
end)()]]

-- The total number of keys in the result equals the size of the union of both lists.
GetDiffedAndUntracked.properties.result_size_equals_union = [[(function()
    local diffed    = _G.fixture.diffed
    local untracked = _G.fixture.untracked

    local union = {}
    for _, f in ipairs(diffed)    do union[f] = true end
    for _, f in ipairs(untracked) do union[f] = true end

    local union_size = 0
    for _ in pairs(union) do union_size = union_size + 1 end

    local result = M.get_diffed_and_untracked_files('HEAD')
    local result_size = 0
    for _ in pairs(result) do result_size = result_size + 1 end

    return result_size == union_size
end)()]]

T['get_diffed_and_untracked_files() properties'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- Stub the two collaborators so we control their return values
                M.get_diffed_files    = function(_ref) return _G.fixture.diffed    end
                M.get_untracked_files = function()     return _G.fixture.untracked end
            ]])
        end,
    },
})

for func_name, func in pairs(GetDiffedAndUntracked.properties) do
    for _, case in ipairs(GetDiffedAndUntracked.cases) do
        local test_name = func_name .. ': ' .. case.name
        T['get_diffed_and_untracked_files() properties'][test_name] = function()
            child.lua([[_G.fixture.diffed    = ...]], { case.diffed })
            child.lua([[_G.fixture.untracked = ...]], { case.untracked })
            local result = child.lua_get(func)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_sorted_diffed_files() - example based tests

-- Helper shared across test cases: configure the child's stubs for a given scenario.
-- `files_map`    table<string, boolean>   returned by M.get_diffed_and_untracked_files
-- `dirstat_out`  string                   fake git dirstat output
-- `numstat_map`  table<string, string>    path -> numstat line e.g. "3\t1\tpath"

T['get_sorted_diffed_files()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                vim.notify = function() end

                -- Stubs are set per-test; provide safe no-op defaults here
                M.get_diffed_and_untracked_files = function(_ref)
                    return _G.fixture.files_map or {}
                end

                M.git_rel_to_abs = function(rel)
                    return '/repo/' .. rel
                end

                vim.system = function(cmd, _opts)
                    -- Distinguish the four vim.system call sites by command shape:
                    -- 1. dirstat:     {'git', 'diff', ref, '-X', '--dirstat=lines,0'}
                    -- 2. name-status: {'git', 'diff', '--name-status', ref}
                    -- 3. numstat (tracked):   {'git', 'diff', '--numstat', ref, '--', abs_path}
                    -- 4. numstat (untracked): {'git', 'diff', '--numstat', '--no-index', '--', '/dev/null', abs_path}
                    local stdout
                    if cmd[1] == 'git' and cmd[2] == 'diff' and cmd[4] == '-X' then
                        -- dirstat call
                        stdout = _G.fixture.dirstat_out or ''
                    elseif cmd[1] == 'git' and cmd[2] == 'diff' and cmd[3] == '--name-status' then
                        -- name-status call
                        stdout = _G.fixture.name_status_out or ''
                    elseif cmd[1] == 'git' and cmd[2] == 'diff' and cmd[3] == '--numstat' then
                        -- untracked: {'git','diff','--numstat','--no-index','--','/dev/null', abs_path}  -> cmd[7]
                        -- tracked:   {'git','diff','--numstat', ref,         '--', abs_path}            -> cmd[6]
                        local abs_path = (cmd[4] == '--no-index') and cmd[7] or cmd[6]
                        local numstat_map = _G.fixture.numstat_map or {}
                        stdout = numstat_map[abs_path] or '0\t0\t' .. abs_path .. '\n'
                    else
                        stdout = ''
                    end
                    local code = _G.fixture.system_code or 0
                    return { wait = function() return { code = code, stdout = stdout, stderr = '' } end }
                end
            ]])
        end,
    },
})

T['get_sorted_diffed_files()']['returns empty table when no files'] = function()
    child.lua([[_G.fixture.files_map   = {}]])
    child.lua([[_G.fixture.dirstat_out = '']])
    local result = child.lua_get([[M.get_sorted_diffed_files('HEAD')]])
    eq(result, {})
end

T['get_sorted_diffed_files()']['returns empty table and notifies on dirstat git error'] = function()
    child.lua([[
        _G.fixture.files_map   = { ['a.lua'] = true }
        _G.fixture.dirstat_out = ''
        _G.fixture.system_code = 128
        _G.fixture.notify_called = false
        vim.notify = function(_msg, _level) _G.fixture.notify_called = true end
    ]])
    local result = child.lua_get([[M.get_sorted_diffed_files('HEAD')]])
    local notify_called = child.lua_get([[_G.fixture.notify_called]])
    eq(result, {})
    eq(notify_called, true)
end

T['get_sorted_diffed_files()']['single tracked file returns correct name, added, removed, and status'] = function()
    child.lua([[
        _G.fixture.files_map      = { ['lua/foo.lua'] = true }
        _G.fixture.dirstat_out    = '  100.0% lua/\n'
        _G.fixture.name_status_out = 'M\tlua/foo.lua\n'
        _G.fixture.numstat_map    = { ['/repo/lua/foo.lua'] = '10\t3\tlua/foo.lua\n' }
    ]])
    local result = child.lua_get([[M.get_sorted_diffed_files('HEAD')]])
    eq(#result, 1)
    eq(result[1].name,    'lua/foo.lua')
    eq(result[1].added,   10)
    eq(result[1].removed, 3)
    eq(result[1].status,  'M')
end

T['get_sorted_diffed_files()']['files sorted by directory dirstat weight descending'] = function()
    -- lua/ has 70% weight, tests/ has 30%; files in lua/ must appear first
    child.lua([[
        _G.fixture.files_map = {
            ['tests/test_a.lua'] = true,
            ['lua/mod.lua']      = true,
        }
        _G.fixture.dirstat_out = '   70.0% lua/\n   30.0% tests/\n'
        _G.fixture.numstat_map = {
            ['/repo/tests/test_a.lua'] = '5\t5\ttests/test_a.lua\n',
            ['/repo/lua/mod.lua']      = '5\t5\tlua/mod.lua\n',
        }
    ]])
    local result = child.lua_get([[M.get_sorted_diffed_files('HEAD')]])
    eq(#result, 2)
    eq(result[1].name, 'lua/mod.lua')
    eq(result[2].name, 'tests/test_a.lua')
end

T['get_sorted_diffed_files()']['within same directory, sort by total line changes descending'] = function()
    -- Both files in lua/; file_b has more total changes so it should come first
    child.lua([[
        _G.fixture.files_map = {
            ['lua/file_a.lua'] = true,
            ['lua/file_b.lua'] = true,
        }
        _G.fixture.dirstat_out = '  100.0% lua/\n'
        _G.fixture.numstat_map = {
            ['/repo/lua/file_a.lua'] = '2\t1\tlua/file_a.lua\n',
            ['/repo/lua/file_b.lua'] = '8\t4\tlua/file_b.lua\n',
        }
    ]])
    local result = child.lua_get([[M.get_sorted_diffed_files('HEAD')]])
    eq(#result, 2)
    eq(result[1].name, 'lua/file_b.lua')
    eq(result[2].name, 'lua/file_a.lua')
end

T['get_sorted_diffed_files()']['alphabetical sort as final tiebreaker'] = function()
    -- Same directory, same change count; must sort by name ascending
    child.lua([[
        _G.fixture.files_map = {
            ['lua/zzz.lua'] = true,
            ['lua/aaa.lua'] = true,
        }
        _G.fixture.dirstat_out = '  100.0% lua/\n'
        _G.fixture.numstat_map = {
            ['/repo/lua/zzz.lua'] = '5\t5\tlua/zzz.lua\n',
            ['/repo/lua/aaa.lua'] = '5\t5\tlua/aaa.lua\n',
        }
    ]])
    local result = child.lua_get([[M.get_sorted_diffed_files('HEAD')]])
    eq(#result, 2)
    eq(result[1].name, 'lua/aaa.lua')
    eq(result[2].name, 'lua/zzz.lua')
end

T['get_sorted_diffed_files()']['single untracked file returns correct added count'] = function()
    child.lua([[
        _G.fixture.files_map   = { ['new_file.lua'] = false }
        _G.fixture.dirstat_out = ''
        _G.fixture.numstat_map = { ['/repo/new_file.lua'] = '7\t0\tnew_file.lua\n' }
    ]])
    local result = child.lua_get([[M.get_sorted_diffed_files('HEAD')]])
    eq(#result, 1)
    eq(result[1].name,    'new_file.lua')
    eq(result[1].added,   7)
    eq(result[1].removed, 0)
end

T['get_sorted_diffed_files()']['binary untracked file shows 0 added and 0 removed'] = function()
    child.lua([[
        _G.fixture.files_map   = { ['image.png'] = false }
        _G.fixture.dirstat_out = ''
        _G.fixture.numstat_map = { ['/repo/image.png'] = '-\t-\t{/dev/null => image.png}\n' }
    ]])
    local result = child.lua_get([[M.get_sorted_diffed_files('HEAD')]])
    eq(#result, 1)
    eq(result[1].name,    'image.png')
    eq(result[1].added,   0)
    eq(result[1].removed, 0)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- git_rel_to_abs() - example based tests

T['git_rel_to_abs()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                vim.notify = function() end
                -- Default: git rev-parse succeeds
                vim.system = function(_cmd, _opts)
                    return {
                        wait = function()
                            return _G.fixture.system_result or
                                { code = 0, stdout = '/home/user/repo\n', stderr = '' }
                        end
                    }
                end
            ]])
        end,
    },
})

T['git_rel_to_abs()']['returns absolute path by joining git root and rel_path'] = function()
    child.lua([[
        _G.fixture.system_result = { code = 0, stdout = '/home/user/myrepo\n', stderr = '' }
    ]])
    local result = child.lua_get([[M.git_rel_to_abs('lua/foo.lua')]])
    eq(result, '/home/user/myrepo/lua/foo.lua')
end

T['git_rel_to_abs()']['trims trailing newline from git root before joining'] = function()
    child.lua([[
        -- stdout has a trailing newline — must not appear in the result
        _G.fixture.system_result = { code = 0, stdout = '/repo/root\n', stderr = '' }
    ]])
    local result = child.lua_get([[M.git_rel_to_abs('src/main.lua')]])
    eq(result, '/repo/root/src/main.lua')
end

T['git_rel_to_abs()']['throws error when git rev-parse fails'] = function()
    child.lua([[
        _G.fixture.system_result = { code = 128, stdout = '', stderr = 'not a git repo' }
    ]])
    local ok = child.lua_get([[pcall(M.git_rel_to_abs, 'any.lua')]])
    eq(ok, false)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_filenames_from_sortedfiles() - property based tests

local GetFilenamesFromSortedfiles = {}

--- Builds a SortedFile[] from a flat list of {name, added, removed} descriptors.
local function make_sorted_files(descs)
    local result = {}
    for _, d in ipairs(descs) do
        table.insert(result, { name = d.name, added = d.added, removed = d.removed })
    end
    return result
end

--- @class get_filenames__case
--- @field name string
--- @field sorted_files SortedFile[]

GetFilenamesFromSortedfiles.cases = {
    {
        name         = 'empty list',
        sorted_files = make_sorted_files({}),
    },
    {
        name         = 'single file',
        sorted_files = make_sorted_files({ { name = 'lua/foo.lua', added = 3, removed = 1 } }),
    },
    {
        name         = 'multiple files',
        sorted_files = make_sorted_files({
            { name = 'lua/a.lua',    added = 10, removed = 2 },
            { name = 'lua/b.lua',    added = 5,  removed = 0 },
            { name = 'tests/c.lua',  added = 1,  removed = 1 },
        }),
    },
    {
        -- Files with duplicate names should still all appear in the output.
        name         = 'files with same name appear separately',
        sorted_files = make_sorted_files({
            { name = 'same.lua', added = 1, removed = 0 },
            { name = 'same.lua', added = 2, removed = 0 },
        }),
    },
    {
        -- added/removed fields are irrelevant to the extraction — only name matters.
        name         = 'zero added and removed fields do not affect output',
        sorted_files = make_sorted_files({
            { name = 'x.lua', added = 0, removed = 0 },
            { name = 'y.lua', added = 0, removed = 0 },
        }),
    },
}

GetFilenamesFromSortedfiles.properties = {}

-- Output length equals input length.
GetFilenamesFromSortedfiles.properties.output_length_equals_input = [[(function()
    local sorted_files = _G.fixture.sorted_files
    local result = M.get_filenames_from_sortedfiles(sorted_files)
    return #result == #sorted_files
end)()]]

-- Each output element is the .name field of the corresponding input element (order preserved).
GetFilenamesFromSortedfiles.properties.names_match_in_order = [[(function()
    local sorted_files = _G.fixture.sorted_files
    local result = M.get_filenames_from_sortedfiles(sorted_files)
    for i, sf in ipairs(sorted_files) do
        if result[i] ~= sf.name then return false end
    end
    return true
end)()]]

-- Every element in the output is a string.
GetFilenamesFromSortedfiles.properties.all_elements_are_strings = [[(function()
    local sorted_files = _G.fixture.sorted_files
    local result = M.get_filenames_from_sortedfiles(sorted_files)
    for _, v in ipairs(result) do
        if type(v) ~= 'string' then return false end
    end
    return true
end)()]]

T['get_filenames_from_sortedfiles() properties'] = new_set()
for func_name, func in pairs(GetFilenamesFromSortedfiles.properties) do
    for _, case in ipairs(GetFilenamesFromSortedfiles.cases) do
        local test_name = func_name .. ': ' .. case.name
        T['get_filenames_from_sortedfiles() properties'][test_name] = function()
            child.lua([[_G.fixture.sorted_files = ...]], { case.sorted_files })
            local result = child.lua_get(func)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- read_file_lines() - example based tests

T['read_file_lines()'] = new_set({
    hooks = {
        pre_case = function()
            -- Create a temp directory path for test files; clean up on each pre_case
            child.lua([[
                _G.fixture.tmpdir = vim.fn.tempname()
                vim.fn.mkdir(_G.fixture.tmpdir, 'p')
            ]])
        end,
    },
})

T['read_file_lines()']['returns array of lines from a multi-line file'] = function()
    child.lua([[
        local path = _G.fixture.tmpdir .. '/multi.txt'
        local f = io.open(path, 'w')
        f:write('line one\nline two\nline three\n')
        f:close()
        _G.fixture.path = path
    ]])
    local result = child.lua_get([[M.read_file_lines(_G.fixture.path)]])
    eq(result, { 'line one', 'line two', 'line three' })
end

T['read_file_lines()']['returns a single-element array for a one-line file'] = function()
    child.lua([[
        local path = _G.fixture.tmpdir .. '/single.txt'
        local f = io.open(path, 'w')
        f:write('only line\n')
        f:close()
        _G.fixture.path = path
    ]])
    local result = child.lua_get([[M.read_file_lines(_G.fixture.path)]])
    eq(result, { 'only line' })
end

T['read_file_lines()']['returns empty table for an empty file'] = function()
    child.lua([[
        local path = _G.fixture.tmpdir .. '/empty.txt'
        local f = io.open(path, 'w')
        f:write('')
        f:close()
        _G.fixture.path = path
    ]])
    local result = child.lua_get([[M.read_file_lines(_G.fixture.path)]])
    eq(result, {})
end

T['read_file_lines()']['returns nil for a non-existent file'] = function()
    local result = child.lua_get([[M.read_file_lines('/definitely/does/not/exist/file.txt')]])
    eq(result, vim.NIL)
end

T['read_file_lines()']['preserves content exactly including spaces and special chars'] = function()
    child.lua([[
        local path = _G.fixture.tmpdir .. '/special.txt'
        local f = io.open(path, 'w')
        f:write('  leading spaces\n\ttabbed\nwith symbols: @#$%\n')
        f:close()
        _G.fixture.path = path
    ]])
    local result = child.lua_get([[M.read_file_lines(_G.fixture.path)]])
    eq(result, { '  leading spaces', '\ttabbed', 'with symbols: @#$%' })
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- is_untracked_file() - property based tests

local IsUntrackedFile = {}

--- Returns a list of {path, untracked_rel_paths, git_root} inputs.
--- Each input represents one call to M.is_untracked_file(path).
--- @param case_data { git_root: string, paths: string[], untracked_rel: string[] }
--- @return table[]
IsUntrackedFile.get_inputs = function(case_data)
    local inputs = {}
    -- For every path under test, build an input that includes the full context
    for _, path in ipairs(case_data.paths) do
        table.insert(inputs, {
            path              = path,
            untracked_rel     = case_data.untracked_rel,
            git_root          = case_data.git_root,
        })
    end
    return inputs
end

--- @class is_untracked_file__case
--- @field name string
--- @field git_root string
--- @field paths string[]
--- @field untracked_rel string[]

IsUntrackedFile.cases = {
    {
        -- No untracked files at all — every path must return false.
        name          = 'no untracked files: all paths return false',
        git_root      = '/repo',
        paths         = { '/repo/lua/a.lua', '/repo/src/b.lua', '/repo/README.md' },
        untracked_rel = {},
    },
    {
        -- Every queried path is untracked — all must return true.
        name          = 'all paths are untracked: all return true',
        git_root      = '/repo',
        paths         = { '/repo/new.lua', '/repo/another.lua' },
        untracked_rel = { 'new.lua', 'another.lua' },
    },
    {
        -- Disjoint sets: queried paths are tracked; untracked list contains different files.
        name          = 'disjoint: queried paths are not in untracked list',
        git_root      = '/home/user/project',
        paths         = { '/home/user/project/tracked.lua' },
        untracked_rel = { 'other_new.lua', 'also_new.lua' },
    },
    {
        -- Mixed: some paths are untracked, some are not.
        name          = 'mixed: some paths are untracked, some are not',
        git_root      = '/workspace',
        paths         = {
            '/workspace/lua/tracked.lua',
            '/workspace/lua/untracked.lua',
            '/workspace/README.md',
        },
        untracked_rel = { 'lua/untracked.lua', 'new_file.lua' },
    },
    {
        -- Single untracked file, single queried path matching exactly.
        name          = 'single match: exactly one untracked file matches the queried path',
        git_root      = '/myrepo',
        paths         = { '/myrepo/src/foo.lua' },
        untracked_rel = { 'src/foo.lua' },
    },
}

IsUntrackedFile.properties = {}

-- A path whose absolute form is in the untracked list must return true.
IsUntrackedFile.properties.untracked_paths_return_true = [[(function()
    local inputs = _G.fixture.inputs

    -- build a set of absolute untracked paths for O(1) lookup
    local untracked_abs = {}
    if #inputs > 0 then
        local git_root = inputs[1].git_root
        for _, rel in ipairs(inputs[1].untracked_rel) do
            untracked_abs[git_root .. '/' .. rel] = true
        end
    end

    for _, input in ipairs(inputs) do
        if untracked_abs[input.path] then
            local result = M.is_untracked_file(input.path, input.git_root)
            if result ~= true then return false end
        end
    end
    return true
end)()]]

-- A path whose absolute form is NOT in the untracked list must return false.
IsUntrackedFile.properties.tracked_paths_return_false = [[(function()
    local inputs = _G.fixture.inputs

    local untracked_abs = {}
    if #inputs > 0 then
        local git_root = inputs[1].git_root
        for _, rel in ipairs(inputs[1].untracked_rel) do
            untracked_abs[git_root .. '/' .. rel] = true
        end
    end

    for _, input in ipairs(inputs) do
        if not untracked_abs[input.path] then
            local result = M.is_untracked_file(input.path, input.git_root)
            if result ~= false then return false end
        end
    end
    return true
end)()]]

-- The return value is always a boolean (never nil or another type).
IsUntrackedFile.properties.always_returns_boolean = [[(function()
    local inputs = _G.fixture.inputs
    for _, input in ipairs(inputs) do
        local result = M.is_untracked_file(input.path, input.git_root)
        if type(result) ~= 'boolean' then return false end
    end
    return true
end)()]]

T['is_untracked_file() properties'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- Stub get_untracked_files so it returns the fixture's rel paths
                M.get_untracked_files = function(_git_root)
                    return _G.fixture.inputs[1] and _G.fixture.inputs[1].untracked_rel or {}
                end

                -- Stub git_rel_to_abs to join the fixture's git_root with the rel path
                M.git_rel_to_abs = function(rel)
                    local git_root = _G.fixture.inputs[1] and _G.fixture.inputs[1].git_root or ''
                    return git_root .. '/' .. rel
                end
            ]])
        end,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- is_untracked_file() - example based tests

T['is_untracked_file()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                M.git_rel_to_abs = function(rel)
                    return '/repo/' .. rel
                end
            ]])
        end,
    },
})

T['is_untracked_file()']['forwards git_root to get_untracked_files'] = function()
    child.lua([[
        _G.fixture.captured_git_root = nil
        M.get_untracked_files = function(git_root)
            _G.fixture.captured_git_root = git_root
            return {}
        end
    ]])
    child.lua([[M.is_untracked_file('/repo/file.lua', '/repo')]])
    local captured = child.lua_get([[_G.fixture.captured_git_root]])
    eq(captured, '/repo')
end

T['is_untracked_file()']['passes nil git_root to get_untracked_files when not provided'] = function()
    child.lua([[
        _G.fixture.captured_git_root = 'sentinel'
        M.get_untracked_files = function(git_root)
            _G.fixture.captured_git_root = git_root
            return {}
        end
    ]])
    child.lua([[M.is_untracked_file('/repo/file.lua')]])
    local captured = child.lua_get([[_G.fixture.captured_git_root]])
    eq(captured, vim.NIL)
end

for func_name, func in pairs(IsUntrackedFile.properties) do
    for _, case in ipairs(IsUntrackedFile.cases) do
        local test_name = func_name .. ': ' .. case.name
        T['is_untracked_file() properties'][test_name] = function()
            child.lua([[_G.fixture.inputs = ...]], { IsUntrackedFile.get_inputs(case) })
            local result = child.lua_get(func)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_git_root() - example based tests

T['get_git_root()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                vim.fn.isdirectory = function(_) return 0 end
                vim.fn.fnamemodify = function(path, _) return path end
                vim.system = function(cmd, _opts)
                    _G.fixture.captured_cmd = cmd
                    return { wait = function() return { code = 0, stdout = '/repo\n', stderr = '' } end }
                end
            ]])
        end,
    },
})

T['get_git_root()']['calls git rev-parse --show-toplevel with -C and the file directory'] = function()
    child.lua([[
        _G.fixture.captured_cmd = nil
        vim.fn.fnamemodify = function(_path, _mod) return '/repo/lua' end
    ]])
    local result = child.lua_get([[M.get_git_root('/repo/lua/file.lua')]])
    local cmd = child.lua_get([[_G.fixture.captured_cmd]])
    eq(cmd[1], 'git')
    eq(cmd[2], '-C')
    eq(cmd[3], '/repo/lua')
    eq(cmd[4], 'rev-parse')
    eq(cmd[5], '--show-toplevel')
    eq(result, '/repo')
end

return T
