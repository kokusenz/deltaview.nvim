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
                -- Stub delta.utils_treesitter before require so M sees the stub
                package.loaded['delta.utils_treesitter'] = {
                    get_treesitter_highlight_captures = function(_content, _lang) return {} end,
                    get_treesitter_token_strings      = function(_str, _lang) return {} end,
                    get_lua_pattern_token_strings     = function(str)
                        local tokens = {}
                        for token in str:gmatch('[%w_]+') do
                            table.insert(tokens, token)
                        end
                        return tokens
                    end,
                }
            ]])
            child.lua([[M = require('delta.utils_highlighting')]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- initialize_hl_groups() - property based tests

local InitializeHlGroups = {}

InitializeHlGroups.initialize_hl_groups__property_cases = {
    { name = 'default setup' },
}

InitializeHlGroups.properties = {}

InitializeHlGroups.properties.calls_setup_hl_groups_immediately = [[(function()
    local setup_called = false
    M.setup_hl_groups = function() setup_called = true end
    vim.api.nvim_create_augroup = function() return 1 end
    vim.api.nvim_create_autocmd = function() end
    M.initialize_hl_groups()
    return setup_called
end)()]]

InitializeHlGroups.properties.colorscheme_autocmd_re_calls_setup_hl_groups = [[(function()
    local count = 0
    M.setup_hl_groups = function() count = count + 1 end
    local captured_callback = nil
    vim.api.nvim_create_augroup = function() return 1 end
    vim.api.nvim_create_autocmd = function(event, opts)
        if event == 'ColorScheme' then captured_callback = opts.callback end
    end
    M.initialize_hl_groups()
    if captured_callback then captured_callback() end
    return count == 2
end)()]]

T['initialize_hl_groups() properties'] = new_set()
for prop_name, prop in pairs(InitializeHlGroups.properties) do
    for _, case in ipairs(InitializeHlGroups.initialize_hl_groups__property_cases) do
        T['initialize_hl_groups() properties'][prop_name .. ': ' .. case.name] = function()
            local result = child.lua_get(prop)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup_hl_groups() - property based tests

local SetupHlGroups = {}

SetupHlGroups.setup_hl_groups__property_cases = {
    { name = 'dark background',  background = 'dark',  expected_added_line_color = '#002800' },
    { name = 'light background', background = 'light', expected_added_line_color = '#cfffd0' },
}

SetupHlGroups.properties = {}

SetupHlGroups.properties.uses_correct_color_for_background = [[(function()
    local inputs = _G.fixture.inputs
    local set_hl_calls = {}
    vim.api.nvim_set_hl = function(ns, name, def)
        set_hl_calls[name] = def
    end
    vim.o.background = inputs.background
    M.setup_hl_groups()
    local added_line = set_hl_calls['DeltaDiffAddedLine']
    if not added_line then return false end
    return added_line.bg == inputs.expected_added_line_color
end)()]]

SetupHlGroups.properties.highlight_groups_queryable_after_setup = [[(function()
    local inputs = _G.fixture.inputs
    vim.o.background = inputs.background
    M.setup_hl_groups()
    local hl = vim.api.nvim_get_hl(0, { name = 'DeltaDiffAddedLine', link = false })
    return type(hl.bg) == 'number'
end)()]]

T['setup_hl_groups() properties'] = new_set()
for prop_name, prop in pairs(SetupHlGroups.properties) do
    for _, case in ipairs(SetupHlGroups.setup_hl_groups__property_cases) do
        T['setup_hl_groups() properties'][prop_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.inputs = ...]], { {
                background = case.background,
                expected_added_line_color = case.expected_added_line_color,
            } })
            local result = child.lua_get(prop)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_highlights_multiple_files() - property based tests

local GetHighlightsMultipleFiles = {}

GetHighlightsMultipleFiles.get_inputs = function(case)
    local files = {}
    for _ = 1, case.n do table.insert(files, {}) end
    return { files = files, n = case.n }
end

GetHighlightsMultipleFiles.get_highlights_multiple_files__property_cases = {
    { name = '0 files', n = 0 },
    { name = '1 file',  n = 1 },
    { name = '2 files', n = 2 },
    { name = '3 files', n = 3 },
}

GetHighlightsMultipleFiles.properties = {}

GetHighlightsMultipleFiles.properties.calls_get_highlights_file_once_per_file = [[(function()
    local inputs = _G.fixture.inputs
    local count = 0
    M.get_highlights_file = function() count = count + 1; return {} end
    M.get_highlights_multiple_files(inputs.files, {})
    return count == inputs.n
end)()]]

T['get_highlights_multiple_files() properties'] = new_set()
for prop_name, prop in pairs(GetHighlightsMultipleFiles.properties) do
    for _, case in ipairs(GetHighlightsMultipleFiles.get_highlights_multiple_files__property_cases) do
        T['get_highlights_multiple_files() properties'][prop_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.inputs = ...]], { GetHighlightsMultipleFiles.get_inputs(case) })
            local result = child.lua_get(prop)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_highlights_file() - property based tests

local GetHighlightsFile = {}

GetHighlightsFile.get_inputs = function(case)
    local hunks = {}
    for _ = 1, case.n_hunks do table.insert(hunks, { lines = {} }) end
    return { file = { hunks = hunks, language = case.language }, n_hunks = case.n_hunks }
end

GetHighlightsFile.get_highlights_file__property_cases = {
    { name = '0 hunks with language',   n_hunks = 0, language = 'lua' },
    { name = '1 hunk with language',    n_hunks = 1, language = 'lua' },
    { name = '2 hunks with language',   n_hunks = 2, language = 'lua' },
    { name = '3 hunks with language',   n_hunks = 3, language = 'lua' },
    { name = '1 hunk without language', n_hunks = 1, language = nil },
}

GetHighlightsFile.properties = {}

GetHighlightsFile.properties.calls_helper_functions_once_per_hunk = [[(function()
    local inputs = _G.fixture.inputs
    local line_hl_count, adjacent_count, highlights_count = 0, 0, 0
    M.get_line_highlights    = function() line_hl_count    = line_hl_count    + 1; return {} end
    M.get_adjacent_line_sets = function() adjacent_count   = adjacent_count   + 1; return {} end
    M.get_highlights         = function() highlights_count = highlights_count + 1; return {} end
    M.get_highlights_file(inputs.file, {})
    return line_hl_count    == inputs.n_hunks
       and adjacent_count   == inputs.n_hunks
       and highlights_count == inputs.n_hunks
end)()]]

GetHighlightsFile.properties.calls_get_highlights_with_false_when_language_nil = [[(function()
    local inputs = _G.fixture.inputs
    -- assume: only check cases where language is nil
    if inputs.file.language ~= nil then return true end
    M.get_line_highlights    = function() return {} end
    M.get_adjacent_line_sets = function() return {} end
    local captured = nil
    M.get_highlights = function(adj, opts, lang, use_treesitter)
        captured = use_treesitter
        return {}
    end
    M.get_highlights_file(inputs.file, {})
    return captured == false
end)()]]

T['get_highlights_file() properties'] = new_set()
for prop_name, prop in pairs(GetHighlightsFile.properties) do
    for _, case in ipairs(GetHighlightsFile.get_highlights_file__property_cases) do
        T['get_highlights_file() properties'][prop_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.inputs = ...]], { GetHighlightsFile.get_inputs(case) })
            local result = child.lua_get(prop)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_line_highlights() - property based tests

local GetLineHighlights = {}

GetLineHighlights.get_inputs = function(case)
    local lines = {}
    for i = 1, case.n do
        table.insert(lines, { line_type = case.line_type, formatted_diff_line_num = i })
    end
    return { lines = lines, n = case.n, line_type = case.line_type }
end

GetLineHighlights.get_line_highlights__property_cases = {
    { name = '0 added lines',   n = 0, line_type = 'added' },
    { name = '1 added line',    n = 1, line_type = 'added' },
    { name = '2 added lines',   n = 2, line_type = 'added' },
    { name = '3 added lines',   n = 3, line_type = 'added' },
    { name = '0 removed lines', n = 0, line_type = 'removed' },
    { name = '1 removed line',  n = 1, line_type = 'removed' },
    { name = '2 removed lines', n = 2, line_type = 'removed' },
    { name = '3 removed lines', n = 3, line_type = 'removed' },
    { name = '3 context lines', n = 3, line_type = 'context' },
}

GetLineHighlights.properties = {}

GetLineHighlights.properties.produces_one_highlight_per_non_context_line = [[(function()
    local inputs = _G.fixture.inputs
    local result = M.get_line_highlights({ lines = inputs.lines })
    local count = 0
    for _ in pairs(result) do count = count + 1 end
    local expected = inputs.line_type == 'context' and 0 or inputs.n
    return count == expected
end)()]]

T['get_line_highlights() properties'] = new_set()
for prop_name, prop in pairs(GetLineHighlights.properties) do
    for _, case in ipairs(GetLineHighlights.get_line_highlights__property_cases) do
        T['get_line_highlights() properties'][prop_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.inputs = ...]], { GetLineHighlights.get_inputs(case) })
            local result = child.lua_get(prop)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_adjacent_line_sets() - property based tests

local GetAdjacentLineSets = {}

local gals_pbt_helpers = [=[
    local function reference_clusters(non_context_positions)
        local sorted = {}
        for _, p in ipairs(non_context_positions) do table.insert(sorted, p) end
        table.sort(sorted)
        local clusters = {}
        for _, pos in ipairs(sorted) do
            local last = clusters[#clusters]
            if last and pos - last[#last] <= 1 then
                table.insert(last, pos)
            else
                table.insert(clusters, { pos })
            end
        end
        return clusters
    end

    local function check_property(hunk, non_context_positions)
        local result = M.get_adjacent_line_sets(hunk)
        for _, set in ipairs(result) do
            for _, v in pairs(set) do
                if v == '' then return false, 'residue: empty string in output set' end
            end
        end
        local pos_to_set_idx = {}
        for set_idx, set in ipairs(result) do
            for pos, _ in pairs(set) do
                if pos_to_set_idx[pos] then
                    return false, 'coverage: pos ' .. pos .. ' appears in multiple sets'
                end
                pos_to_set_idx[pos] = set_idx
            end
        end
        for _, pos in ipairs(non_context_positions) do
            if not pos_to_set_idx[pos] then
                return false, 'coverage: pos ' .. pos .. ' missing from output'
            end
        end
        local ref = reference_clusters(non_context_positions)
        if #ref ~= #result then
            return false, 'set count: expected ' .. #ref .. ' got ' .. #result
        end
        for _, cluster in ipairs(ref) do
            local set_idx = pos_to_set_idx[cluster[1]]
            for _, pos in ipairs(cluster) do
                if pos_to_set_idx[pos] ~= set_idx then
                    return false, 'connectivity: pos ' .. pos .. ' in wrong set'
                end
            end
        end
        return true
    end

    _G.gals_check_property = check_property
]=]

GetAdjacentLineSets.get_inputs = function(case)
    if case.is_random then return { is_random = true } end
    local non_context = {}
    for _, l in ipairs(case.lines) do
        if l.line_type ~= 'context' then
            table.insert(non_context, l.formatted_diff_line_num)
        end
    end
    return { lines = case.lines, non_context_positions = non_context, is_random = false }
end

GetAdjacentLineSets.get_adjacent_line_sets__property_cases = {
    {
        name = 'empty hunk',
        lines = {}
    },
    {
        name = 'all context lines',
        lines = {
            { line_type = 'context', formatted_diff_line_num = 1 },
            { line_type = 'context', formatted_diff_line_num = 2 },
            { line_type = 'context', formatted_diff_line_num = 3 },
        }
    },
    {
        name = 'single non-context line',
        lines = {
            { line_type = 'added', formatted_diff_line_num = 5 },
        }
    },
    {
        name = 'two adjacent non-context lines',
        lines = {
            { line_type = 'added',   formatted_diff_line_num = 3 },
            { line_type = 'removed', formatted_diff_line_num = 4 },
        }
    },
    {
        name = 'two non-adjacent non-context lines',
        lines = {
            { line_type = 'added',   formatted_diff_line_num = 3 },
            { line_type = 'removed', formatted_diff_line_num = 7 },
        }
    },
    {
        name = 'context does not bridge non-adjacent lines',
        lines = {
            { line_type = 'added',   formatted_diff_line_num = 3 },
            { line_type = 'context', formatted_diff_line_num = 4 },
            { line_type = 'removed', formatted_diff_line_num = 5 },
        }
    },
    { name = 'random inputs', is_random = true },
}

GetAdjacentLineSets.properties = {}

GetAdjacentLineSets.properties.partition_correctness = [[(function()
    local inputs = _G.fixture.inputs
    if inputs.is_random then
        math.randomseed(42)
        local all_types = { 'added', 'removed', 'context' }
        for trial = 1, 100 do
            local k = math.random(1, 10)
            local used, positions = {}, {}
            for _ = 1, k do
                local pos
                repeat pos = math.random(1, 20) until not used[pos]
                used[pos] = true
                table.insert(positions, pos)
            end
            table.sort(positions)
            local lines, non_context_positions = {}, {}
            for _, pos in ipairs(positions) do
                local lt = all_types[math.random(1, 3)]
                table.insert(lines, { line_type = lt, formatted_diff_line_num = pos })
                if lt ~= 'context' then table.insert(non_context_positions, pos) end
            end
            local ok, err = _G.gals_check_property({ lines = lines }, non_context_positions)
            if not ok then
                return 'trial ' .. trial .. ': ' .. (err or 'unknown')
            end
        end
        return true
    end
    local ok, err = _G.gals_check_property({ lines = inputs.lines }, inputs.non_context_positions)
    return ok or err
end)()]]

T['get_adjacent_line_sets() properties'] = new_set()
for prop_name, prop in pairs(GetAdjacentLineSets.properties) do
    for _, case in ipairs(GetAdjacentLineSets.get_adjacent_line_sets__property_cases) do
        T['get_adjacent_line_sets() properties'][prop_name .. ': ' .. case.name] = function()
            child.lua(gals_pbt_helpers)
            child.lua([[_G.fixture.inputs = ...]], { GetAdjacentLineSets.get_inputs(case) })
            local result = child.lua_get(prop)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_highlights() - property based tests

local GetHighlights = {}

local gh_pbt_helpers = [=[
    local function install_stub()
        local calls = {}
        M.get_two_tier_highlights = function(added_content, removed_content)
            table.insert(calls, { tonumber(added_content), tonumber(removed_content) })
            return { added = {}, removed = {} }
        end
        return calls
    end

    local function check_property(adjacent_lines_sets, opts, all_input_keys)
        local stub_calls = install_stub()
        local result = M.get_highlights(adjacent_lines_sets, opts, nil, false)
        for key, _ in pairs(result) do
            if not all_input_keys[key] then
                return false, 'soundness: output key ' .. key .. ' not in any input set'
            end
        end
        local seen = {}
        for _, call in ipairs(stub_calls) do
            local added_key, removed_key = call[1], call[2]
            if seen[added_key] then
                return false, 'greedy: line ' .. tostring(added_key) .. ' matched twice as added'
            end
            if seen[removed_key] then
                return false, 'greedy: line ' .. tostring(removed_key) .. ' matched twice as removed'
            end
            seen[added_key] = true
            seen[removed_key] = true
        end
        return true
    end

    _G.gh_check_property = check_property
]=]

GetHighlights.get_highlights__property_cases = {
    {
        name = 'empty input',
        adjacent_lines_sets = {},
        all_input_keys = {},
        opts = { highlighting = { max_similarity_threshold = 0.6 } },
        expect_stub_called = false
    },
    {
        name = 'all-added set',
        adjacent_lines_sets = { {
            [1] = { new_line_num = 1, content = '1' },
            [2] = { new_line_num = 2, content = '2' }
        } },
        all_input_keys = { [1] = true, [2] = true },
        opts = { highlighting = { max_similarity_threshold = 0.6 } },
        expect_stub_called = false
    },
    {
        name = 'all-removed set',
        adjacent_lines_sets = { {
            [1] = { old_line_num = 1, content = '1' },
            [2] = { old_line_num = 2, content = '2' }
        } },
        all_input_keys = { [1] = true, [2] = true },
        opts = { highlighting = { max_similarity_threshold = 0.6 } },
        expect_stub_called = false
    },
    {
        name = 'identical content above threshold',
        adjacent_lines_sets = { {
            [1] = { new_line_num = 1, content = 'hello' },
            [2] = { old_line_num = 1, content = 'hello' }
        } },
        all_input_keys = { [1] = true, [2] = true },
        opts = { highlighting = { max_similarity_threshold = 0.6 } },
        expect_stub_called = true
    },
    {
        name = 'threshold above 1.0 suppresses all matches',
        adjacent_lines_sets = { {
            [1] = { new_line_num = 1, content = 'hello' },
            [2] = { old_line_num = 1, content = 'hello' }
        } },
        all_input_keys = { [1] = true, [2] = true },
        opts = { highlighting = { max_similarity_threshold = 1.1 } },
        expect_stub_called = false
    },
    { name = 'random inputs', is_random = true },
}

GetHighlights.properties = {}

GetHighlights.properties.stub_called_iff_expected = [[(function()
    local inputs = _G.fixture.inputs
    -- assume: only structural cases carry expect_stub_called
    if inputs.is_random then return true end
    local called = false
    M.get_two_tier_highlights = function() called = true; return { added = {}, removed = {} } end
    M.get_highlights(inputs.adjacent_lines_sets, inputs.opts, nil, false)
    return called == inputs.expect_stub_called
end)()]]

GetHighlights.properties.soundness_and_greedy_matching = [[(function()
    local inputs = _G.fixture.inputs
    if inputs.is_random then
        math.randomseed(42)
        local opts = { highlighting = { max_similarity_threshold = 0.6 } }
        for trial = 1, 100 do
            local adjacent_lines_sets, all_input_keys, next_key = {}, {}, 1
            for _ = 1, math.random(0, 4) do
                local set = {}
                for _ = 1, math.random(0, 3) do
                    local key = next_key; next_key = next_key + 1
                    set[key] = { new_line_num = 1, content = tostring(key) }
                    all_input_keys[key] = true
                end
                for _ = 1, math.random(0, 3) do
                    local key = next_key; next_key = next_key + 1
                    set[key] = { old_line_num = 1, content = tostring(key) }
                    all_input_keys[key] = true
                end
                if next(set) then table.insert(adjacent_lines_sets, set) end
            end
            local ok, err = _G.gh_check_property(adjacent_lines_sets, opts, all_input_keys)
            if not ok then
                return 'trial ' .. trial .. ': ' .. (err or 'unknown')
            end
        end
        return true
    end
    -- structural: simple soundness check with stub installed
    M.get_two_tier_highlights = function() return { added = {}, removed = {} } end
    local result = M.get_highlights(inputs.adjacent_lines_sets, inputs.opts, nil, false)
    for key, _ in pairs(result) do
        if not inputs.all_input_keys[key] then
            return 'soundness: output key ' .. key .. ' not in input keys'
        end
    end
    return true
end)()]]

T['get_highlights() properties'] = new_set()
for prop_name, prop in pairs(GetHighlights.properties) do
    for _, case in ipairs(GetHighlights.get_highlights__property_cases) do
        T['get_highlights() properties'][prop_name .. ': ' .. case.name] = function()
            child.lua(gh_pbt_helpers)
            child.lua([[_G.fixture.inputs = ...]], { {
                adjacent_lines_sets = case.adjacent_lines_sets,
                all_input_keys      = case.all_input_keys,
                opts                = case.opts,
                expect_stub_called  = case.expect_stub_called,
                is_random           = case.is_random,
            } })
            local result = child.lua_get(prop)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_two_tier_highlights() - property based tests

local GetTwoTierHighlights = {}

local gtth_pbt_helpers = [=[
    local function check_property(str1, str2)
        local result = M.get_two_tier_highlights(str1, str2, nil, false)
        if result == nil then
            return false, 'unexpected nil for use_treesitter=false'
        end
        for i, h in ipairs(result.added) do
            if h.col < 0 then
                return false, 'added[' .. i .. ']: col ' .. h.col .. ' < 0'
            end
            if h.end_col <= h.col then
                return false, 'added[' .. i .. ']: end_col ' .. h.end_col .. ' <= col ' .. h.col
            end
            if h.end_col > #str1 then
                return false, 'added[' .. i .. ']: end_col ' .. h.end_col .. ' > #str1 ' .. #str1
            end
        end
        for i, h in ipairs(result.removed) do
            if h.col < 0 then
                return false, 'removed[' .. i .. ']: col ' .. h.col .. ' < 0'
            end
            if h.end_col <= h.col then
                return false, 'removed[' .. i .. ']: end_col ' .. h.end_col .. ' <= col ' .. h.col
            end
            if h.end_col > #str2 then
                return false, 'removed[' .. i .. ']: end_col ' .. h.end_col .. ' > #str2 ' .. #str2
            end
        end
        for i = 1, #result.added - 1 do
            local h1, h2 = result.added[i], result.added[i + 1]
            if h1.end_col > h2.col then
                return false, 'added overlap: [' .. i .. '].end_col=' .. h1.end_col .. ' > [' .. (i+1) .. '].col=' .. h2.col
            end
        end
        for i = 1, #result.removed - 1 do
            local h1, h2 = result.removed[i], result.removed[i + 1]
            if h1.end_col > h2.col then
                return false, 'removed overlap: [' .. i .. '].end_col=' .. h1.end_col .. ' > [' .. (i+1) .. '].col=' .. h2.col
            end
        end
        return true
    end

    _G.gtth_check_property = check_property
]=]

GetTwoTierHighlights.get_two_tier_highlights__property_cases = {
    {
        name = 'use_treesitter true with nil language',
        str1 = 'foo',
        str2 = 'bar',
        use_treesitter = true,
        expect_nil = true
    },
    {
        name = 'identical strings',
        str1 = 'hello world',
        str2 = 'hello world',
        use_treesitter = false
    },
    {
        name = 'completely disjoint strings',
        str1 = 'foo bar',
        str2 = 'baz qux',
        use_treesitter = false,
        expect_both_nonempty = true
    },
    {
        name = 'empty str1',
        str1 = '',
        str2 = 'foo bar',
        use_treesitter = false
    },
    {
        name = 'empty str2',
        str1 = 'foo bar',
        str2 = '',
        use_treesitter = false
    },
    { name = 'random inputs', is_random = true },
}

GetTwoTierHighlights.properties = {}

GetTwoTierHighlights.properties.nil_when_treesitter_without_language = [[(function()
    local inputs = _G.fixture.inputs
    -- assume: only the treesitter-without-language case
    if not inputs.expect_nil then return true end
    local result = M.get_two_tier_highlights(inputs.str1, inputs.str2, nil, true)
    return result == nil
end)()]]

GetTwoTierHighlights.properties.highlight_validity = [[(function()
    local inputs = _G.fixture.inputs
    -- assume: skip nil-returning case and random (handled separately below)
    if inputs.expect_nil then return true end
    if inputs.is_random then
        math.randomseed(42)
        local vocab = { 'foo', 'bar', 'baz', 'qux' }
        local function random_string()
            local words = {}
            for _ = 1, math.random(0, 6) do
                table.insert(words, vocab[math.random(1, #vocab)])
            end
            return table.concat(words, ' ')
        end
        for trial = 1, 100 do
            local str1, str2 = random_string(), random_string()
            local ok, err = _G.gtth_check_property(str1, str2)
            if not ok then
                return 'trial ' .. trial .. ' ("' .. str1 .. '" / "' .. str2 .. '"): ' .. (err or 'unknown')
            end
        end
        return true
    end
    local ok, err = _G.gtth_check_property(inputs.str1, inputs.str2)
    return ok or err
end)()]]

GetTwoTierHighlights.properties.no_highlights_when_content_unchanged = [[(function()
    local inputs = _G.fixture.inputs
    if inputs.is_random or inputs.expect_nil then return true end
    local result = M.get_two_tier_highlights(inputs.str1, inputs.str2, nil, false)
    -- identical strings → both empty
    if inputs.str1 == inputs.str2 then
        return #result.added == 0 and #result.removed == 0
    end
    -- empty str1 → no added highlights
    if inputs.str1 == '' then return #result.added == 0 end
    -- empty str2 → no removed highlights
    if inputs.str2 == '' then return #result.removed == 0 end
    return true
end)()]]

GetTwoTierHighlights.properties.produces_highlights_for_changed_content = [[(function()
    local inputs = _G.fixture.inputs
    -- assume: only the 'expect_both_nonempty' case
    if not inputs.expect_both_nonempty then return true end
    local result = M.get_two_tier_highlights(inputs.str1, inputs.str2, nil, false)
    return #result.added > 0 and #result.removed > 0
end)()]]

T['get_two_tier_highlights() properties'] = new_set()
for prop_name, prop in pairs(GetTwoTierHighlights.properties) do
    for _, case in ipairs(GetTwoTierHighlights.get_two_tier_highlights__property_cases) do
        T['get_two_tier_highlights() properties'][prop_name .. ': ' .. case.name] = function()
            child.lua(gtth_pbt_helpers)
            child.lua([[_G.fixture.inputs = ...]], { {
                str1                 = case.str1,
                str2                 = case.str2,
                use_treesitter       = case.use_treesitter,
                expect_nil           = case.expect_nil,
                expect_both_nonempty = case.expect_both_nonempty,
                is_random            = case.is_random,
            } })
            local result = child.lua_get(prop)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- calculate_similarity() - property based tests

local CalculateSimilarity = {}

CalculateSimilarity.get_inputs = function(case)
    return { str1 = case.str1, str2 = case.str2, threshold = case.threshold, is_random = case.is_random }
end

CalculateSimilarity.calculate_similarity__property_cases = {
    -- existing cases, now carry an explicit threshold
    { name = 'identical strings',    str1 = 'hello',  str2 = 'hello',  threshold = 0.6 },
    { name = 'empty vs non-empty',   str1 = '',       str2 = 'hello',  threshold = 0.6 },
    { name = 'completely different', str1 = 'abc',    str2 = 'xyz',    threshold = 0.6 },
    { name = 'random inputs',        is_random = true, threshold = 0.6 },

    -- length-ratio early exit: min/max = 0.1 which is below threshold 0.6, must return 0.0
    { name = 'length ratio below threshold',
      str1 = 'a', str2 = 'aaaaaaaaaa', threshold = 0.6 },
    -- length-ratio NOT triggered: ratio ~0.83 > 0.6, must compute properly
    { name = 'length ratio above threshold computes normally',
      str1 = 'hello', str2 = 'hellox', threshold = 0.6 },

    -- row-min early exit: every char differs so row_min hits threshold fast
    { name = 'row min early exit: all chars differ',
      str1 = 'aaaa', str2 = 'bbbb', threshold = 0.5 },

    -- known Levenshtein values to verify byte-level correctness
    { name = 'known distance: kitten->sitting',
      str1 = 'kitten', str2 = 'sitting', threshold = 0.0 },
    { name = 'known distance: sunday->saturday',
      str1 = 'sunday', str2 = 'saturday', threshold = 0.0 },
    { name = 'known distance: single char mismatch',
      str1 = 'a', str2 = 'b', threshold = 0.0 },
}

CalculateSimilarity.properties = {}

CalculateSimilarity.properties.result_in_range_0_to_1 = [[(function()
    local inputs = _G.fixture.inputs
    if inputs.is_random then
        math.randomseed(42)
        local vocab = { 'foo', 'bar', 'baz', 'qux' }
        local function random_string()
            local words = {}
            for _ = 1, math.random(0, 6) do
                table.insert(words, vocab[math.random(1, #vocab)])
            end
            return table.concat(words, ' ')
        end
        for trial = 1, 100 do
            local str1, str2 = random_string(), random_string()
            local sim = M.calculate_similarity(str1, str2, inputs.threshold)
            if type(sim) ~= 'number' then
                return 'trial ' .. trial .. ': expected number, got ' .. type(sim)
            end
            if sim < 0 or sim > 1 then
                return 'trial ' .. trial .. ' ("' .. str1 .. '" / "' .. str2 .. '"): ' .. sim .. ' out of [0, 1]'
            end
        end
        return true
    end
    local sim = M.calculate_similarity(inputs.str1, inputs.str2, inputs.threshold)
    return type(sim) == 'number' and sim >= 0 and sim <= 1
end)()]]

CalculateSimilarity.properties.identical_strings_return_1 = [[(function()
    local inputs = _G.fixture.inputs
    -- assume: only identical-string cases
    if inputs.is_random or inputs.str1 ~= inputs.str2 then return true end
    return M.calculate_similarity(inputs.str1, inputs.str2, inputs.threshold) == 1.0
end)()]]

-- length-ratio early exit: when min_len/max_len < threshold the full matrix
-- must be skipped and 0.0 returned.
CalculateSimilarity.properties.length_ratio_early_exit_returns_zero = [[(function()
    local inputs = _G.fixture.inputs
    if inputs.is_random then return true end
    if inputs.str1 ~= 'a' or inputs.str2 ~= 'aaaaaaaaaa' then return true end
    -- min/max = 1/10 = 0.1, threshold = 0.6  →  must return 0.0
    local sim = M.calculate_similarity(inputs.str1, inputs.str2, inputs.threshold)
    return sim == 0.0
end)()]]

-- when length ratio is above threshold the function must not short-circuit
-- and must return a non-zero value for strings that genuinely share content.
CalculateSimilarity.properties.length_ratio_above_threshold_computes = [[(function()
    local inputs = _G.fixture.inputs
    if inputs.is_random then return true end
    if inputs.str1 ~= 'hello' or inputs.str2 ~= 'hellox' then return true end
    -- ratio = 5/6 ≈ 0.83 > 0.6, strings are very similar → result must be > 0
    local sim = M.calculate_similarity(inputs.str1, inputs.str2, inputs.threshold)
    return sim > 0.0
end)()]]

-- row-min early exit: once the minimum edit distance in any row already
-- exceeds (1 - threshold) * max_len, we know the final similarity will be
-- below the threshold and can abort without finishing the matrix.
CalculateSimilarity.properties.row_min_early_exit_returns_zero = [[(function()
    local inputs = _G.fixture.inputs
    if inputs.is_random then return true end
    if inputs.str1 ~= 'aaaa' or inputs.str2 ~= 'bbbb' then return true end
    -- every character differs: row_min reaches 4 quickly.
    -- (1 - 0.5) * 4 = 2  →  row_min(=4) > 2, triggers early exit.
    local sim = M.calculate_similarity(inputs.str1, inputs.str2, inputs.threshold)
    return sim == 0.0
end)()]]

-- verify byte-level correctness against known Levenshtein distances so that
-- any future change from byte() back to sub() that alters results is caught.
CalculateSimilarity.properties.known_levenshtein_values = [[(function()
    local inputs = _G.fixture.inputs
    if inputs.is_random then return true end
    local known = {
        -- distance 3, max_len 7  →  1 - 3/7
        ['kitten:sitting']   = 1.0 - 3/7,
        -- distance 3, max_len 8  →  1 - 3/8
        ['sunday:saturday']  = 1.0 - 3/8,
        -- distance 1, max_len 1  →  0.0
        ['a:b']              = 0.0,
    }
    local key = inputs.str1 .. ':' .. inputs.str2
    local expected = known[key]
    if expected == nil then return true end  -- not a known-distance case, skip
    local sim = M.calculate_similarity(inputs.str1, inputs.str2, inputs.threshold)
    local eps = 1e-9
    return math.abs(sim - expected) < eps
end)()]]

T['calculate_similarity() properties'] = new_set()
for prop_name, prop in pairs(CalculateSimilarity.properties) do
    for _, case in ipairs(CalculateSimilarity.calculate_similarity__property_cases) do
        T['calculate_similarity() properties'][prop_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.inputs = ...]], { CalculateSimilarity.get_inputs(case) })
            local result = child.lua_get(prop)
            eq(result, true)
        end
    end
end

return T
