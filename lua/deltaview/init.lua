local M = {}

--- @param opts DeltaViewOpts
M.setup = function(opts)
    require('deltaview.diff').setup(opts)
end

--- check if a buffer is a deltaview diff buffer
--- @param bufnr number|nil Buffer number to check (defaults to current buffer)
--- @return boolean True if the buffer is a deltaview buffer
M.is_deltaview_buffer = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local ok, is_deltaview = pcall(vim.api.nvim_buf_get_var, bufnr, 'is_deltaview')
    return ok and is_deltaview == true
end

return M
