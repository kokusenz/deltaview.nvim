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

return T
