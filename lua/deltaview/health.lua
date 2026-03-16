local M = {}

M.check = function()
    local config = require('deltaview.config')

    -- ── core dependency ───────────────────────────────────────────────────────
    vim.health.start('deltaview: core')

    local has_delta_lua = Delta ~= nil
    if has_delta_lua then
        vim.health.ok('delta.lua found')
    else
        vim.health.warn(
            'delta.lua is not installed — treesitter syntax highlighting and other delta.lua features are unavailable',
            { 'Install delta.lua and ensure it is loaded before deltaview' }
        )

        -- Only check for the delta binary when delta.lua is absent (legacy fallback)
        if vim.fn.executable('delta') == 1 then
            vim.health.ok('delta binary found (fallback): ' .. vim.fn.exepath('delta'))
        else
            vim.health.error(
                'delta binary not found — deltaview will not work without either delta.lua or delta',
                { 'Install delta: https://github.com/dandavison/delta' }
            )
        end
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
    local has_fzf_junegunn = vim.fn.exists('*fzf#run') == 1

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

    if has_fzf_junegunn then
        vim.health.ok('fzf (junegunn/fzf.vim) available — note: delta.lua diffs cannot be shown in its preview window')
    else
        vim.health.warn('fzf (junegunn/fzf.vim) not found (optional)')
    end

    vim.health.ok('quickselect always available (built-in fallback)')

    -- report which picker will actually be used
    local configured = config.options.fzf_picker
    local active_picker
    if configured == 'fzf-lua' then
        active_picker = has_fzf_lua and 'fzf-lua (configured)' or 'fzf-lua configured but not found — will use auto-detect'
    elseif configured == 'telescope' then
        active_picker = has_telescope and 'telescope (configured)' or 'telescope configured but not found — will use auto-detect'
    elseif configured == 'fzf' then
        active_picker = 'fzf/junegunn (configured)'
    else
        -- auto-detect order: fzf-lua -> telescope -> fzf -> quickselect
        if has_fzf_lua then
            active_picker = 'fzf-lua (auto)'
        elseif has_telescope then
            active_picker = 'telescope (auto)'
        elseif has_fzf_junegunn then
            active_picker = 'fzf/junegunn (auto)'
        else
            active_picker = 'quickselect (built-in)'
        end
    end
    vim.health.info('active picker: ' .. active_picker)
end

return M
