local config = require('deltaview.config')

if config.options.use_legacy_delta == false then
    if Delta == nil then
        vim.notify(
        'delta.lua is not installed. Please install to access new features like treesitter syntax highlighting and more. Setting up deltaview.nvim with v0.1.2.',
            vim.log.levels.WARN)
        config.options.use_legacy_delta = true
        require('deltaview').setup({})
    end
end
