local M = {}

local NVIM_MIN_VERSION = { major = 0, minor = 10, patch = 0 }

--- Check that Neovim meets the minimum version requirement.
local function check_neovim_version()
    local v = vim.version()
    local ok = v.major > NVIM_MIN_VERSION.major
        or (v.major == NVIM_MIN_VERSION.major and v.minor > NVIM_MIN_VERSION.minor)
        or (v.major == NVIM_MIN_VERSION.major and v.minor == NVIM_MIN_VERSION.minor and v.patch >= NVIM_MIN_VERSION.patch)

    if ok then
        vim.health.ok(string.format(
            "Neovim >= 0.10 (running %d.%d.%d)",
            v.major, v.minor, v.patch
        ))
    else
        vim.health.error(
            string.format("Neovim >= 0.10 required (running %d.%d.%d)", v.major, v.minor, v.patch),
            "Upgrade Neovim to at least version 0.10"
        )
    end
end

--- Check that the git executable is on PATH.
local function check_git()
    local result = vim.fn.executable("git")
    if result == 1 then
        local version_result = vim.fn.systemlist("git --version")
        local version_str = (version_result and version_result[1]) or "unknown version"
        vim.health.ok(version_str)
    else
        vim.health.warn(
            "git not found on PATH",
            "git is required for Delta.git_diff(). Install git or ensure it is on your PATH."
        )
    end
end

--- Check Neovim treesitter is available.
local function check_treesitter()
    if vim.treesitter and vim.treesitter.get_string_parser then
        vim.health.ok("vim.treesitter is available")
    else
        vim.health.error(
            "vim.treesitter is not available",
            "Treesitter support is built into Neovim >= 0.10. Ensure you are running a supported version."
        )
    end
end

--- Check that vim.text.diff or the legacy vim.diff is available for text_diff.
local function check_diff_api()
    if vim.text and vim.text.diff then
        vim.health.ok("vim.text.diff is available (Neovim >= 0.10)")
    elseif vim.diff then
        vim.health.ok("vim.diff is available (legacy API)")
    else
        vim.health.error(
            "Neither vim.text.diff nor vim.diff is available",
            "Delta.text_diff() requires one of these APIs. Upgrade Neovim."
        )
    end
end

--- Check that delta's highlight groups are defined after setup.
local function check_highlight_groups()
    local groups = {
        "DeltaDiffAddedLine",
        "DeltaDiffRemovedLine",
        "DeltaDiffAddedWord",
        "DeltaDiffRemovedWord",
        "DeltaTitle",
        "DeltaLineNrAdded",
        "DeltaLineNrRemoved",
        "DeltaLineNrContext",
    }

    local undefined = {}
    for _, group in ipairs(groups) do
        -- nvim_get_hl returns an empty table when the group is not defined
        local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
        if vim.tbl_isempty(hl) then
            table.insert(undefined, group)
        end
    end

    if #undefined == 0 then
        vim.health.ok("All delta highlight groups are defined")
    else
        vim.health.warn(
            "The following highlight groups are not yet defined: " .. table.concat(undefined, ", "),
            "Call require('delta').setup() to initialise highlight groups, "
            .. "or define them manually in your colorscheme / init.lua."
        )
    end
end

--- Entry point called by `:checkhealth delta`.
M.check = function()
    vim.health.start("delta.lua")

    vim.health.start("delta.lua: neovim")
    check_neovim_version()
    check_diff_api()

    vim.health.start("delta.lua: git")
    check_git()

    vim.health.start("delta.lua: treesitter")
    check_treesitter()

    vim.health.start("delta.lua: highlight groups")
    check_highlight_groups()
end

return M

