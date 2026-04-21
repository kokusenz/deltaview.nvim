local M = {}

M.check = function()
    local config = require('deltaview.config')

    -- ── core dependency ───────────────────────────────────────────────────────
    vim.health.start('deltaview: core')

    local ok, _ = pcall(require, 'delta')
    local has_delta_lua = ok
    if has_delta_lua then
        vim.health.ok('delta.lua found')
    else
        vim.health.error(
            'delta.lua is not installed',
            { 'Install delta.lua, https://github.com/kokusenz/delta.lua' }
        )
    end

    -- ── git ───────────────────────────────────────────────────────────────────
    vim.health.start('deltaview: git')

    if vim.fn.executable('git') == 1 then
        local result = vim.system({ 'git', '--version' }):wait()
        vim.health.ok(vim.trim(result.stdout))
    else
        vim.health.error('git not found', { 'Install git: https://git-scm.com' })
    end

    -- ── neovim version ────────────────────────────────────────────────────────
    vim.health.start('deltaview: neovim')

    if vim.fn.has('nvim-0.10') == 1 then
        vim.health.ok('Neovim >= 0.10')
    else
        vim.health.error(
            'Neovim 0.10+ is required (vim.system API)',
            { 'Upgrade Neovim to at least 0.10' }
        )
    end

    -- ── pickers ───────────────────────────────────────────────────────────────
    vim.health.start('deltaview: pickers')

    local has_fzf_lua = pcall(require, 'fzf-lua')
    local has_telescope = pcall(require, 'telescope')

    if has_fzf_lua then
        vim.health.ok('fzf-lua available')
    else
        vim.health.warn('fzf-lua not found (optional)')
    end

    if has_telescope then
        vim.health.ok('telescope available')
    else
        vim.health.warn('telescope not found (optional)')
    end

    vim.health.ok('quickselect always available (built-in fallback)')

    -- report which picker will actually be used
    local configured = config.options.fzf_picker
    local active_picker
    if configured == 'fzf-lua' then
        active_picker = has_fzf_lua and 'fzf-lua (configured)' or 'fzf-lua configured but not found — will use auto-detect'
    elseif configured == 'telescope' then
        active_picker = has_telescope and 'telescope (configured)' or 'telescope configured but not found — will use auto-detect'
    else
        -- auto-detect order: fzf-lua -> telescope -> quickselect
        if has_fzf_lua then
            active_picker = 'fzf-lua (auto)'
        elseif has_telescope then
            active_picker = 'telescope (auto)'
        else
            active_picker = 'quickselect (built-in)'
        end
    end
    vim.health.info('active picker: ' .. active_picker)
end

return M
