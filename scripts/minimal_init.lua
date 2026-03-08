-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  -- mini.test
  vim.cmd('set rtp+=deps/mini.test')

  -- Add deps/ so treesitter finds compiled parsers in deps/parser/
  vim.cmd('set rtp+=deps')

  -- delta.lua
  vim.cmd('set rtp+=deps/delta')

  -- fzf
  vim.cmd('set rtp+=deps/fzf')

  -- fzf_lua
  vim.cmd('set rtp+=deps/fzf_lua')

  -- telescope
  vim.cmd('set rtp+=deps/telescope')

  -- Set up 'mini.test'
  require('mini.test').setup()
end
