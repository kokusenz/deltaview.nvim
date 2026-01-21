local M = {}

--- @param opts DeltaViewOpts
M.setup = function(opts)
    require('deltaview.config').setup(opts)
    require('deltaview.commands').setup()
end

--- check if a buffer is a deltaview diff buffer
--- @param bufnr number|nil Buffer number to check (defaults to current buffer)
--- @return boolean True if the buffer is a deltaview buffer
M.is_deltaview_buffer = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local ok, is_deltaview = pcall(vim.api.nvim_buf_get_var, bufnr, 'is_deltaview')
    return ok and is_deltaview == true
end

--- use the DeltaView picker as default vim ui select ui. Comes with the default labeling strategy, keybinds, and the expanded opts to use.
M.register_ui_select = function()
    vim.ui.select = require('deltaview.selector').ui_select
end

return M
