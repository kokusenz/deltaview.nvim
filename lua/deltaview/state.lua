local M = {}
-- minimalist state variables, held in memory. Intended to be wiped out when neovim restarted.

--- stores the last used ref
--- @type string
M.diff_target_ref = 'HEAD'

--- stores the last used context
--- @type number
M.default_context = 3

return M
