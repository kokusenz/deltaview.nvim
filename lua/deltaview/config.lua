local M = {}

M.setup_keybinds = function()
    -- :DeltaView global keybind
    if M.options.keyconfig.dv_toggle_keybind ~= nil and M.options.keyconfig.dv_toggle_keybind ~= '' then
        vim.keymap.set('n', M.options.keyconfig.dv_toggle_keybind, function()
            vim.cmd('DeltaView')
        end)
    end

    -- :DeltaMenu global keybind
    if M.options.keyconfig.dm_toggle_keybind ~= nil and M.options.keyconfig.dm_toggle_keybind ~= '' then
        vim.keymap.set('n', M.options.keyconfig.dm_toggle_keybind, function()
            vim.cmd('DeltaMenu')
        end)
    end


    -- :Delta global keybind
    if M.options.keyconfig.d_toggle_keybind ~= nil and M.options.keyconfig.d_toggle_keybind ~= '' then
        vim.keymap.set('n', M.options.keyconfig.d_toggle_keybind, function()
            vim.cmd('Delta')
        end)
    end
end

--- @type ViewConfig
M.basic_viewconfig = {
    dot = "·",
    circle = "•",
    vs = "comparing to",
    segment = "≡",
    file = "🗎"
}

--- @type ViewConfig
M.nerdfont_viewconfig = {
    dot = "󰧟", -- nf-md-circle_small
    circle = "󰧞", -- nf-md-circle_medium
    vs = "", -- nf-seti-git
    segment = "󰻋", -- nf-md-segment 
    file = "󰈔" -- nf-md-file
}

--- @returns ViewConfig
M.viewconfig = function()
    if M.options.use_nerdfonts then
        return M.nerdfont_viewconfig
    end
    return M.basic_viewconfig
end

--- @type DeltaViewOpts
M.defaults = {
    use_nerdfonts = true,
    show_verbose_nav = false,
    quick_select_view = 'hsplit',
    default_context = 3,
    line_numbers = false,
    fzf_picker = nil,
    keyconfig = {
        dm_toggle_keybind = "<leader>dm",
        dv_toggle_keybind = "<leader>dl",
        d_toggle_keybind = "<leader>da",
        next_hunk = "<Tab>",
        prev_hunk = "<S-Tab>",
        help_legend = "d?",
    }
}

-- Current options (merged config)
M.options = vim.deepcopy(M.defaults)

--- Setup configuration by merging user options with defaults
--- @param opts DeltaViewOpts | nil User configuration options
M.setup = function(opts)
    M.options = vim.tbl_deep_extend("force", M.options, opts or {})

    -- flagging breaking changes
    if opts and opts.keyconfig and opts.keyconfig.next_diff ~= nil then
        vim.notify([[Deltaview next_diff keybind has been deprecated, as a result of an overall behavioral change to DeltaMenu that involves using the quickfix list underneath all pickers. You can now achieve the original function of this keybind by using ']q', or `:cnext`. This keybind will be bound to `:cnext` temporarily, but please adjust yoru configuration accordingly. This keybind will be removed in the near future.]], vim.log.levels.WARN)
        vim.keymap.set('n', opts.keyconfig.next_diff, function() vim.cmd('cnext') end)
    end
    if opts and opts.keyconfig and opts.keyconfig.prev_diff ~= nil then
        vim.notify([[[Deltaview prev_diff keybind has been deprecated, as a result of an overall behavioral change to DeltaMenu that involves using the quickfix list underneath all pickers. You can now achieve the original function of this keybind by using ']q', or `:cprev`. This keybind will be bound to `:cprev` temporarily, but please adjust yoru configuration accordingly. This keybind will be removed in the near future.]], vim.log.levels.WARN)
        vim.keymap.set('n', opts.keyconfig.prev_diff, function() vim.cmd('cprev') end)
    end
    if opts and opts.fzf_threshold then
        vim.notify([[Support for the Deltaview fzf_threshold configuration option has been removed, as a result of an overall behavioral change to DeltaMenu that involves using the quickfix list underneath all pickers. The benefit of this option was deemed no longer necessary. Please remove this from your configuration.]], vim.log.levels.WARN)
    end
end

--- @class ViewConfig
--- @field dot string
--- @field circle string
--- @field vs string
--- @field segment string
--- @field file string


--- @class KeyConfig
--- @field dv_toggle_keybind string | nil if defined, will create keybind that runs DeltaView, and exits Diff buffer if open. By default, <leader>dv.
--- @field dm_toggle_keybind string | nil if defined, will create keybind that runs DeltaView Menu. By default, <leader>dm.
--- @field d_toggle_keybind string | nil if defined, will create keybind that runs Delta, and exits Diff buffer if open
--- @field next_hunk string skip to next hunk in diff.
--- @field prev_hunk string skip to prev hunk in diff.
--- @field help_legend string opens the help legend when inside a deltaview buffer

--- @class DeltaViewOpts
--- @field use_nerdfonts boolean | nil Defaults to true
--- @field keyconfig KeyConfig | nil
--- @field show_verbose_nav boolean | nil Show both prev and next filenames (true) or just position + next (false, default)
--- @field quick_select_view string | nil 'bottom' | 'center' | 'hsplit' - the position of DeltaMenu. Defaults to 'hsplit'
--- @field default_context number | nil if running deltaview on a directory rather than a file, it will show a typical delta view with limited context. Defaults to 3. Set here, or pass it in as a second param to DeltaView, which will persist as the context for this session
--- @field line_numbers boolean | nil If this setting is true, will show the delta style line numbers in the statuscolumn.
--- @field fzf_picker 'fzf-lua' | 'telescope' | 'quickfix' | 'ui_select' | nil specify which picker to use. If nil, will go through the order and pick the first available. fzf-lua -> telescope -> quickfix -> ui_select. Note that quickfix should always succeed, and ui_select is only available for users who specify it. ui_select refers to vim.ui.select, and will respect whichever picker you are using for it; this exists as an option for a picker that doesn't use a previewer. For example, with fzf-lua, you might use require('fzf-lua').register_ui_select() for a fuzzy picker without a previewer, then set this option. Telescope only comes with a vim.ui.select override, at https://github.com/nvim-telescope/telescope-ui-select.nvim.

return M
