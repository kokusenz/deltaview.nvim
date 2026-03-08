---
name: minitest-pbt-lua
description: This skill should be used when the user asks to write property-based tests, PBT, or pseudo property-based tests for a Neovim plugin using the MiniTest (mini.test) framework in Lua. Use when the user says things like "add property tests", "write a PBT for", "property based test for", "mini.test property", or "fuzz inputs for".
version: 1.0.0
---

# Property-Based Testing with MiniTest for Neovim Plugins

A pattern for writing pseudo property-based tests (PBT) in Lua using `mini.test`, where test cases are curated hard-coded inputs iterated exhaustively against one or more properties. This is not a true PBT framework — there is no random generation — but it achieves the same goal: separating *what inputs to test* from *what to assert*.

## Core Concept

Split the test into three concerns:
1. **Input generators** — functions that produce exhaustive or edge-covering input sets
2. **Property cases** — curated scenarios (different data shapes, buffer contents, configurations) that each run against every property
3. **Properties** — assertions expressed as Lua strings evaluated inside a child neovim process

Properties and cases are combined in a nested loop: every property runs against every case.

## File Structure

```lua
-- ─────────────────────────────────────────────────────────────────
-- function_name() - property based tests

local FunctionName = {}

-- Input generator: returns a list of inputs to iterate in the property
FunctionName.get_inputs = function(buf_contents) ... end

-- Property cases: each case defines a distinct data shape / scenario
--- @class function_name__property_cases
FunctionName.function_name__property_cases = {
    { name = '...', buf_contents = {...}, get_inputs = FunctionName.get_inputs, ... },
    { name = '...', buf_contents = {...}, get_inputs = FunctionName.get_inputs, ... },
}

-- Properties: each is a Lua string that returns true/false when evaluated in child neovim
FunctionName.properties = {}
FunctionName.properties.property_name = [[(function() ... return true end)()]]

-- Test loop: cross-product of properties × cases
T['function_name() properties'] = new_set()
for func_name, func in pairs(FunctionName.properties) do
    for _, case in ipairs(FunctionName.function_name__property_cases) do
        T['function_name() properties'][func_name .. ': ' .. case.name] = function()
            -- pass inputs into child neovim via _G.fixture
            child.lua([[_G.fixture.inputs = ...]], { case.get_inputs(case.buf_contents) })
            -- set up buffer in child neovim
            child.lua([[
                local bufnr = vim.api.nvim_create_buf(true, true)
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, ...)
                vim.api.nvim_set_current_buf(bufnr)
                _G.fixture.bufnr = bufnr
                _G.fixture.winnr = vim.api.nvim_get_current_win()
            ]], { case.buf_contents })
            -- pass any additional fixture data
            child.lua([[vim.b[_G.fixture.bufnr].some_data = ...]], { case.some_data })
            local result = child.lua_get(func)
            eq(result, true)
        end
    end
end
```

## Input Generators

Generate inputs exhaustively, including boundary and invalid values. The assume pattern (see below) filters out invalid combinations inside the property.

```lua
-- Cursor-style: every (row, col) in the buffer, including zero-indexed cols
FunctionName.get_cursors_set = function(buf_contents)
    local set = {}
    for i, v in ipairs(buf_contents) do
        for j = 1, #v do
            table.insert(set, { i, j - 1 })
        end
    end
    return set
end

-- Numeric inputs: sweep a range including below-zero and beyond-max edge cases
FunctionName.get_inputs = function(buf_contents)
    local set = {}
    for winline = -1, #buf_contents + 1 do
        for row, line in ipairs(buf_contents) do
            for col = -1, #line + 1 do
                table.insert(set, { target_row = row, target_col = col, og_winline = winline })
            end
        end
    end
    -- extreme edge cases
    table.insert(set, { target_row = 9999, target_col = 9999, og_winline = 9999 })
    table.insert(set, { target_row = -9999, target_col = -9999, og_winline = -9999 })
    return set
end
```

## Property Structure

Properties are Lua strings (`[[(function() ... end)()]]`) evaluated in the child neovim via `child.lua_get`. They must return `true` (pass) or `false` (fail). They read from `_G.fixture` which was populated by the test loop before evaluation.

```lua
FunctionName.properties.property_name = [[(function()
    local inputs  = _G.fixture.inputs
    local bufnr   = _G.fixture.bufnr
    local winnr   = _G.fixture.winnr

    for _, input in ipairs(inputs) do
        -- [assume] skip invalid inputs vacuously
        if input.value < 0 then goto continue end

        -- call the function under test
        M.some_function(bufnr, winnr, input.value)

        -- assert the property
        local actual = vim.api.nvim_win_get_cursor(winnr)
        if actual[1] ~= input.expected_row then return false end

        ::continue::
    end

    return true
end)()]]
```

### Assume Semantics

Use `goto continue` + `::continue::` to skip inputs that violate preconditions (analogous to `assume`/`guard` in real PBT frameworks). This makes the property vacuously true for those inputs rather than failing.

For single-value properties (no loop), use an early `return true`:
```lua
if precondition_not_met then return true end
```

## Mocking

### What to mock

Mock functions that:
- Are **side-effectful** and not under test (`vim.api.nvim_echo`, `vim.defer_fn`, `vim.cmd` for file opens)
- Are **plugin-internal** functions on `M` that the function under test calls but you want to isolate (`M.setup_something`, `M.set_restview`)
- Return **runtime values** that can't be known at fixture-setup time (`M.get_cursor_placement_current_buffer`)

### What NOT to mock

Do **not** mock native Neovim/Vim API functions (`vim.api.*`, `vim.fn.*`). These are the ground truth of the running environment. Mocking them undermines the value of the test. Let the child neovim execute them for real.

### How to mock in a property string

Replace functions by direct Lua assignment inside the property string. Always save and restore originals if the mock changes global state that other properties or iterations might depend on.

```lua
FunctionName.properties.some_property = [[(function()
    local winnr = _G.fixture.winnr

    -- mock plugin-internal function; capture runtime value via closure
    local current_cursor = nil
    M.get_cursor_placement_current_buffer = function()
        return { winnr = winnr, cursor = current_cursor }
    end

    -- mock side-effectful calls not under test
    local orig_nvim_echo = vim.api.nvim_echo
    local orig_defer_fn  = vim.defer_fn
    vim.api.nvim_echo = function() end
    vim.defer_fn      = function() end

    -- mock plugin helpers
    M.set_restview            = function() end
    M.setup_cursor_placement  = function() end

    local result = true
    for _, input in ipairs(_G.fixture.inputs) do
        current_cursor = input.cursor  -- update closure each iteration
        M.function_under_test(_G.fixture.bufnr, input.forward)
        local new_row = vim.api.nvim_win_get_cursor(winnr)[1]
        if not valid_rows[new_row] then result = false; break end
    end

    -- restore originals
    vim.api.nvim_echo = orig_nvim_echo
    vim.defer_fn      = orig_defer_fn
    return result
end)()]]
```

## Passing State via `_G.fixture`

Use `_G.fixture` as the namespace for all data passed from the host test process into the child neovim. Populate it with separate `child.lua(...)` calls before evaluating the property.

```lua
-- scalars / tables serialized by MiniTest's RPC
child.lua([[_G.fixture = {}]])  -- reset between cases (or rely on child.restart())
child.lua([[_G.fixture.inputs = ...]], { case.get_inputs(case.buf_contents) })

-- runtime values (bufnr, winnr) must be captured inside child.lua, not passed as args
child.lua([[
    local bufnr = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, ...)
    vim.api.nvim_set_current_buf(bufnr)
    _G.fixture.bufnr = bufnr
    _G.fixture.winnr = vim.api.nvim_get_current_win()
]], { case.buf_contents })

-- buffer-local variables
child.lua([[vim.b[_G.fixture.bufnr].some_buf_var = ...]], { case.some_data })

-- conditional fixture values (e.g. a bufnr that may or may not exist)
if case.use_alternative_bufnr then
    child.lua([[_G.fixture.alternative_bufnr = vim.api.nvim_create_buf(true, true)]])
else
    child.lua([[_G.fixture.alternative_bufnr = nil]])
end
```

## Buffer Setup Best Practices

- Create buffers inside `child.lua` (never pass bufnr from host — the integer won't match)
- Set the buffer as current immediately after creation so `nvim_get_current_win()` reflects it
- Capture `winnr` from inside the same `child.lua` call that sets the current buffer
- Set buffer-local variables (`vim.b[bufnr].x`) in a separate `child.lua` call after the bufnr is in `_G.fixture`

## Property Case Design Guidelines

Each case should represent a distinct **scenario** (not just different numeric inputs). Good axes for variation:
- Different data shapes: single hunk vs. multiple hunks, one file vs. two files
- Presence/absence of optional fields: `filepath = nil` vs. `filepath = 'src/foo.lua'`
- Line types: context-only, added-only, removed-only, mixed
- Boundary conditions: empty buffer, single-line buffer, cursor at first/last row
- Known edge cases or documented bugs: document them in a comment even if the test can't catch them in headless mode

Aim for 3–5 cases. More cases slow the suite; fewer miss meaningful variation.

## When Properties Can't Catch Real Bugs

Some bugs only manifest with an attached terminal (e.g., `vim.fn.screenpos()` returning 0 for off-screen lines in interactive mode but not in headless child neovim). When this happens:
- Document the limitation in a comment above the property
- Add an `assume` (goto continue) to exclude the inputs that trigger the bug, rather than letting the property silently pass for wrong reasons
- Note the bug in the function's source comments for manual testing
