-- Add current directory to 'runtimepath' to be able to use 'lua' files
-- Capture the absolute project root now, before any test fixture changes cwd.
local project_root = vim.fn.getcwd()
vim.cmd('set rtp+=' .. project_root)

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  -- mini.test
  vim.cmd('set rtp+=' .. project_root .. '/deps/mini.test')

  -- Add deps/ so treesitter finds compiled parsers in deps/parser/
  vim.cmd('set rtp+=' .. project_root .. '/deps')

  -- delta.lua
  vim.cmd('set rtp+=' .. project_root .. '/deps/delta')

  -- fzf
  vim.cmd('set rtp+=' .. project_root .. '/deps/fzf')

  -- fzf_lua
  vim.cmd('set rtp+=' .. project_root .. '/deps/fzf_lua')

  -- telescope
  vim.cmd('set rtp+=' .. project_root .. '/deps/telescope')

  -- plenary (telescope dependency)
  vim.cmd('set rtp+=' .. project_root .. '/deps/plenary')

  -- Set up 'mini.test'
  require('mini.test').setup()
end
