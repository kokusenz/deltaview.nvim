local config = require('deltaview.config')

if config.options.use_legacy_delta == false then
    if Delta == nil then
        vim.notify(
        'delta.lua is not installed. Please install to access new features like treesitter syntax highlighting and more.',
            vim.log.levels.WARN)
        config.options.use_legacy_delta = true
    end
end
