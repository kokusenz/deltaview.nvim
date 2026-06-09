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
            child.lua([[R = require('delta.statuscolumn')]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup_delta_statuscolumn() - example based tests

T['setup_delta_statuscolumn()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                local bufnr = vim.api.nvim_create_buf(false, true)
                vim.api.nvim_win_get_buf = function() return bufnr end
                _G.fixture.bufnr = bufnr
            ]])
        end
    },
})

T['setup_delta_statuscolumn()']['sets statuscolumn option value'] = function()
    child.lua([[
        _G.fixture.option_value_arg_1 = nil
        _G.fixture.option_value_arg_2 = nil
        _G.fixture.option_value_arg_3 = nil
        vim.api.nvim_set_option_value = function(arg1, arg2, arg3)
            _G.fixture.option_value_arg_1 = arg1
            _G.fixture.option_value_arg_2 = arg2
            _G.fixture.option_value_arg_3 = arg3
        end
    ]])
    local valid = child.lua_get([[(function()
        M.setup_delta_statuscolumn(_G.fixture.bufnr)
        local arg1_match = _G.fixture.option_value_arg_1 == 'statuscolumn'
        local arg2_match = _G.fixture.option_value_arg_2 == '%{%v:lua.require("delta.statuscolumn").render(v:lnum)%}'
        local arg3_match = _G.fixture.option_value_arg_3.win == 0
        return arg1_match and arg2_match and arg3_match
    end)()]])

    eq(valid, true)
end

T['setup_delta_statuscolumn()']['calls vim.cmd(\'redraw\')'] = function()
    local valid = child.lua_get([[(function()
        local redraw_called = false
        vim.cmd = function(cmd)
            if cmd == 'redraw' then redraw_called = true end
        end
        M.setup_delta_statuscolumn(_G.fixture.bufnr)
        return redraw_called
    end)()]])

    eq(valid, true)
end

T['setup_delta_statuscolumn()']['restores statuscolumn on BufUnload'] = function()
    local valid = child.lua_get([[(function()
        local autocmd_callback = nil
        vim.api.nvim_create_autocmd = function(event, opts)
            if event == 'BufUnload' then
                autocmd_callback = opts.callback
            end
        end
        vim.api.nvim_win_is_valid = function() return true end
        local restored_arg1 = nil
        local restored_arg2 = nil
        local restored_arg3 = nil
        vim.api.nvim_get_option_value = function() return 'original_statuscolumn' end
        vim.api.nvim_set_option_value = function(arg1, arg2, arg3)
            restored_arg1 = arg1
            restored_arg2 = arg2
            restored_arg3 = arg3
        end
        M.setup_delta_statuscolumn(_G.fixture.bufnr)
        -- simulate BufUnload firing
        autocmd_callback()
        local event_match = restored_arg1 == 'statuscolumn'
        local value_match = restored_arg2 == 'original_statuscolumn'
        local win_match = restored_arg3 ~= nil and restored_arg3.win ~= nil
        return event_match and value_match and win_match
    end)()]])

    eq(valid, true)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- render() - example based tests

T['render()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                local bufnr = vim.api.nvim_create_buf(false, true)
                _G.fixture.bufnr = bufnr
                vim.api.nvim_get_current_buf = function() return bufnr end
            ]])
        end,
    },
})

T['render()']['renders a regular line number when no line_map'] = function()
    local output = child.lua_get([[(
        function()
            return R.render(3)
        end
    )()]])
    eq(output, '   3 ')
end

T['render()']['renders no line number when lnum not in line_map'] = function()
    local output = child.lua_get([[(
        function()
            vim.b[_G.fixture.bufnr].delta_line_map = {}
            return R.render(1)
        end
    )()]])
    eq(output, '')
end

T['render()']['renders added line with highlight'] = function()
    local output = child.lua_get([[(
        function()
            vim.b[_G.fixture.bufnr].delta_line_map = {
                [1] = { type = 'added', old = nil, new = 5 }
            }
            return R.render(1)
        end
    )()]])
    eq(output, '%#DeltaLineNrAdded#     ⋮ 5   %*')
end

T['render()']['renders removed line with highlight'] = function()
    local output = child.lua_get([[(
        function()
            vim.b[_G.fixture.bufnr].delta_line_map = {
                [1] = { type = 'removed', old = 3, new = nil }
            }
            return R.render(1)
        end
    )()]])
    eq(output, '%#DeltaLineNrRemoved#   3 ⋮     %*')
end

T['render()']['renders context line with highlight'] = function()
    eq(child.lua_get([[(
        function()
            vim.b[_G.fixture.bufnr].delta_line_map = {
                [1] = { type = 'context', old = 1, new = 1 }
            }
            return R.render(1)
        end
    )()]]), '%#DeltaLineNrContext#   1 ⋮ 1   %*')
end

T['render()']['renders header line without highlight'] = function()
    eq(child.lua_get([[(
        function()
            vim.b[_G.fixture.bufnr].delta_line_map = {
                [1] = { type = 'header', old = nil, new = nil }
            }
            return R.render(1)
        end
    )()]]), '     ⋮     ')
end


return T
