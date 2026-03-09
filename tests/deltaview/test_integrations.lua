local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- Utility

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
-- Test suite

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[M = require('deltaview')]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- `:DeltaView` integration

local setup_tmpdir_git_repo = [[
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    vim.fn.system('git -C ' .. tmpdir .. ' init')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.email "test@test.com"')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.name "Test"')
    local f = io.open(tmpdir .. '/test.lua', 'w')
    f:write('local x = 1\nlocal y = 2\n')
    f:close()
    vim.fn.system('git -C ' .. tmpdir .. ' add test.lua')
    vim.fn.system('git -C ' .. tmpdir .. ' commit -m "initial"')
    local f2 = io.open(tmpdir .. '/test.lua', 'w')
    f2:write('local x = 1\nlocal y = 99\n')
    f2:close()
    vim.cmd('cd ' .. tmpdir)
    vim.cmd('edit ' .. tmpdir .. '/test.lua')
]]

-- Reproduces the file state from broken-delta-lua.patch: the committed (HEAD) version has
-- get_filenames_from_sortedfiles with a `@return table` doc comment and no reorder function.
-- The working-tree version has `@return string[]` and adds reorder_current_file_to_top.
-- This specific change was observed to cause git diff and vim.text.diff to produce different
-- edit sequences, exercising the validator fallback path inside open_git_diff_buffer.
local setup_tmpdir_patch_scenario = [[
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    vim.fn.system('git -C ' .. tmpdir .. ' init')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.email "test@test.com"')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.name "Test"')

    local before_lines = {
        '--- TODO unit test',
        '--- @param sorted_files SortedFile[]',
        '--- @return table list of file names',
        'M.get_filenames_from_sortedfiles = function(sorted_files)',
        '    local files = {}',
        '    for _, value in ipairs(sorted_files) do',
        '        table.insert(files, value.name)',
        '    end',
        '    return files',
        'end',
        '',
        '--- TODO unit test',
        '--- Read file contents without opening a vim buffer',
        '--- @param filepath string Full path to the file',
        '--- @return table|nil lines Array of lines from the file, or nil if error',
        'M.read_file_lines = function(filepath)',
        '    return nil',
        'end',
    }
    local f = io.open(tmpdir .. '/utils.lua', 'w')
    f:write(table.concat(before_lines, '\n') .. '\n')
    f:close()
    vim.fn.system('git -C ' .. tmpdir .. ' add utils.lua')
    vim.fn.system('git -C ' .. tmpdir .. ' commit -m "initial"')

    local after_lines = {
        '--- TODO unit test',
        '--- @param sorted_files SortedFile[]',
        '--- @return string[] list of file names',
        'M.get_filenames_from_sortedfiles = function(sorted_files)',
        '    local files = {}',
        '    for _, value in ipairs(sorted_files) do',
        '        table.insert(files, value.name)',
        '    end',
        '    return files',
        'end',
        '',
        '--- TODO unit test',
        '--- tries to reorder the file list to put the current file at the top, if current buffer is in the list.',
        "--- if not, it just returns the same list",
        '--- @param sorted_file_names string[]',
        "--- @return string[] list, boolean flag if reordering happened, false if didn't",
        'M.reorder_current_file_to_top = function(sorted_file_names)',
        '    local files = {}',
        "    local filepath = vim.trim(vim.fn.expand('%:p'))",
        '    local found = false',
        '    for _, value in ipairs(sorted_file_names) do',
        '        if M.git_rel_to_abs(value) == filepath then',
        '            table.insert(files, 1, value)',
        '            found = true',
        '        else',
        '            table.insert(files, value)',
        '        end',
        '    end',
        '    return files, found',
        'end',
        '',
        '--- TODO unit test',
        '--- Read file contents without opening a vim buffer',
        '--- @param filepath string Full path to the file',
        '--- @return table|nil lines Array of lines from the file, or nil if error',
        'M.read_file_lines = function(filepath)',
        '    return nil',
        'end',
    }
    local f2 = io.open(tmpdir .. '/utils.lua', 'w')
    f2:write(table.concat(after_lines, '\n') .. '\n')
    f2:close()

    vim.cmd('cd ' .. tmpdir)
    vim.cmd('edit ' .. tmpdir .. '/utils.lua')
]]

T['DeltaView integration'] = new_set({
    hooks = {
        pre_case = function()
            child.lua(setup_tmpdir_git_repo)
        end,
    },
})

T['DeltaView integration']['happy path: creates a delta buffer for a tracked file with changes'] = function()
    child.cmd('DeltaView HEAD')
    local has_diff_data  = child.lua_get('vim.b[vim.api.nvim_get_current_buf()].delta_diff_data_set ~= nil')
    local has_parsed     = child.lua_get('vim.b[vim.api.nvim_get_current_buf()].no_context_delta_diff_data_set ~= nil')
    local buf_on_window  = child.lua_get('vim.api.nvim_win_get_buf(0) == vim.api.nvim_get_current_buf()')
    local name           = child.lua_get('vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())')
    eq(has_diff_data, true)
    eq(has_parsed, true)
    eq(buf_on_window, true)
    eq(name:find('HEAD',     1, true) ~= nil, true)
    eq(name:find('test.lua', 1, true) ~= nil, true)
    eq(name:match('%d+')    ~= nil, true)
end

T['DeltaView integration']['fallback path: git diff vs vim.text.diff mismatch (patch scenario) recovers and creates a delta buffer'] = function()
    child.lua(setup_tmpdir_patch_scenario)
    child.cmd('DeltaView HEAD')
    local has_diff_data = child.lua_get('vim.b[vim.api.nvim_get_current_buf()].delta_diff_data_set ~= nil')
    local has_parsed    = child.lua_get('vim.b[vim.api.nvim_get_current_buf()].no_context_delta_diff_data_set ~= nil')
    local buf_on_window = child.lua_get('vim.api.nvim_win_get_buf(0) == vim.api.nvim_get_current_buf()')
    local name          = child.lua_get('vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())')
    eq(has_diff_data, true)
    eq(has_parsed, true)
    eq(buf_on_window, true)
    eq(name:find('HEAD',      1, true) ~= nil, true)
    eq(name:find('utils.lua', 1, true) ~= nil, true)
    eq(name:match('%d+')      ~= nil, true)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- `:DeltaMenu` integration

-- creates N tracked files with working-tree changes; each file{i}.lua starts as 'local x = i'
-- and is modified to 'local x = i*10' after the initial commit
local setup_tmpdir_git_repo_n_files = [[
    local n = ...
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    vim.fn.system('git -C ' .. tmpdir .. ' init')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.email "test@test.com"')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.name "Test"')
    for i = 1, n do
        local fname = 'file' .. i .. '.lua'
        local f = io.open(tmpdir .. '/' .. fname, 'w')
        f:write('local x = ' .. i .. '\n')
        f:close()
        vim.fn.system('git -C ' .. tmpdir .. ' add ' .. fname)
    end
    vim.fn.system('git -C ' .. tmpdir .. ' commit -m "initial"')
    for i = 1, n do
        local fname = 'file' .. i .. '.lua'
        local f = io.open(tmpdir .. '/' .. fname, 'w')
        f:write('local x = ' .. (i * 10) .. '\n')
        f:close()
    end
    vim.cmd('cd ' .. tmpdir)
]]

T['DeltaMenu integration'] = new_set()

T['DeltaMenu integration']['quickselect path: selecting a file opens a delta buffer'] = function()
    child.lua([[
        M.setup({fzf_threshold = 6})
    ]])
    child.lua(setup_tmpdir_git_repo_n_files, { 3 })
    child.cmd('DeltaMenu HEAD')
    child.type_keys('<CR>')
    local has_diff_data = child.lua_get('vim.b[vim.api.nvim_get_current_buf()].delta_diff_data_set ~= nil')
    local has_parsed    = child.lua_get('vim.b[vim.api.nvim_get_current_buf()].no_context_delta_diff_data_set ~= nil')
    eq(has_diff_data, true)
    eq(has_parsed, true)
end

T['DeltaMenu integration']['fzf path: opens a terminal window'] = function()
    child.lua([[
        M.setup({fzf_threshold = 6})
    ]])
    child.lua(setup_tmpdir_git_repo_n_files, { 7 })
    child.cmd('DeltaMenu HEAD')
    local has_terminal = child.lua_get([[
        (function()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.bo[buf].buftype == 'terminal' then return true end
            end
            return false
        end)()
    ]])
    eq(has_terminal, true)
end

return T
