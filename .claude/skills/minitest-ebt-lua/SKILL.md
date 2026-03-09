---
name: minitest-ebt-lua
description: This skill should be used when the user asks to write example-based tests, unit tests, or EBT for a Neovim plugin using the MiniTest (mini.test) framework in Lua. Use when the user says things like "add unit tests", "write example tests", "write tests for", "add mini.test tests", "test this function", or "write a test case for".
version: 1.0.0
---

# Example-Based Testing with MiniTest for Neovim Plugins

A pattern for writing example-based unit tests for Neovim plugins in Lua using `mini.test`. Each test targets a **single function**, is fully **isolated** (independent mocks per suite), and **stubs all external dependencies** so that a change to an unrelated function never breaks this test.

## Core Principles

1. **Test functions, not features** — one `T['function_name()']` set per function under test.
2. **Isolation** — each suite re-mocks everything it needs in its own `pre_case` hook. Top-level hooks only handle truly global setup (child restart, core module load).
3. **Mock external dependencies** — stub every dependency the function under test calls that is not itself under test. This includes other `M.*` functions, `vim.system`, `vim.fn.*`, `vim.api.*` side-effectful calls, and plugin modules loaded via `package.loaded`.
4. **Do NOT mock native Neovim API calls that produce real state** (buffer/window creation, cursor manipulation) — let the child process execute those for real.
5. **Capture prints** — always install the print-capture shim so debug output is visible on failure.

---

## File Header

Every test file starts with the same three aliases and one child instance:

```lua
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()
```

---

## Print Capture Utility

Paste this verbatim near the top of every test file, after the header. It is activated per-suite via `child.lua(test_logging)` inside `pre_case` and surfaced via `post_case = print_test_logging`.

```lua
-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- utility

-- usage: add the following to a pre_case hook
-- child.lua(test_logging)
local test_logging = [[
    _G.test_logs = {}
    _G.captured_prints = {}
    local original_print = print
    print = function(...)
      local args = {...}
      local msg = table.concat(vim.tbl_map(tostring, args), ' ')
      table.insert(_G.captured_prints, msg)
      original_print(...)  -- Still call original for child's output
    end
]]

-- usage: add the following to the new_set
-- post_case = print_test_logging
local print_test_logging = function()
    local captured_prints = child.lua_get('_G.captured_prints')
    if captured_prints and #captured_prints > 0 then
        print('\n=== Child Neovim Print Statements ===')
        for i, msg in ipairs(captured_prints) do
            print(string.format('[%d] %s', i, msg))
        end
        print('=== End Print Statements ===\n')
    end
end
```

---

## Top-Level Set (T)

`T` is the root set. Its `pre_case` restarts the child neovim, mocks every external dependency that **all** suites share, then loads the module under test. `post_case` prints captured output. `post_once` stops the child.

```lua
-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                -- Stub plugin modules that the module under test requires.
                -- Use package.loaded to intercept require() before the real module loads.
                package.loaded['myplugin.utils'] = {
                    some_util = function(_) return {} end,
                }
                package.loaded['myplugin.config'] = {
                    options = { some_option = true },
                }

                -- Stub global dependencies (e.g. a C extension exposed as _G.Lib)
                _G.Lib = {
                    parse = { get_data = function(_) return {} end },
                    compute = function(_a, _b, _opts) return nil end,
                }

                -- Stub vim functions that have side effects or require a real terminal
                vim.fn.expand = function(_) return '/fake/path' end
                vim.fn.systemlist = function(_) return {} end
                vim.system = function(_cmd, _opts)
                    return { wait = function() return { code = 0, stdout = '', stderr = '' } end }
                end
            ]])
            child.lua([[M = require('myplugin.module')]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})
```

**Rules for the top-level `pre_case`:**
- `child.restart(...)` must come first.
- Mock via `package.loaded` **before** `require(...)` so the module sees the stubs.
- Initialize `_G.fixture = {}` here so each case starts clean.
- Install `test_logging` here.

---

## Suite Separator Comments

Use the following comment line to visually separate each suite. Keep it exactly 96 characters wide.

```lua
-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- function_name() - example based tests
```

For mixed files (some suites have property tests, others example tests), use the appropriate suffix: `- property based tests` or `- example based tests`.

---

## Suite Structure

Each function under test gets its own `T['function_name()']` set. The suite's `pre_case` hook adds **only** the mocks that this function needs on top of the top-level stubs.

```lua
-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- my_function() - example based tests

T['my_function()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                -- Stub vim functions called by my_function that are not under test
                vim.fn.expand = function(_) return '/fake/file.lua' end
                vim.api.nvim_get_current_buf = function() return 99 end

                -- Stub other M.* functions called by my_function
                M.helper_a = function(_arg) return {} end
                M.helper_b = function() end
            ]])
        end,
    }
})
```

**If the function needs no extra setup**, omit the suite-level hooks entirely:

```lua
T['my_simple_function()'] = new_set()
```

---

## Individual Test Cases

Assign each test as `T['suite']['description'] = function() ... end`. Follow Arrange / Act / Assert:

```lua
T['my_function()']['returns expected value for happy path input'] = function()
    -- Arrange: override specific mocks or set up fixture state for this test only
    child.lua([[
        _G.fixture.captured_args = nil
        M.helper_a = function(arg)
            _G.fixture.captured_args = arg
            return { result = 42 }
        end
    ]])

    -- Act + Assert: run the function and check results
    local result = child.lua_get([[(function()
        local ok, val = pcall(M.my_function, 'input_a', 'input_b')
        if not ok then return nil end
        return val
    end)()]])

    local captured = child.lua_get([[_G.fixture.captured_args]])

    eq(result, 42)
    eq(captured, 'input_a')
end

T['my_function()']['returns nil and does not throw on invalid input'] = function()
    local result = child.lua_get([[(function()
        local ok, val = pcall(M.my_function, nil, 'input_b')
        if not ok then return nil end  -- unexpected throw is a bug
        return val
    end)()]])

    eq(result, vim.NIL)
end
```

---

## `child.lua` vs `child.lua_get`

| Use | When |
|---|---|
| `child.lua(code)` | Execute code in the child with no return value needed |
| `child.lua(code, {args})` | Execute code with args passed via `...` vararg |
| `child.lua_get(code)` | Execute and return the result to the host |
| `child.lua_get(code, {args})` | Execute with args and return result |

Pass args via the second argument (serialized via MiniTest RPC), never by string interpolation. Inside the child, receive them via `...`:

```lua
child.lua([[
    local winnr, cursor = ...
    vim.api.nvim_win_set_cursor(winnr, cursor)
]], { window_handle, { 2, 3 } })
```

---

## Mocking Strategy

### Three layers of mocks

1. **Top-level `pre_case`** — shared stubs for all suites (module-level dependencies, global `_G.Lib`, `vim.system` happy path).
2. **Suite-level `pre_case`** — stubs specific to one function (its direct collaborators on `M.*`, any `vim.fn.*` it calls).
3. **Inside individual tests** — override a single mock to test a specific code path (failure mode, call counting, spy capture).

### Mock external dependencies, not internal state

```lua
-- Good: mock a collaborator so this test is only about my_function
M.fetch_data = function(_path) return { lines = { 'a', 'b' } } end

-- Good: mock a vim API with side effects not relevant to this test
vim.notify = function() end

-- Bad: mock vim.api.nvim_create_buf — let neovim do this for real
```

### Spy pattern (capture what was called)

```lua
child.lua([[
    _G.fixture.keymap_set_args = {}
    vim.keymap.set = function(modes, lhs, rhs, opts)
        _G.fixture.keymap_set_args[lhs] = { modes = modes, lhs = lhs, rhs = rhs, opts = opts }
    end
    M.my_function()
]])

local modes = child.lua_get([[_G.fixture.keymap_set_args['<Esc>'].modes]])
eq(modes, 'n')
```

### Verifying callbacks are called

```lua
child.lua([[
    _G.fixture.callback_called = false
    M.get_callback = function()
        return function() _G.fixture.callback_called = true end
    end
    M.my_function()
]])

-- trigger the callback
child.lua([[_G.fixture.keymap_set_args['q'].rhs()]])
local called = child.lua_get([[_G.fixture.callback_called]])
eq(called, true)
```

---

## `_G.fixture` Conventions

Use `_G.fixture` as the namespace for all shared state inside the child:

```lua
_G.fixture = {}                          -- reset at top-level pre_case
_G.fixture.bufnr = <number>              -- buffer handles captured inside child.lua
_G.fixture.winnr = <number>              -- window handles captured inside child.lua
_G.fixture.captured_args = <any>         -- spy captures
_G.fixture.some_flag = false             -- boolean sentinels
```

**Do not pass buffer or window handles from the host** — integers differ between host and child. Always create buffers inside `child.lua` and store the result in `_G.fixture`:

```lua
child.lua([[
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, ...)
    vim.api.nvim_set_current_buf(buf)
    _G.fixture.bufnr = buf
    _G.fixture.winnr = vim.api.nvim_get_current_win()
]], { { 'line1', 'line2', 'line3' } })
```

---

## Asserting `nil` Returns

`child.lua_get` maps Lua `nil` to `vim.NIL` on the host side:

```lua
eq(result, vim.NIL)   -- function returned nil
```

---

## Complete Example

```lua
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- utility

local test_logging = [[
    _G.test_logs = {}
    _G.captured_prints = {}
    local original_print = print
    print = function(...)
      local args = {...}
      local msg = table.concat(vim.tbl_map(tostring, args), ' ')
      table.insert(_G.captured_prints, msg)
      original_print(...)
    end
]]

local print_test_logging = function()
    local captured_prints = child.lua_get('_G.captured_prints')
    if captured_prints and #captured_prints > 0 then
        print('\n=== Child Neovim Print Statements ===')
        for i, msg in ipairs(captured_prints) do
            print(string.format('[%d] %s', i, msg))
        end
        print('=== End Print Statements ===\n')
    end
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- setup

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                package.loaded['myplugin.utils'] = {
                    read_lines = function(_) return {} end,
                }
                _G.Lib = {
                    compute = function(_s1, _s2, _opts) return nil end,
                }
                vim.system = function(_cmd, _opts)
                    return { wait = function() return { code = 0, stdout = '', stderr = '' } end }
                end
            ]])
            child.lua([[M = require('myplugin.view')]])
            child.lua([[_G.fixture = {}]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- open_buffer() - example based tests

T['open_buffer()'] = new_set({
    hooks = {
        pre_case = function()
            child.lua([[
                vim.fn.expand = function(_) return '/fake/file.lua' end
                vim.api.nvim_get_current_buf = function() return 99 end
                M.load_content = function(_buf, _path) end
                M.setup_keymaps = function(_buf) end
            ]])
        end,
    }
})

T['open_buffer()']['binds escape key to close'] = function()
    child.lua([[
        _G.fixture.keymap_set_args = {}
        vim.keymap.set = function(modes, lhs, rhs, opts)
            _G.fixture.keymap_set_args[lhs] = { modes = modes, rhs = rhs, opts = opts }
        end
        M.open_buffer('HEAD')
    ]])

    local modes = child.lua_get([[_G.fixture.keymap_set_args['<Esc>'].modes]])
    local silent = child.lua_get([[_G.fixture.keymap_set_args['<Esc>'].opts.silent]])
    eq(modes, 'n')
    eq(silent, true)
end

T['open_buffer()']['returns nil when file is not readable'] = function()
    child.lua([[
        vim.fn.filereadable = function(_) return 0 end
    ]])

    local result = child.lua_get([[(function()
        local ok, val = pcall(M.open_buffer, 'HEAD')
        if not ok then return nil end
        return val
    end)()]])

    eq(result, vim.NIL)
end

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- get_cursor_position() - example based tests

T['get_cursor_position()'] = new_set()

T['get_cursor_position()']['returns winnr and cursor for current window'] = function()
    child.lua([[
        local buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'line1', 'line2' })
        local winnr, cursor = ...
        vim.api.nvim_set_current_win(winnr)
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_win_set_cursor(winnr, cursor)
        _G.fixture.winnr = winnr
    ]], { 1000, { 2, 3 } })

    child.lua([[
        local pos = M.get_cursor_position()
        _G.fixture.result = pos
    ]])

    local result = child.lua_get([[_G.fixture.result]])
    eq(result.winnr, 1000)
    eq(result.cursor, { 2, 3 })
end

return T
```

---

## Checklist Before Submitting Tests

- [ ] Every suite has its own `pre_case` that mocks all direct collaborators of the function under test
- [ ] No suite's setup leaks into another suite (top-level `pre_case` does `child.restart` which resets all state)
- [ ] Print capture (`test_logging` + `print_test_logging`) is installed
- [ ] Buffer/window handles are created inside `child.lua` and stored in `_G.fixture`, never passed from host
- [ ] `nil` return values are compared with `vim.NIL`, not `nil`
- [ ] Failure paths use `pcall` and assert `vim.NIL` (not `eq(ok, false)` which isn't idiomatic here)
- [ ] Suite separator comments use the full-width `──` line
- [ ] Each test name describes the **behaviour** being verified, not the implementation detail
