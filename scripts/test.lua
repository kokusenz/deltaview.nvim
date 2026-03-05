-- Run tests from command line
-- This script is meant to be run with: nvim --headless --noplugin -u scripts/minimal_init.lua -c "luafile scripts/test.lua"

-- Collect all test files
local test_files = vim.fn.glob('tests/**/test_*.lua', false, true)

if #test_files == 0 then
  print('No test files found')
  vim.cmd('cquit 1')
end

-- Run all tests
for _, file in ipairs(test_files) do
  print(string.format('\n=== Running %s ===\n', file))
  MiniTest.run_file(file)
end

vim.cmd('quit')
