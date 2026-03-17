local M = {}
local config = require('deltaview.config')

--- registers a keybind description into a vim buffer variable that the help legend reads from.
--- call this alongside every vim.keymap.set on a diff buffer in order to have that keybind on the legend
--- @param bufnr number
--- @param key string the key as displayed to the user (e.g. "<Tab>", "q")
--- @param desc string short description of what the keybind does
M.register_keybind = function(bufnr, key, desc)
    -- vim.b values with table types must be fully reassigned
    local entries = vim.b[bufnr].deltaview_help_entries or {}
    table.insert(entries, { key = key, desc = desc })
    vim.b[bufnr].deltaview_help_entries = entries
end

--- opens a floating window centered on the current window showing registered keybinds for bufnr.
--- @param bufnr number the diff buffer whose help entries should be displayed
M.open_help_menu = function(bufnr)
    local entries = vim.b[bufnr].deltaview_help_entries or {}

    local max_key_len = 0
    for _, e in ipairs(entries) do
        max_key_len = math.max(max_key_len, #e.key)
    end

    local title = ' Deltaview keybindings '
    local lines = { title, string.rep('─', #title) }
    for _, e in ipairs(entries) do
        local padding = string.rep(' ', max_key_len - #e.key)
        table.insert(lines, string.format(' %s%s  %s ', e.key, padding, e.desc))
    end
    table.insert(lines, '')

    local width = 0
    for _, l in ipairs(lines) do
        width = math.max(width, #l)
    end
    local height = #lines

    local win_width = vim.api.nvim_win_get_width(0)
    local win_height = vim.api.nvim_win_get_height(0)
    local row = math.max(0, math.floor((win_height - height) / 2))
    local col = math.max(0, math.floor((win_width - width) / 2))

    local help_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, lines)
    vim.bo[help_buf].modifiable = false
    vim.bo[help_buf].bufhidden = 'wipe'

    local win = vim.api.nvim_open_win(help_buf, true, {
        relative = 'win',
        row = row,
        col = col,
        width = width,
        height = height,
        style = 'minimal',
        border = 'rounded',
    })

    for _, key in ipairs({ 'q', '<Esc>', '?' }) do
        vim.keymap.set('n', key, function()
            vim.api.nvim_win_close(win, true)
        end, { buffer = help_buf, silent = true, nowait = true })
    end
end

--- Binds '?' on the given diff buffer to open the help menu, and registers itself as a keybind entry.
--- Call this after all other keybinds for the buffer have been registered.
--- @param bufnr number
M.setup_help_keybind = function(bufnr)
    M.register_keybind(bufnr, config.options.keyconfig.help_legend, 'open this help menu')
    vim.keymap.set('n', config.options.keyconfig.help_legend, function()
        M.open_help_menu(bufnr)
    end, { buffer = bufnr, silent = true })
end

return M
