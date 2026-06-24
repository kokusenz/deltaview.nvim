-- Run tests from command line
-- This script is meant to be run with: nvim --headless --noplugin -u scripts/minimal_init.lua -c "luafile scripts/test.lua"

-- Collect all test files
local minitest_files = vim.fn.glob('test/**/minitest_*.lua', false, true)

if #minitest_files == 0 then
  print('No minitest files found')
  vim.cmd('cquit 1')
end

-- Run all tests
for _, file in ipairs(minitest_files) do
  print(string.format('\n=== Running %s ===\n', file))
  MiniTest.run_file(file)
end

vim.cmd('quit')
