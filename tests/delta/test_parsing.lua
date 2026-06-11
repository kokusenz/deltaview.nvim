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
-- fixtures

local single_hunk_diff = table.concat({
    "@@ -1,3 +1,3 @@",
    " local x = 1",
    "-local y = 2",
    "+local y = 10",
    " local z = 3",
}, "\n")

local multi_hunk_diff = table.concat({
    "@@ -1,3 +1,3 @@",
    " local x = 1",
    "-local y = 2",
    "+local y = 10",
    " local z = 3",
    "@@ -10,3 +10,3 @@",
    " local a = 1",
    "-local b = 2",
    "+local b = 20",
    " local c = 3",
}, "\n")

local hunk_with_context_diff = table.concat({
    "@@ -5,3 +5,3 @@ function foo()",
    " local x = 1",
    "-local y = 2",
    "+local y = 10",
    " local z = 3",
}, "\n")

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

local multi_file_git_diff = table.concat({
    "diff --git a/foo.lua b/foo.lua",
    "index abc1234..def5678 100644",
    "--- a/foo.lua",
    "+++ b/foo.lua",
    "@@ -1,2 +1,2 @@",
    "-local x = 1",
    "+local x = 2",
    " local y = 3",
    "diff --git a/bar.py b/bar.py",
    "index ghi5678..jkl9012 100644",
    "--- a/bar.py",
    "+++ b/bar.py",
    "@@ -5,2 +5,2 @@",
    "-x = 1",
    "+x = 2",
    " y = 3",
}, "\n")

local new_file_git_diff = table.concat({
    "diff --git a/new.lua b/new.lua",
    "new file mode 100644",
    "index 0000000..abc1234",
    "--- /dev/null",
    "+++ b/new.lua",
    "@@ -0,0 +1,2 @@",
    "+local x = 1",
    "+local y = 2",
}, "\n")

-- diff.mnemonicPrefix uses c/ (commit) and w/ (worktree) instead of a/ and b/
local mnemonic_prefix_single_file_git_diff = table.concat({
    "diff --git c/foo.lua w/foo.lua",
    "index abc1234..def5678 100644",
    "--- c/foo.lua",
    "+++ w/foo.lua",
    "@@ -1,3 +1,3 @@",
    " local x = 1",
    "-local y = 2",
    "+local y = 10",
    " local z = 3",
}, "\n")

-- diff.mnemonicPrefix with i/ (index) and w/ (worktree) for staged vs worktree
local mnemonic_prefix_multi_file_git_diff = table.concat({
    "diff --git c/foo.lua w/foo.lua",
    "index abc1234..def5678 100644",
    "--- c/foo.lua",
    "+++ w/foo.lua",
    "@@ -1,2 +1,2 @@",
    "-local x = 1",
    "+local x = 2",
    " local y = 3",
    "diff --git c/bar.py w/bar.py",
    "index ghi5678..jkl9012 100644",
    "--- c/bar.py",
    "+++ w/bar.py",
    "@@ -5,2 +5,2 @@",
    "-x = 1",
    "+x = 2",
    " y = 3",
}, "\n")

local git_diff_artifacts_in_content_git_diff_deleted = table.concat({
    "diff --git a/foo.lua b/foo.lua",
    "index abc1234..def5678 100644",
    "--- a/foo.lua",
    "+++ b/foo.lua",
    "@@ -1,3 +1,3 @@",
    " local x = 1",
    "-local y = 2",
    "+local y = 10",
    " local z = 3",
    "@@ -10,3 +10,3 @@",
    " local a = 1",
    "--- this is a lua comment, I will delete",
    "-local b = 2",
    "+local b = 20",
    " local c = 3",
}, "\n")

-- binary file diff: no ---/+++ header
local binary_file_git_diff = table.concat({
    "diff --git a/photo.jpg b/photo.jpg",
    "index abc1234..def5678 100644",
    "Binary files a/photo.jpg and b/photo.jpg differ",
}, "\n")

-- mode-only change: no ---/+++ header
local mode_only_git_diff = table.concat({
    "diff --git a/script.sh b/script.sh",
    "old mode 100644",
    "new mode 100755",
}, "\n")

-- new file
local new_file_mode_git_diff = table.concat({
    "diff --git a/newfile.md b/newfile.md",
    "new file mode 100644",
    "index 0000000000000000000000000000000000000000..039727ec5a50d0ed45ff67e6f4c9b953bd23c17d",
    "--- /dev/null",
    "+++ b/newfile.md",
    "@@ -0,0 +1 @@",
    "+lol"
}, "\n")

-- two-file diff: first is a new file, second is a regular change
-- used to verify that new_file / blob hash metadata does not bleed from file 1 to file 2
local new_file_then_regular_git_diff = table.concat({
    "diff --git a/added.lua b/added.lua",
    "new file mode 100644",
    "index 0000000..aaa1111",
    "--- /dev/null",
    "+++ b/added.lua",
    "@@ -0,0 +1 @@",
    "+new content",
    "diff --git a/existing.lua b/existing.lua",
    "index bbb2222..ccc3333 100644",
    "--- a/existing.lua",
    "+++ b/existing.lua",
    "@@ -1,1 +1,1 @@",
    "-old",
    "+new",
}, "\n")

local git_diff_artifacts_in_content_git_diff_added = table.concat({
    "diff --git a/foo.lua b/foo.lua",
    "index abc1234..def5678 100644",
    "--- a/foo.lua",
    "+++ b/foo.lua",
    "@@ -1,3 +1,3 @@",
    " local x = 1",
    "-local y = 2",
    "+local y = 10",
    " local z = 3",
    "@@ -10,3 +10,3 @@",
    " local a = 1",
    "-local b = 2",
    "+++ this is a lua comment I am now adding",
    "+local b = 20",
    " local c = 3",
}, "\n")

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup

-- Note: child.lua_get(expr) prepends 'return' to expr before executing.
-- Multi-line code with locals must be wrapped in an IIFE: (function() ... end)()

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                -- Stub module-level dependencies before require so M sees the stubs
                package.loaded['delta.config'] = {
                    options = {
                        context = 3,
                        highlighting = { max_similarity_threshold = 0.6 },
                        new_file = false,
                    },
                }
                package.loaded['delta.utils'] = {
                    build_git_diff_cmd_with_flags = function(_effective, _ref, _path)
                        return { 'git', 'diff', 'HEAD' }
                    end,
                    get_window_width = function(_winid) return 80 end,
                    apply_highlights  = function(_bufnr, _highlights) end,
                    get_language_from_filename = function(filename)
                        local ext = filename:match('%.([^%.]+)$')
                        local map = { lua = 'lua', py = 'python' }
                        return map[ext]
                    end,
                }
                package.loaded['delta.utils_treesitter'] = {
                    get_treesitter_highlight_captures = function(_content, _lang) return {} end,
                    get_treesitter_token_strings      = function(_str, _lang) return {} end,
                    get_lua_pattern_token_strings     = function(_str) return {} end,
                }
                package.loaded['delta.utils_highlighting'] = {
                    get_highlights_multiple_files = function(_files, _opts) return {} end,
                }
            ]])
            child.lua([[M = require('delta.diff')]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_diff_data() - example based tests

T['get_diff_data()'] = new_set()

T['get_diff_data()']['stores language'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_hunk_diff })
    local result = child.lua_get([[M.get_diff_data(_G.fixture.diff, 'lua').language]])
    eq(result, 'lua')
end

T['get_diff_data()']['parses hunk header fields'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_hunk_diff })
    local hunk = child.lua_get([[(function()
        local h = M.get_diff_data(_G.fixture.diff, 'lua').hunks[1]
        return { old_start = h.old_start, old_count = h.old_count, new_start = h.new_start, new_count = h.new_count }
    end)()]])
    eq(hunk.old_start, 1)
    eq(hunk.old_count, 3)
    eq(hunk.new_start, 1)
    eq(hunk.new_count, 3)
end

T['get_diff_data()']['parses context string from hunk header'] = function()
    child.lua([[_G.fixture.diff = ...]], { hunk_with_context_diff })
    local context = child.lua_get([[M.get_diff_data(_G.fixture.diff, 'lua').hunks[1].context]])
    eq(context, 'function foo()')
end

T['get_diff_data()']['context line: both line numbers set, content stripped'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_hunk_diff })
    -- line 1 is " local x = 1" (context)
    local line = child.lua_get([[(function()
        local lines = M.get_diff_data(_G.fixture.diff, 'lua').hunks[1].lines
        return { old = lines[1].old_line_num, new = lines[1].new_line_num, type = lines[1].line_type, content = lines[1].content }
    end)()]])
    eq(line.old, 1)
    eq(line.new, 1)
    eq(line.type, 'context')
    eq(line.content, 'local x = 1')
end

T['get_diff_data()']['removed line: old_line_num set, new_line_num nil, content stripped'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_hunk_diff })
    -- line 2 is "-local y = 2" (removed)
    local line = child.lua_get([[(function()
        local lines = M.get_diff_data(_G.fixture.diff, 'lua').hunks[1].lines
        return { old = lines[2].old_line_num, new = lines[2].new_line_num, type = lines[2].line_type, content = lines[2].content }
    end)()]])
    eq(line.old, 2)
    eq(line.new, nil)
    eq(line.type, 'removed')
    eq(line.content, 'local y = 2')
end

T['get_diff_data()']['added line: new_line_num set, old_line_num nil, content stripped'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_hunk_diff })
    -- line 3 is "+local y = 10" (added)
    local line = child.lua_get([[(function()
        local lines = M.get_diff_data(_G.fixture.diff, 'lua').hunks[1].lines
        return { old = lines[3].old_line_num, new = lines[3].new_line_num, type = lines[3].line_type, content = lines[3].content }
    end)()]])
    eq(line.old, nil)
    eq(line.new, 2)
    eq(line.type, 'added')
    eq(line.content, 'local y = 10')
end

T['get_diff_data()']['line numbers advance correctly across a hunk'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_hunk_diff })
    -- context(old=1,new=1) → removed(old=2) → added(new=2) → context(old=3,new=3)
    local last = child.lua_get([[(function()
        local lines = M.get_diff_data(_G.fixture.diff, 'lua').hunks[1].lines
        return { old = lines[4].old_line_num, new = lines[4].new_line_num }
    end)()]])
    eq(last.old, 3)
    eq(last.new, 3)
end

T['get_diff_data()']['second hunk starts at its declared line numbers'] = function()
    child.lua([[_G.fixture.diff = ...]], { multi_hunk_diff })
    local result = child.lua_get([[(function()
        local data = M.get_diff_data(_G.fixture.diff, 'lua')
        local h = data.hunks[2]
        return { old_start = h.old_start, new_start = h.new_start, first_old = h.lines[1].old_line_num, first_new = h.lines[1].new_line_num }
    end)()]])
    eq(result.old_start, 10)
    eq(result.new_start, 10)
    eq(result.first_old, 10)
    eq(result.first_new, 10)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_diff_data() - property based tests

local GetDiffData = {}

GetDiffData.get_diff_data__property_cases = {
    {
        name = 'pure context',
        diff = "@@ -1,3 +1,3 @@\n local a\n local b\n local c",
    },
    {
        name = 'pure addition',
        diff = "@@ -4,0 +5,3 @@\n+line1\n+line2\n+line3",
    },
    {
        name = 'pure deletion',
        diff = "@@ -5,3 +4,0 @@\n-line1\n-line2\n-line3",
    },
    {
        name = 'mixed replace',
        diff = "@@ -1,4 +1,4 @@\n context\n-old line\n+new line\n context2",
    },
    {
        name = 'old line numbers much larger than new',
        diff = "@@ -100,4 +1,4 @@\n context\n-removed\n+added\n context2",
    },
    {
        name = 'lines that start with minus but arent deleted',
        diff = "@@ -5,3 +4,0 @@\n -line1\n-line2\n line3",
    },
    {
        name = 'lines that start with a plus but arent added',
        diff = "@@ -5,3 +4,0 @@\n +line1\n-line2\n line3",
    },
    {
        name = 'binary file diff (no hunks)',
        diff = "Binary files a/photo.jpg and b/photo.jpg differ",
    },
    {
        name = 'mode-only change (no content)',
        diff = "",
    },
    {
        name = 'new file with single added line',
        diff = "@@ -0,0 +1 @@\n+new line",
    },
}

GetDiffData.properties = {}

-- Checks type/nil consistency for every line in every hunk.
-- Returns true on success, or an error string on the first violation.
GetDiffData.properties.type_nil_consistency = [[(function()
    local hunks = M.get_diff_data(_G.fixture.diff, 'lua').hunks
    for _, hunk in ipairs(hunks) do
        for _, line in ipairs(hunk.lines) do
            if line.line_type == 'added' then
                if line.new_line_num == nil then return 'added: new_line_num is nil' end
                if line.old_line_num ~= nil then return 'added: old_line_num should be nil' end
            elseif line.line_type == 'removed' then
                if line.old_line_num == nil then return 'removed: old_line_num is nil' end
                if line.new_line_num ~= nil then return 'removed: new_line_num should be nil' end
            elseif line.line_type == 'context' then
                if line.old_line_num == nil then return 'context: old_line_num is nil' end
                if line.new_line_num == nil then return 'context: new_line_num is nil' end
            else
                return 'unknown line_type: ' .. tostring(line.line_type)
            end
        end
    end
    return true
end)()]]

-- Checks that old_line_num and new_line_num each advance strictly within a hunk.
-- Returns true on success, or an error string on the first violation.
GetDiffData.properties.line_number_monotonicity = [[(function()
    local hunks = M.get_diff_data(_G.fixture.diff, 'lua').hunks
    for _, hunk in ipairs(hunks) do
        local prev_old, prev_new = nil, nil
        for _, line in ipairs(hunk.lines) do
            if line.old_line_num ~= nil then
                if prev_old ~= nil and line.old_line_num <= prev_old then
                    return 'old_line_num not strictly increasing: ' .. line.old_line_num .. ' after ' .. prev_old
                end
                prev_old = line.old_line_num
            end
            if line.new_line_num ~= nil then
                if prev_new ~= nil and line.new_line_num <= prev_new then
                    return 'new_line_num not strictly increasing: ' .. line.new_line_num .. ' after ' .. prev_new
                end
                prev_new = line.new_line_num
            end
        end
    end
    return true
end)()]]

-- Checks that a line of code that starts with - or + will not be processed as a
-- deleted/added line when it is in fact a context line (prefixed by a space).
GetDiffData.properties.no_false_positive_context_lines = [[(function()
    local text_lines = vim.split(_G.fixture.diff, '\n', { plain = true })
    local lines_that_should_be_context = {}
    for _, line in ipairs(text_lines) do
        local chars = vim.split(line, '')
        if chars[1] == ' ' then
            table.insert(lines_that_should_be_context, line)
        end
    end

    local hunks = M.get_diff_data(_G.fixture.diff, 'lua').hunks
    for _, context_line in ipairs(lines_that_should_be_context) do
        local found = false
        for _, hunk in ipairs(hunks) do
            for _, line in ipairs(hunk.lines) do
                if line.line_type == 'context' and line.content == context_line:sub(2) then
                    found = true
                end
            end
        end
        if found == false then
            return false
        end
    end
    return true
end)()]]

T['get_diff_data() properties'] = new_set()
for prop_name, prop in pairs(GetDiffData.properties) do
    for _, case in ipairs(GetDiffData.get_diff_data__property_cases) do
        T['get_diff_data() properties'][prop_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.diff = ...]], { case.diff })
            local result = child.lua_get(prop)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_diff_data_git() - example based tests

T['get_diff_data_git()'] = new_set()

T['get_diff_data_git()']['returns one entry for a single-file diff'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_file_git_diff })
    local count = child.lua_get([[#M.get_diff_data_git(_G.fixture.diff)]])
    eq(count, 1)
end

T['get_diff_data_git()']['parses old_path and new_path'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_file_git_diff })
    local paths = child.lua_get([[(function()
        local d = M.get_diff_data_git(_G.fixture.diff)[1]
        return { old_path = d.old_path, new_path = d.new_path }
    end)()]])
    eq(paths.old_path, 'foo.lua')
    eq(paths.new_path, 'foo.lua')
end

T['get_diff_data_git()']['infers language from file extension'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_file_git_diff })
    local language = child.lua_get([[M.get_diff_data_git(_G.fixture.diff)[1].language]])
    eq(language, 'lua')
end

T['get_diff_data_git()']['returns one entry per file for a multi-file diff'] = function()
    child.lua([[_G.fixture.diff = ...]], { multi_file_git_diff })
    local result = child.lua_get([[(function()
        local data = M.get_diff_data_git(_G.fixture.diff)
        return { count = #data, first = data[1].new_path, second = data[2].new_path }
    end)()]])
    eq(result.count, 2)
    eq(result.first, 'foo.lua')
    eq(result.second, 'bar.py')
end

T['get_diff_data_git()']['second file hunk starts at its declared line numbers'] = function()
    child.lua([[_G.fixture.diff = ...]], { multi_file_git_diff })
    local result = child.lua_get([[(function()
        local h = M.get_diff_data_git(_G.fixture.diff)[2].hunks[1]
        return { old_start = h.old_start, new_start = h.new_start }
    end)()]])
    eq(result.old_start, 5)
    eq(result.new_start, 5)
end

T['get_diff_data_git()']['handles new file (from /dev/null)'] = function()
    child.lua([[_G.fixture.diff = ...]], { new_file_git_diff })
    local result = child.lua_get([[(function()
        local d = M.get_diff_data_git(_G.fixture.diff)[1]
        return { new_path = d.new_path, line_count = #d.hunks[1].lines }
    end)()]])
    eq(result.new_path, 'new.lua')
    eq(result.line_count, 2)
end

T['get_diff_data_git()']['triple minus outside of a hunk header will be processed as a real line'] = function()
    child.lua([[_G.fixture.diff = ...]], { git_diff_artifacts_in_content_git_diff_deleted })
    local result = child.lua_get([[(function()
        return M.get_diff_data_git(_G.fixture.diff)
    end)()]])
    local found = false
    for _, diff_data in ipairs(result) do
        for _, hunk in ipairs(diff_data.hunks) do
            for _, line in ipairs(hunk.lines) do
                -- expect this to be deleted
                if line.new_line_num == nil and line.line_type == 'removed' and line.content == '-- this is a lua comment, I will delete' then
                    found = true
                end
            end
        end
    end
    eq(found, true)
end

T['get_diff_data_git()']['triple plus outside of a hunk header will be processed as a real line'] = function()
    child.lua([[_G.fixture.diff = ...]], { git_diff_artifacts_in_content_git_diff_added })
    local result = child.lua_get([[(function()
        return M.get_diff_data_git(_G.fixture.diff)
    end)()]])
    local found = false
    for _, diff_data in ipairs(result) do
        for _, hunk in ipairs(diff_data.hunks) do
            for _, line in ipairs(hunk.lines) do
                -- expect this to be added
                if line.old_line_num == nil and line.line_type == 'added' and line.content == '++ this is a lua comment I am now adding' then
                    found = true
                end
            end
        end
    end
    eq(found, true)
end

T['get_diff_data_git()']['parses paths with mnemonic prefix (c/w)'] = function()
    child.lua([[_G.fixture.diff = ...]], { mnemonic_prefix_single_file_git_diff })
    local paths = child.lua_get([[(function()
        local d = M.get_diff_data_git(_G.fixture.diff)[1]
        return { old_path = d.old_path, new_path = d.new_path }
    end)()]])
    eq(paths.old_path, 'foo.lua')
    eq(paths.new_path, 'foo.lua')
end

T['get_diff_data_git()']['returns one entry per file with mnemonic prefix'] = function()
    child.lua([[_G.fixture.diff = ...]], { mnemonic_prefix_multi_file_git_diff })
    local result = child.lua_get([[(function()
        local data = M.get_diff_data_git(_G.fixture.diff)
        return { count = #data, first = data[1].new_path, second = data[2].new_path }
    end)()]])
    eq(result.count, 2)
    eq(result.first, 'foo.lua')
    eq(result.second, 'bar.py')
end

T['get_diff_data_git()']['handles binary file diff (no hunks)'] = function()
    child.lua([[_G.fixture.diff = ...]], { binary_file_git_diff })
    local result = child.lua_get([[(function()
        local data = M.get_diff_data_git(_G.fixture.diff)
        return { count = #data, new_path = data[1].new_path, hunk_count = #data[1].hunks }
    end)()]])
    eq(result.count, 1)
    eq(result.new_path, 'photo.jpg')
    eq(result.hunk_count, 0)
end

T['get_diff_data_git()']['handles mode-only change (no content lines to parse)'] = function()
    child.lua([[_G.fixture.diff = ...]], { mode_only_git_diff })
    local result = child.lua_get([[(function()
        local data = M.get_diff_data_git(_G.fixture.diff)
        -- mode-only changes have no content lines, so they're not added to result
        return { count = #data }
    end)()]])
    eq(result.count, 0)
end

T['get_diff_data_git()']['handles new file with mode and hunks'] = function()
    child.lua([[_G.fixture.diff = ...]], { new_file_mode_git_diff })
    local result = child.lua_get([[(function()
        local data = M.get_diff_data_git(_G.fixture.diff)
        return {
            count = #data,
            new_path = data[1] and data[1].new_path or nil,
            is_new = data[1] and data[1].new_file or nil,
            hunk_count = data[1] and #data[1].hunks or nil,
            new_mode = data[1] and data[1].new_file_mode or nil,
            line_count = data[1] and data[1].hunks[1] and #data[1].hunks[1].lines or 0
        }
    end)()]])
    eq(result.count, 1)
    eq(result.new_path, 'newfile.md')
    eq(result.is_new, true)
    eq(result.hunk_count, 1)
    eq(result.new_mode, '100644')
    eq(result.line_count, 1)
end

T['get_diff_data_git()']['new_file metadata does not bleed into the following regular file'] = function()
    child.lua([[_G.fixture.diff = ...]], { new_file_then_regular_git_diff })
    local result = child.lua_get([[(function()
        local data = M.get_diff_data_git(_G.fixture.diff)
        local second = data[2]
        return {
            count = #data,
            second_path = second and second.new_path or nil,
            second_new_file = second and second.new_file or nil,
            second_old_blob = second and second.old_blob_hash or nil,
            second_new_blob = second and second.new_blob_hash or nil,
        }
    end)()]])
    eq(result.count, 2)
    eq(result.second_path, 'existing.lua')
    -- new_file flag must not carry over from the first file
    eq(result.second_new_file, nil)
    -- blob hashes must come from the second file's index line, not the first file's
    eq(result.second_old_blob, 'bbb2222')
    eq(result.second_new_blob, 'ccc3333')
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_diff_data_git() - property based tests

local GetDiffDataGit = {}

-- Curated property test cases that cover different diff scenarios
GetDiffDataGit.get_diff_data_git__property_cases = {
    {
        name = 'single file with regular changes',
        diff = table.concat({
            "diff --git a/test.lua b/test.lua",
            "index abc1234..def5678 100644",
            "--- a/test.lua",
            "+++ b/test.lua",
            "@@ -1,2 +1,2 @@",
            "-old line",
            "+new line",
            " context",
        }, "\n"),
    },
    {
        name = 'multi-file diff',
        diff = table.concat({
            "diff --git a/file1.lua b/file1.lua",
            "index abc1234..def5678 100644",
            "--- a/file1.lua",
            "+++ b/file1.lua",
            "@@ -1,1 +1,1 @@",
            "-old",
            "+new",
            "diff --git a/file2.py b/file2.py",
            "index def5678..abc9012 100644",
            "--- a/file2.py",
            "+++ b/file2.py",
            "@@ -5,1 +5,1 @@",
            "-python",
            "+Python",
        }, "\n"),
    },
    {
        name = 'binary file',
        diff = table.concat({
            "diff --git a/image.png b/image.png",
            "index abc1234..def5678 100644",
            "Binary files a/image.png and b/image.png differ",
        }, "\n"),
    },
    {
        name = 'new file',
        diff = table.concat({
            "diff --git a/newfile.txt b/newfile.txt",
            "new file mode 100644",
            "index 0000000..abc1234 100644",
            "--- /dev/null",
            "+++ b/newfile.txt",
            "@@ -0,0 +1,1 @@",
            "+new content",
        }, "\n"),
    },
    {
        name = 'multiple hunks in single file',
        diff = table.concat({
            "diff --git a/code.lua b/code.lua",
            "index abc1234..def5678 100644",
            "--- a/code.lua",
            "+++ b/code.lua",
            "@@ -1,2 +1,2 @@",
            "-old1",
            "+new1",
            " context",
            "@@ -10,2 +10,2 @@",
            "-old2",
            "+new2",
            " context2",
        }, "\n"),
    },
}

GetDiffDataGit.properties = {}

-- Property: every entry in result has old_path and new_path set correctly
-- Returns true on success, or an error string on the first violation
GetDiffDataGit.properties.paths_are_parsed = [[(function()
    local diff = _G.fixture.diff
    local result = M.get_diff_data_git(diff)
    
    for idx, entry in ipairs(result) do
        -- For binary files and mode-only changes, paths should still be extracted from the diff header
        if not entry.new_path then
            return 'entry ' .. idx .. ': new_path is nil'
        end
        -- old_path may be nil for new files, but should exist otherwise
        if entry.new_path and not entry.old_path and not entry.new_file then
            -- Only new files can have nil old_path
            return 'entry ' .. idx .. ': old_path is nil but not a new file'
        end
    end
    return true
end)()]]

-- Property: every file has correct metadata (new_file, old_file_mode, new_file_mode, blob hashes)
-- Returns true on success
GetDiffDataGit.properties.metadata_is_captured = [[(function()
    local diff = _G.fixture.diff
    local result = M.get_diff_data_git(diff)
    
    for idx, entry in ipairs(result) do
        -- For new files, new_file should be true
        if entry.new_file == true then
            -- New files should have some hash information if they have hunks
            if #entry.hunks > 0 and not entry.new_blob_hash then
                return 'new file entry ' .. idx .. ' with hunks: new_blob_hash not captured'
            end
        end
        
        -- For regular files, both old and new blob hashes should be captured if there are hunks
        if not entry.new_file and #entry.hunks > 0 then
            if not entry.old_blob_hash then
                return 'entry ' .. idx .. ' with hunks: old_blob_hash not captured'
            end
            if not entry.new_blob_hash then
                return 'entry ' .. idx .. ' with hunks: new_blob_hash not captured'
            end
        end
        
        -- Blob hashes should match expected pattern (hex characters) if present
        if entry.old_blob_hash and not entry.old_blob_hash:match('^%x+$') then
            return 'entry ' .. idx .. ': old_blob_hash is not hex: ' .. entry.old_blob_hash
        end
        if entry.new_blob_hash and not entry.new_blob_hash:match('^%x+$') then
            return 'entry ' .. idx .. ': new_blob_hash is not hex: ' .. entry.new_blob_hash
        end
    end
    return true
end)()]]

-- Property: result array size matches number of files in the diff
-- Returns true on success
GetDiffDataGit.properties.correct_file_count = [[(function()
    local diff = _G.fixture.diff
    local lines = vim.split(diff, '\n', { plain = true })
    
    -- Count unique "diff --git" markers (one per file)
    local expected_count = 0
    for _, line in ipairs(lines) do
        if line:match('^diff %-%-git') then
            expected_count = expected_count + 1
        end
    end
    
    local result = M.get_diff_data_git(diff)
    if #result ~= expected_count then
        return 'expected ' .. expected_count .. ' files but got ' .. #result
    end
    return true
end)()]]

-- Property: hunks are empty for binary files and mode-only changes; non-empty for regular diffs
-- Returns true on success
GetDiffDataGit.properties.hunks_match_diff_type = [[(function()
    local diff = _G.fixture.diff
    local lines = vim.split(diff, '\n', { plain = true })
    local result = M.get_diff_data_git(diff)
    
    for idx, entry in ipairs(result) do
        local is_binary = false
        local has_hunk_headers = false
        
        -- Check if this file is binary
        for _, line in ipairs(lines) do
            if line:match('^Binary files') then
                is_binary = true
                break
            end
            if line:match('^@@') then
                has_hunk_headers = true
                break
            end
        end
        
        -- Binary files should have no hunks
        if is_binary and #entry.hunks > 0 then
            return 'binary file entry ' .. idx .. ' should have no hunks'
        end
        
        -- Files with hunk headers should have hunks
        if has_hunk_headers and #entry.hunks == 0 then
            return 'entry ' .. idx .. ' with hunk headers should have hunks'
        end
    end
    return true
end)()]]

-- Property: language is correctly inferred from file extension
-- Returns true on success
GetDiffDataGit.properties.language_inference = [[(function()
    local diff = _G.fixture.diff
    local result = M.get_diff_data_git(diff)
    
    for idx, entry in ipairs(result) do
        if not entry.new_path then goto continue end
        
        -- Check that language matches the extension (if we know about it)
        local ext = entry.new_path:match('%.([^%.]+)$')
        if ext then
            local expected_language = nil
            if ext == 'lua' then expected_language = 'lua'
            elseif ext == 'py' then expected_language = 'python'
            end
            
            if expected_language and entry.language ~= expected_language then
                return 'entry ' .. idx .. ' with extension .' .. ext .. ' has language=' .. tostring(entry.language) .. ' (expected ' .. expected_language .. ')'
            end
        end
        
        ::continue::
    end
    return true
end)()]]

T['get_diff_data_git() properties'] = new_set()
for prop_name, prop in pairs(GetDiffDataGit.properties) do
    for _, case in ipairs(GetDiffDataGit.get_diff_data_git__property_cases) do
        T['get_diff_data_git() properties'][prop_name .. ': ' .. case.name] = function()
            child.lua([[_G.fixture.diff = ...]], { case.diff })
            local result = child.lua_get(prop)
            eq(result, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- reconstruct_after_content() - example based tests

T['reconstruct_after_content()'] = new_set()

T['reconstruct_after_content()']['includes context and added lines, excludes removed'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_hunk_diff })
    -- context "local x = 1" (new=1), removed "local y = 2" (excluded),
    -- added "local y = 10" (new=2), context "local z = 3" (new=3)
    local result = child.lua_get([[(function()
        local data = M.get_diff_data(_G.fixture.diff, 'lua')
        return M.reconstruct_after_content(data)
    end)()]])
    eq(result, "local x = 1\nlocal y = 10\nlocal z = 3")
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- create_formatted_buffer() - example based tests

T['create_formatted_buffer()'] = new_set()

T['create_formatted_buffer()']['returns a valid buffer id'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_hunk_diff })
    local valid = child.lua_get([[(function()
        local data = M.get_diff_data(_G.fixture.diff, 'lua')
        local bufnr = M.create_formatted_buffer({ data })
        return vim.api.nvim_buf_is_valid(bufnr)
    end)()]])
    eq(valid, true)
end

T['create_formatted_buffer()']['buffer is not modifiable'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_hunk_diff })
    local modifiable = child.lua_get([[(function()
        local data = M.get_diff_data(_G.fixture.diff, 'lua')
        local bufnr = M.create_formatted_buffer({ data })
        return vim.api.nvim_get_option_value('modifiable', { buf = bufnr })
    end)()]])
    eq(modifiable, false)
end

T['create_formatted_buffer()']['buffer variables are set'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_hunk_diff })
    local result = child.lua_get([[(function()
        local data = M.get_diff_data(_G.fixture.diff, 'lua')
        local bufnr = M.create_formatted_buffer({ data })
        return {
            has_line_map      = vim.b[bufnr].delta_line_map ~= nil,
            has_diff_data_set = vim.b[bufnr].delta_diff_data_set ~= nil,
            has_artifacts     = vim.b[bufnr].delta_artifacts ~= nil,
        }
    end)()]])
    eq(result.has_line_map, true)
    eq(result.has_diff_data_set, true)
    eq(result.has_artifacts, true)
end

T['create_formatted_buffer()']['no title artifact when diff has no file paths'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_hunk_diff })
    -- get_diff_data produces DiffData with old_path=nil, new_path=nil
    local has_title = child.lua_get([[(function()
        local data = M.get_diff_data(_G.fixture.diff, 'lua')
        local bufnr = M.create_formatted_buffer({ data })
        for _, a in ipairs(vim.b[bufnr].delta_artifacts) do
            if a.type == 'title' then return true end
        end
        return false
    end)()]])
    eq(has_title, false)
end

T['create_formatted_buffer()']['title artifact present when diff has file paths'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_file_git_diff })
    -- get_diff_data_git produces DiffData with old_path and new_path set
    local has_title = child.lua_get([[(function()
        local data_set = M.get_diff_data_git(_G.fixture.diff)
        local bufnr = M.create_formatted_buffer(data_set)
        for _, a in ipairs(vim.b[bufnr].delta_artifacts) do
            if a.type == 'title' then return true end
        end
        return false
    end)()]])
    eq(has_title, true)
end

T['create_formatted_buffer()']['last line of buffer is not empty for a single-hunk diff'] = function()
    child.lua([[_G.fixture.diff = ...]], { single_hunk_diff })
    local last_line = child.lua_get([[(function()
        local data = M.get_diff_data(_G.fixture.diff, 'lua')
        local bufnr = M.create_formatted_buffer({ data })
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        return lines[#lines]
    end)()]])
    eq(last_line ~= '', true)
end

T['create_formatted_buffer()']['last line of buffer is not empty for a multi-hunk diff'] = function()
    child.lua([[_G.fixture.diff = ...]], { multi_hunk_diff })
    local last_line = child.lua_get([[(function()
        local data = M.get_diff_data(_G.fixture.diff, 'lua')
        local bufnr = M.create_formatted_buffer({ data })
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        return lines[#lines]
    end)()]])
    eq(last_line ~= '', true)
end

return T
