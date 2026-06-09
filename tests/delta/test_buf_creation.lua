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
    if captured_prints == vim.NIL or captured_prints == nil then return end
    if #captured_prints > 0 then
        print('\n=== Child Neovim Print Statements ===')
        for i, msg in ipairs(captured_prints) do
            print(string.format('[%d] %s', i, msg))
        end
        print('=== End Print Statements ===\n')
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- fixtures

local git_diff_fixture = table.concat({
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

local patch_fixture = table.concat({
    "@@ -1,3 +1,3 @@",
    " local x = 1",
    "-local y = 2",
    "+local y = 10",
    " local z = 3",
}, "\n")

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup

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
                    build_git_diff_cmd_with_flags = function(_effective, _ref, _git_root, _path)
                        return { 'git', 'diff', 'HEAD' }
                    end,
                    get_git_root = function(_path) return '/fake/git/root' end,
                    get_window_width = function(_winid) return 80 end,
                    apply_highlights  = function(_bufnr, _highlights) end,
                    get_language_from_filename = function(_filename) return 'lua' end,
                    read_file_lines = function(_filepath) return {} end,
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
-- git_diff() - example based tests

T['git_diff()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                vim.system = function(_cmd, _opts)
                    return { wait = function() return { code = 0, stdout = '', stderr = '' } end }
                end
                M.get_diff_data_git = function(_diffstring) return { _G.fixture.fake_diff_data } end
                M.create_formatted_buffer = function(_data)
                    _G.fixture.create_formatted_buffer_called = true
                    _G.fixture.create_formatted_buffer_data = _data
                    -- return a real scratch buffer so vim.b[buf_id] assignments in git_diff succeed
                    local bufnr = vim.api.nvim_create_buf(false, true)
                    _G.fixture.fake_bufnr = bufnr
                    return bufnr
                end
                _G.fixture.fake_diff_data = { new_path = 'foo.lua', hunks = {} }
            ]])
        end,
    },
})

T['git_diff()']['returns nil when git produces no output'] = function()
    local is_nil = child.lua_get([[M.git_diff('HEAD', nil, {}) == nil]])
    eq(is_nil, true)
end

T['git_diff()']['returns the bufnr from create_formatted_buffer when diff has changes'] = function()
    child.lua([[
        vim.system = function(_cmd, _opts)
            return { wait = function() return { code = 0, stdout = 'some diff output', stderr = '' } end }
        end
        _G.fixture.returned_bufnr = M.git_diff('HEAD', nil, {})
    ]])
    local matches = child.lua_get([[_G.fixture.returned_bufnr == _G.fixture.fake_bufnr]])
    eq(matches, true)
end

T['git_diff()']['passes diff output to get_diff_data_git'] = function()
    child.lua([[
        _G.fixture.get_diff_data_git_input = nil
        local diff_output = ...
        vim.system = function(_cmd, _opts)
            return { wait = function() return { code = 0, stdout = diff_output, stderr = '' } end }
        end
        M.get_diff_data_git = function(diffstring)
            _G.fixture.get_diff_data_git_input = diffstring
            return { _G.fixture.fake_diff_data }
        end
    ]], { git_diff_fixture })
    child.lua([[M.git_diff('HEAD', nil, {})]])
    local input = child.lua_get([[_G.fixture.get_diff_data_git_input]])
    eq(input, git_diff_fixture)
end

T['git_diff()']['sets git_root buffer variable on the returned buffer'] = function()
    child.lua([[
        vim.system = function(_cmd, _opts)
            return { wait = function() return { code = 0, stdout = 'some diff output', stderr = '' } end }
        end
        M.git_diff('HEAD', nil, {})
    ]])
    local git_root_set = child.lua_get([[vim.b[_G.fixture.fake_bufnr].git_root ~= nil]])
    eq(git_root_set, true)
end

T['git_diff()']['throws an error when git diff returns a failing exit code'] = function()
    child.lua([[
        vim.system = function(_cmd, _opts)
            return { wait = function() return { code = 128, stdout = '', stderr = 'fatal: not a repo' } end }
        end
    ]])
    local ok = child.lua_get([[(function()
        local ok, _ = pcall(M.git_diff, 'HEAD', nil, {})
        return ok
    end)()]])
    eq(ok, false)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- text_diff() - example based tests

T['text_diff()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                M.get_diff_data = function(_diffstring, _language)
                    _G.fixture.get_diff_data_called = true
                    return _G.fixture.fake_diff_data
                end
                M.create_formatted_buffer = function(_data)
                    _G.fixture.create_formatted_buffer_called = true
                    return _G.fixture.fake_bufnr
                end
                _G.fixture.fake_bufnr = 42
                _G.fixture.fake_diff_data = { language = 'lua', hunks = {} }
            ]])
        end,
    },
})

T['text_diff()']['returns the bufnr from create_formatted_buffer'] = function()
    local bufnr = child.lua_get([[M.text_diff('local x = 1', 'local x = 2', 'lua', {})]])
    eq(bufnr, 42)
end

T['text_diff()']['passes diff output to get_diff_data'] = function()
    child.lua([[
        _G.fixture.get_diff_data_input = nil
        M.get_diff_data = function(diffstring, _language)
            _G.fixture.get_diff_data_input = diffstring
            return _G.fixture.fake_diff_data
        end
    ]])
    child.lua([[M.text_diff('local x = 1\n', 'local x = 2\n', 'lua', {})]])
    local input = child.lua_get([[_G.fixture.get_diff_data_input]])
    eq(input ~= nil, true)
end

T['text_diff()']['falls back to vim.diff when vim.text is unavailable'] = function()
    local used_vim_diff = child.lua_get([[(function()
        local called = false
        vim.text = nil
        vim.diff = function(_s1, _s2, _opts)
            called = true
            return '@@ -1,1 +1,1 @@\n-local x = 1\n+local x = 2\n'
        end
        M.text_diff('local x = 1', 'local x = 2', 'lua', {})
        return called
    end)()]])
    eq(used_vim_diff, true)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- patch_diff() - example based tests

T['patch_diff()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                M.get_diff_data = function(_diffstring, _language)
                    return _G.fixture.fake_diff_data
                end
                M.get_diff_data_git = function(_diffstring)
                    return { _G.fixture.fake_diff_data }
                end
                M.create_formatted_buffer = function(_data)
                    _G.fixture.create_formatted_buffer_data = _data
                    return _G.fixture.fake_bufnr
                end
                _G.fixture.fake_bufnr = 42
                _G.fixture.fake_diff_data = { new_path = 'foo.lua', hunks = {} }
            ]])
        end,
    },
})

T['patch_diff()']['returns nil when diffstring is empty'] = function()
    local is_nil = child.lua_get([[M.patch_diff('', false, 'lua', {}) == nil]])
    eq(is_nil, true)
end

T['patch_diff()']['plain unified diff: returns bufnr from create_formatted_buffer'] = function()
    child.lua([[_G.fixture.diff_input = ...]], { patch_fixture })
    local bufnr = child.lua_get([[M.patch_diff(_G.fixture.diff_input, false, 'lua', {})]])
    eq(bufnr, 42)
end

T['patch_diff()']['plain unified diff: wraps result of get_diff_data in a table for create_formatted_buffer'] = function()
    child.lua([[_G.fixture.diff_input = ...]], { patch_fixture })
    child.lua([[M.patch_diff(_G.fixture.diff_input, false, 'lua', {})]])
    local data_is_table = child.lua_get([[type(_G.fixture.create_formatted_buffer_data) == 'table']])
    eq(data_is_table, true)
end

T['patch_diff()']['git diff format: returns bufnr from create_formatted_buffer'] = function()
    child.lua([[_G.fixture.diff_input = ...]], { git_diff_fixture })
    local bufnr = child.lua_get([[M.patch_diff(_G.fixture.diff_input, true, nil, {})]])
    eq(bufnr, 42)
end

T['patch_diff()']['git diff format: passes diffstring to get_diff_data_git'] = function()
    child.lua([[
        _G.fixture.get_diff_data_git_input = nil
        M.get_diff_data_git = function(diffstring)
            _G.fixture.get_diff_data_git_input = diffstring
            return { _G.fixture.fake_diff_data }
        end
        _G.fixture.diff_input = ...
    ]], { git_diff_fixture })
    child.lua([[M.patch_diff(_G.fixture.diff_input, true, nil, {})]])
    local input = child.lua_get([[_G.fixture.get_diff_data_git_input]])
    eq(input, git_diff_fixture)
end

return T
