local M = {}

M.check = function()
    local config = require('deltaview.config')

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

    -- ── treesitter ────────────────────────────────────────────────────────────
    vim.health.start('deltaview: treesitter')

    if vim.treesitter and vim.treesitter.get_string_parser then
        vim.health.ok('vim.treesitter is available')
    else
        vim.health.error(
            'vim.treesitter is not available',
            { 'Treesitter is built into Neovim >= 0.10. Ensure you are running a supported version.' }
        )
    end

    -- ── diff api ──────────────────────────────────────────────────────────────
    vim.health.start('deltaview: diff api')

    if vim.text and vim.text.diff then
        vim.health.ok('vim.text.diff is available')
    elseif vim.diff then
        vim.health.ok('vim.diff is available (legacy API)')
    else
        vim.health.error(
            'Neither vim.text.diff nor vim.diff is available',
            { 'Upgrade Neovim to at least 0.10' }
        )
    end

    -- ── highlight groups ──────────────────────────────────────────────────────
    vim.health.start('deltaview: highlight groups')

    local hl_groups = {
        'DeltaDiffAddedLine',
        'DeltaDiffRemovedLine',
        'DeltaDiffAddedWord',
        'DeltaDiffRemovedWord',
        'DeltaTitle',
        'DeltaLineNrAdded',
        'DeltaLineNrRemoved',
        'DeltaLineNrContext',
    }

    local undefined = {}
    for _, group in ipairs(hl_groups) do
        if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = group, link = false })) then
            table.insert(undefined, group)
        end
    end

    if #undefined == 0 then
        vim.health.ok('all highlight groups are defined')
    else
        vim.health.warn(
            'undefined highlight groups: ' .. table.concat(undefined, ', '),
            { "Call require('deltaview').setup() to initialise highlight groups." }
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
