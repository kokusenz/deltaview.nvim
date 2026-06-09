_G.Delta = setmetatable({}, {
    __index = function(proxy, k)
        vim.notify(
            '[delta.lua] The Delta global is deprecated and will be removed in the near future. delta.lua is now lazy loaded. If you are using deltaview.nvim, please ensure you are using v0.2.2 or later. If you are a plugin consumer, please use require("delta") instead.',
            vim.log.levels.WARN
        )
        local mod = require('delta')
        -- replace both _G.Delta and any local captures of the proxy so the
        -- warning fires only once regardless of how Delta was captured
        setmetatable(proxy, { __index = mod })
        _G.Delta = mod
        return mod[k]
    end
})
