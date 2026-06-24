local lunatest_files = {}
local handle = io.popen('find test -name "lunatest_*.lua"')
if handle then
  for line in handle:lines() do
    table.insert(lunatest_files, line)
  end
  handle:close()
end

if #lunatest_files == 0 then
  print('No lunatest files found')
  os.exit(1)
end

-- Run all tests
for _, file in ipairs(lunatest_files) do
  print(string.format('\n=== Running %s ===\n', file))
  os.execute('lua ' .. file)
end
