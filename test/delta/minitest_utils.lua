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
            child.lua([[M = require('delta.utils')]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_git_root() - example based tests

T['get_git_root()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                vim.fn.isdirectory = function(_) return 0 end
                vim.fn.fnamemodify = function(path, _) return path end
                vim.system = function(_cmd, _opts)
                    return { wait = function()
                        return { code = 0, stdout = '/fake/git/root\n', stderr = '' }
                    end }
                end
            ]])
        end,
    },
})

T['get_git_root()']['returns trimmed stdout when git succeeds (code 0)'] = function()
    local result = child.lua_get([[(function()
        local ok, val = pcall(M.get_git_root, '/some/file.lua')
        if not ok then return nil end
        return val
    end)()]])

    eq(result, '/fake/git/root')
end

T['get_git_root()']['uses fnamemodify to get parent dir when path is not a directory'] = function()
    child.lua([[
        _G.fixture.fnamemodify_args = nil
        vim.fn.isdirectory = function(_) return 0 end
        vim.fn.fnamemodify = function(path, mod)
            _G.fixture.fnamemodify_args = { path = path, mod = mod }
            return '/parent/dir'
        end
    ]])

    child.lua([[ pcall(M.get_git_root, '/some/file.lua') ]])

    local args = child.lua_get([[_G.fixture.fnamemodify_args]])
    eq(args.path, '/some/file.lua')
    eq(args.mod, ':h')
end

T['get_git_root()']['uses path directly when it is a directory'] = function()
    child.lua([[
        _G.fixture.system_dir = nil
        vim.fn.isdirectory = function(_) return 1 end
        vim.system = function(cmd, _opts)
            _G.fixture.system_dir = cmd[3]  -- git -C <dir> rev-parse ...
            return { wait = function()
                return { code = 0, stdout = '/fake/git/root\n', stderr = '' }
            end }
        end
    ]])

    child.lua([[ pcall(M.get_git_root, '/some/dir') ]])

    local dir = child.lua_get([[_G.fixture.system_dir]])
    eq(dir, '/some/dir')
end

T['get_git_root()']['asserts and throws when git returns a non-zero exit code'] = function()
    child.lua([[
        vim.system = function(_cmd, _opts)
            return { wait = function()
                return { code = 128, stdout = '', stderr = 'not a git repo' }
            end }
        end
    ]])

    local ok = child.lua_get([[(function()
        local ok, _ = pcall(M.get_git_root, '/some/file.lua')
        return ok
    end)()]])

    eq(ok, false)
end

T['get_git_root()']['asserts and throws when git returns code 1'] = function()
    child.lua([[
        vim.system = function(_cmd, _opts)
            return { wait = function()
                return { code = 1, stdout = '', stderr = '' }
            end }
        end
    ]])

    local ok = child.lua_get([[(function()
        local ok, _ = pcall(M.get_git_root, '/some/file.lua')
        return ok
    end)()]])

    eq(ok, false)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- build_git_diff_cmd_with_flags() - example based tests

T['build_git_diff_cmd_with_flags()'] = new_set()

T['build_git_diff_cmd_with_flags()']['returns base command with --full-index always present'] = function()
    local result = child.lua_get([[(function()
        return M.build_git_diff_cmd_with_flags({}, 'HEAD', '/repo')
    end)()]])

    eq(result[1], 'git')
    eq(result[2], '-C')
    eq(result[3], '/repo')
    eq(result[4], 'diff')
    eq(result[5], '--no-ext-diff')
    eq(result[6], '--full-index')
end

T['build_git_diff_cmd_with_flags()']['inserts -U<n> context flag when context is set'] = function()
    eq(child.lua_get([[
        (function()
            local cmd = M.build_git_diff_cmd_with_flags({ context = 5 }, 'HEAD', '/repo')
            for _, v in ipairs(cmd) do
                if v == '-U5' then return true end
            end
            return false
        end)()
    ]]), true)
end

T['build_git_diff_cmd_with_flags()']['omits context flag when context is nil'] = function()
    local result = child.lua_get([[
        (function()
            local cmd = M.build_git_diff_cmd_with_flags({}, 'HEAD', '/repo')
            for _, v in ipairs(cmd) do
                if v:sub(1, 2) == '-U' then return false end
            end
            return true
        end)()
    ]])

    eq(result, true)
end

T['build_git_diff_cmd_with_flags()']['includes ref when new_file is not true and ref is provided'] = function()
    local result = child.lua_get([[(function()
        return M.build_git_diff_cmd_with_flags({}, 'HEAD~1', '/repo')
    end)()]])

    local found = false
    for _, v in ipairs(result) do
        if v == 'HEAD~1' then found = true end
    end
    eq(found, true)
end

T['build_git_diff_cmd_with_flags()']['excludes ref and adds --no-index when new_file is true'] = function()
    local result = child.lua_get([[(function()
        return M.build_git_diff_cmd_with_flags({ new_file = true }, 'HEAD', '/repo')
    end)()]])

    local has_ref = false
    local has_no_index = false
    for _, v in ipairs(result) do
        if v == 'HEAD' then has_ref = true end
        if v == '--no-index' then has_no_index = true end
    end
    eq(has_ref, false)
    eq(has_no_index, true)
end

T['build_git_diff_cmd_with_flags()']['appends -- and path when path is provided'] = function()
    local result = child.lua_get([[(function()
        return M.build_git_diff_cmd_with_flags({}, 'HEAD', '/repo', '/repo/foo.lua')
    end)()]])

    local n = #result
    eq(result[n], '/repo/foo.lua')
    eq(result[n - 1], '--')
end

T['build_git_diff_cmd_with_flags()']['inserts /dev/null before path when new_file is true'] = function()
    local result = child.lua_get([[(function()
        return M.build_git_diff_cmd_with_flags({ new_file = true }, nil, '/repo', '/repo/new.lua')
    end)()]])

    local n = #result
    eq(result[n], '/repo/new.lua')
    eq(result[n - 1], '/dev/null')
    eq(result[n - 2], '--')
end

T['build_git_diff_cmd_with_flags()']['omits -- separator and path when path is nil'] = function()
    local result = child.lua_get([[(function()
        return M.build_git_diff_cmd_with_flags({}, 'HEAD', '/repo', nil)
    end)()]])

    for _, v in ipairs(result) do
        eq(v == '--', false)
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_window_width() - example based tests

T['get_window_width()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                local bufnr = vim.api.nvim_create_buf(true, true)
                vim.api.nvim_set_current_buf(bufnr)
                _G.fixture.bufnr = bufnr
                _G.fixture.winnr = vim.api.nvim_get_current_win()
            ]])
        end,
    },
})

T['get_window_width()']['returns a number when winid is 0'] = function()
    local result = child.lua_get('M.get_window_width(0)')
    eq(type(result), 'number')
end

T['get_window_width()']['winid 0 gives the same result as the explicit current win id'] = function()
    local result = child.lua_get([[(function()
        local with_zero = M.get_window_width(0)
        local with_id   = M.get_window_width(vim.api.nvim_get_current_win())
        return with_zero == with_id
    end)()]])
    eq(result, true)
end

T['get_window_width()']['result equals getwininfo width minus textoff'] = function()
    local result = child.lua_get([[(function()
        local winnr      = vim.api.nvim_get_current_win()
        local calculated = M.get_window_width(winnr)
        local info       = vim.fn.getwininfo(winnr)[1]
        return calculated == (info.width - info.textoff)
    end)()]])
    eq(result, true)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_window_width() - property based tests

local GetWindowWidth = {}

GetWindowWidth.get_inputs = function(_case)
    local inputs = {}
    local foldcolumn_vals     = { '1', 'auto', 'auto:3' }
    local signcolumn_vals     = { 'no', 'yes', 'auto' }
    local number_vals         = { false, true }
    local relativenumber_vals = { false, true }

    for _, fc  in ipairs(foldcolumn_vals) do
        for _, sc  in ipairs(signcolumn_vals) do
            for _, nu  in ipairs(number_vals) do
                for _, rnu in ipairs(relativenumber_vals) do
                    table.insert(inputs, {
                        foldcolumn     = fc,
                        signcolumn     = sc,
                        number         = nu,
                        relativenumber = rnu,
                    })
                end
            end
        end
    end
    return inputs
end

GetWindowWidth.get_window_width__property_cases = {
    { name = 'all option permutations', buf_contents = {}, get_inputs = GetWindowWidth.get_inputs },
}

GetWindowWidth.properties = {}

GetWindowWidth.properties.result_equals_width_minus_textoff = [[(function()
    local inputs = _G.fixture.inputs
    local winnr  = _G.fixture.winnr
    for _, input in ipairs(inputs) do
        vim.api.nvim_set_option_value('foldcolumn',     input.foldcolumn,     { win = winnr })
        vim.api.nvim_set_option_value('signcolumn',     input.signcolumn,     { win = winnr })
        vim.api.nvim_set_option_value('number',         input.number,         { win = winnr })
        vim.api.nvim_set_option_value('relativenumber', input.relativenumber, { win = winnr })
        local result = M.get_window_width(winnr)
        local info   = vim.fn.getwininfo(winnr)[1]
        if result ~= (info.width - info.textoff) then return false end
    end
    return true
end)()]]

T['get_window_width() properties'] = new_set()
for prop_name, prop in pairs(GetWindowWidth.properties) do
    for _, case in ipairs(GetWindowWidth.get_window_width__property_cases) do
        T['get_window_width() properties'][prop_name .. ': ' .. case.name] = function()
            child.lua([[
                local buf_contents = ...
                local bufnr = vim.api.nvim_create_buf(true, true)
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, buf_contents)
                vim.api.nvim_set_current_buf(bufnr)
                _G.fixture.bufnr = bufnr
                _G.fixture.winnr = vim.api.nvim_get_current_win()
            ]], { case.buf_contents })
            child.lua([[_G.fixture.inputs = ...]], { case.get_inputs(case) })
            local result = child.lua_get(prop)
            eq(result, true)
        end
    end
end

return T
