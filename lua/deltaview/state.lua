local M = {}
-- minimalist state variables, held in memory. Intended to be wiped out when neovim restarted.

--- @type DiffedFiles
M.diffed_files = { files = nil, cur_idx = nil }

--- stores the last used ref for future calls
M.diff_target_ref = nil

--- stores the last used context for future delta calls
M.default_context = nil

--- enables the user to go to "next diff in menu" if the current diff was opened via the menu.
--- @class DiffedFiles
--- @field files table | nil
--- @field cur_idx number | nil

return M
