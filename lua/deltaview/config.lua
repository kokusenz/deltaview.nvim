local M = {}

--- @class ViewConfig
--- @field dot string
--- @field circle string
--- @field vs string
--- @field next string
--- @field prev string

--- @class ViewConfig
M.basic_viewconfig = {
    dot = "·",
    circle = "•",
    vs = "comparing to",
    next = "->",
    prev = "<-"
}

--- @class ViewConfig
M.nerdfont_viewconfig = {
    dot = "󰧟", -- nf-md-circle_small
    circle = "󰧞", -- nf-md-circle_medium
    vs = "", -- nf-seti-git
    next = "󰁕", -- nf-md-arrow_right_thick
    prev = "󰁎" -- nf-md-arrow_left_thick
}

--- @returns ViewConfig
M.viewconfig = function()
    if M.options.use_nerdfonts then
        return M.nerdfont_viewconfig
    end
    return M.basic_viewconfig
end

--- @class KeyConfig
--- @field dv_toggle_keybind string | nil if defined, will create keybind that runs DeltaView, and exits Diff buffer if open
--- @field dm_toggle_keybind string | nil if defined, will create keybind that runs DeltaView Menu
--- @field next_hunk string skip to next hunk in diff.
--- @field prev_hunk string skip to prev hunk in diff.
--- @field next_diff string when diff was opened from DeltaMenu, open next file in the menu
--- @field prev_diff string when diff was opened from DeltaMenu, open prev file in the menu
--- @field fzf_toggle string when DeltaMenu is opened in fzf mode (eg. when count exceeds the threshold), can switch back to default quick select.
--- @field jump_to_line string jump to line in Delta buffer
--- @field d_toggle_keybind string | nil if defined, will create keybind that runs Delta, and exits Diff buffer if open

--- @class DeltaViewOpts
--- @field use_nerdfonts boolean | nil Defaults to true
--- @field keyconfig KeyConfig | nil
--- @field show_verbose_nav boolean | nil Show both prev and next filenames (true) or just position + next (false, default)
--- @field quick_select_display string | nil 'bottom' | 'center' | 'hsplit' - the position of DeltaMenu. Defaults to 'hsplit'
--- @field fzf_threshold number | nil if the number of diffed files is equal to or greater than this threshold, it will show up in a fuzzy finding picker. Defaults to 6. Set to 1 or 0 if you would always like a fuzzy picker
--- @field default_context number | nil if running deltaview on a directory rather than a file, it will show a typical delta view with limited context. Defaults to 3. Set here, or pass it in as a second param to DeltaView, which will persist as the context for this session

M.defaults = {
    use_nerdfonts = true,
    show_verbose_nav = false,
    quick_select_display = 'hsplit',
    fzf_threshold = 6,
    default_context = 3,
    keyconfig = {
        dm_toggle_keybind = "<leader>dm",
        dv_toggle_keybind = "<leader>dl",
        d_toggle_keybind = "<leader>da",
        next_hunk = "<Tab>",
        prev_hunk = "<S-Tab>",
        next_diff = "]f",
        prev_diff = "[f",
        fzf_toggle = "alt-;",
        jump_to_line = "<CR>"
    }
}

-- Current options (merged config)
M.options = vim.deepcopy(M.defaults)

--- Setup configuration by merging user options with defaults
--- @param opts DeltaViewOpts | nil User configuration options
M.setup = function(opts)
    M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
