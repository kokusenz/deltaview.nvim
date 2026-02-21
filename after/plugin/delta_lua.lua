local config = require('deltaview.config')

if config.options.use_deltalua then
    if Delta == nil then
        vim.notify(
        'delta.lua is not installed. Please install to access new features like treesitter syntax highlighting and more.',
            vim.log.levels.WARN)
        config.options.use_deltalua = false
    end
end
