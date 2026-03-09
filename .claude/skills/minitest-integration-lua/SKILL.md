---
name: minitest-integration-lua
description: This skill should be used when the user asks to write integration tests for a Neovim plugin using the MiniTest (mini.test) framework in Lua. Use when the user says things like "add integration tests", "write an integration test for", "test against the real dependency", "end-to-end test", "integration test with fzf/telescope/etc", or "test the full flow".
version: 1.0.0
---

# Integration Testing with MiniTest for Neovim Plugins

A pattern for writing integration tests for Neovim plugins in Lua using `mini.test`. Integration tests exercise the **full stack with real dependencies** — no mocks unless a specific non-happy-path case demands one. They test observable outcomes (buffer state, window layout, keymaps bound, commands that work) rather than internal implementation details.

## Core Principles

1. **No mocks by default** — load real dependencies via `runtimepath`; let the plugin run against them as it would in production.
2. **Use mocks only for non-happy-path cases** — e.g. to force a failure branch that can't be triggered with real inputs (a git command that always succeeds in a real repo).
3. **Test happy paths and common failure cases** — not exhaustive edge cases (those belong in unit tests).
4. **Tests are feature-level** — one `T['FeatureName integration']` set per user-visible feature or command, not per internal function.
5. **Isolation via temporary state** — create throwaway git repos, temp files, and temp dirs inside `child.lua` using `vim.fn.tempname()`. Never rely on the test runner's working directory having the right git state.
6. **Print capture** — always install the print-capture shim so debug output is visible on failure.

---

## File Header

```lua
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()
```

---

## Print Capture Utility

Same shim as unit tests — paste verbatim near the top:

```lua
-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- Utility

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

Integration tests have a simpler top-level setup than unit tests: restart child, load the plugin (no mocks), install logging. No `package.loaded` stubs here.

```lua
-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- Test suite

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[M = require('myplugin')]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})
```

**Key difference from unit tests**: no `child.lua([[package.loaded[...] = ...]])` here. The `minimal_init.lua` already adds real deps to `rtp`.

---

## Suite Separator Comments

```lua
-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- `:CommandName` integration
```

Use the full-width `──` banner. Label each suite by the user-visible command or feature it exercises.

---

## Temporary Git Repo Fixtures

Integration tests that touch git need a real, isolated git repo. Build one inside a Lua string that is executed with `child.lua(...)`. Store the pattern as a local variable so multiple tests can reuse it.

### Minimal single-file repo

```lua
local setup_tmpdir_git_repo = [[
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    vim.fn.system('git -C ' .. tmpdir .. ' init')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.email "test@test.com"')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.name "Test"')
    local f = io.open(tmpdir .. '/test.lua', 'w')
    f:write('local x = 1\nlocal y = 2\n')
    f:close()
    vim.fn.system('git -C ' .. tmpdir .. ' add test.lua')
    vim.fn.system('git -C ' .. tmpdir .. ' commit -m "initial"')
    -- Make a working-tree change
    local f2 = io.open(tmpdir .. '/test.lua', 'w')
    f2:write('local x = 1\nlocal y = 99\n')
    f2:close()
    vim.cmd('cd ' .. tmpdir)
    vim.cmd('edit ' .. tmpdir .. '/test.lua')
]]
```

### Parameterised: N tracked files with changes

Pass `n` via the vararg `...` so the same fixture can set up repos of different sizes:

```lua
local setup_tmpdir_git_repo_n_files = [[
    local n = ...
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    vim.fn.system('git -C ' .. tmpdir .. ' init')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.email "test@test.com"')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.name "Test"')
    for i = 1, n do
        local fname = 'file' .. i .. '.lua'
        local f = io.open(tmpdir .. '/' .. fname, 'w')
        f:write('local x = ' .. i .. '\n')
        f:close()
        vim.fn.system('git -C ' .. tmpdir .. ' add ' .. fname)
    end
    vim.fn.system('git -C ' .. tmpdir .. ' commit -m "initial"')
    for i = 1, n do
        local fname = 'file' .. i .. '.lua'
        local f = io.open(tmpdir .. '/' .. fname, 'w')
        f:write('local x = ' .. (i * 10) .. '\n')
        f:close()
    end
    vim.cmd('cd ' .. tmpdir)
]]

-- Usage: child.lua(setup_tmpdir_git_repo_n_files, { 3 })
```

### Scenario fixture: specific file content for a known edge case

When an integration test targets a specific real-world failure mode, build the exact before/after file content inside the fixture string:

```lua
local setup_tmpdir_specific_scenario = [[
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    vim.fn.system('git -C ' .. tmpdir .. ' init')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.email "test@test.com"')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.name "Test"')

    local before_lines = {
        'local function foo()',
        '    return 1',
        'end',
    }
    local f = io.open(tmpdir .. '/mod.lua', 'w')
    f:write(table.concat(before_lines, '\n') .. '\n')
    f:close()
    vim.fn.system('git -C ' .. tmpdir .. ' add mod.lua')
    vim.fn.system('git -C ' .. tmpdir .. ' commit -m "initial"')

    local after_lines = {
        'local function foo()',
        '    return 42',  -- changed line
        'end',
        '',
        'local function bar() end',  -- added function
    }
    local f2 = io.open(tmpdir .. '/mod.lua', 'w')
    f2:write(table.concat(after_lines, '\n') .. '\n')
    f2:close()

    vim.cmd('cd ' .. tmpdir)
    vim.cmd('edit ' .. tmpdir .. '/mod.lua')
]]
```

**Fixture design rules:**
- Always set `user.email` and `user.name` — git refuses to commit without them.
- Always `vim.cmd('cd ' .. tmpdir)` so the plugin's cwd-relative git calls resolve correctly.
- Always open the file with `vim.cmd('edit ...')` if the plugin needs a current buffer.
- Use `io.open` + `f:write` + `f:close` for file creation — `vim.fn.writefile` also works.

---

## Suite and Test Structure

```lua
-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- `:MyCommand` integration

T['MyCommand integration'] = new_set({
    hooks = {
        pre_case = function()
            child.lua(setup_tmpdir_git_repo)  -- shared fixture for all cases in this suite
        end,
    },
})

T['MyCommand integration']['happy path: creates buffer with expected state'] = function()
    child.cmd('MyCommand HEAD')
    local has_data = child.lua_get('vim.b[vim.api.nvim_get_current_buf()].my_data ~= nil')
    local buf_on_window = child.lua_get('vim.api.nvim_win_get_buf(0) == vim.api.nvim_get_current_buf()')
    local name = child.lua_get('vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())')
    eq(has_data, true)
    eq(buf_on_window, true)
    eq(name:find('HEAD',     1, true) ~= nil, true)
    eq(name:find('test.lua', 1, true) ~= nil, true)
end
```

**What to assert in integration tests:**
- Buffer-local variables set by the plugin (e.g. `vim.b[buf].my_data ~= nil`)
- The buffer is visible in the expected window (`nvim_win_get_buf`)
- Buffer name encodes key info (file path, ref, hunk count, etc.)
- A terminal buffer exists when the feature opens an external picker
- Keymaps are bound on the right buffer

**What NOT to assert:**
- Internal data structure shapes (that belongs in unit tests)
- Exact line content of the buffer (too fragile; verify structure instead)

---

## Testing Branching Behavior via Config

When the plugin has configuration that changes the code path taken (e.g. a threshold that switches between two pickers), set the config before the command and assert the observable difference:

```lua
T['MyCommand integration']['picker A path: opens terminal when above threshold'] = function()
    child.lua([[M.setup({ picker_threshold = 6 })]])
    child.lua(setup_tmpdir_git_repo_n_files, { 7 })  -- 7 files > threshold of 6
    child.cmd('MyCommand HEAD')
    local has_terminal = child.lua_get([[
        (function()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.bo[buf].buftype == 'terminal' then return true end
            end
            return false
        end)()
    ]])
    eq(has_terminal, true)
end

T['MyCommand integration']['picker B path: quickselect when below threshold'] = function()
    child.lua([[M.setup({ picker_threshold = 6 })]])
    child.lua(setup_tmpdir_git_repo_n_files, { 3 })  -- 3 files < threshold of 6
    child.cmd('MyCommand HEAD')
    child.type_keys('<CR>')
    local has_data = child.lua_get('vim.b[vim.api.nvim_get_current_buf()].my_data ~= nil')
    eq(has_data, true)
end
```

---

## Using Mocks in Integration Tests

Inline mocks in integration tests are the exception, not the rule. Use them only to:
- Force a failure path that can't be triggered via real inputs (e.g. a git command that would always succeed in a real repo)
- Reproduce a known real-world bug scenario that requires specific tool output

When you do mock, apply the mock inside the individual test, not in a suite-level hook:

```lua
T['MyCommand integration']['failure path: notify called when dependency returns error'] = function()
    child.lua([[
        _G.fixture.notify_called = false
        vim.notify = function(_msg, _level)
            _G.fixture.notify_called = true
        end
        -- Force the failure by making the dependency return an error code
        vim.system = function(_cmd, _opts)
            return { wait = function() return { code = 128, stdout = '', stderr = 'fatal' } end }
        end
    ]])
    child.cmd('MyCommand HEAD')
    local notify_called = child.lua_get('_G.fixture.notify_called')
    eq(notify_called, true)
end
```

---

## Adding a New Dependency

When the plugin integrates with a new Neovim plugin (e.g. a picker, a UI library), follow these steps:

### 1. Add to `Makefile` — clone the dep into `deps/`

In the `setup` and `setup-silent` targets, add an entry for the new dependency alongside existing ones:

```make
# setup target (verbose)
@if [ ! -d "deps/newdep" ]; then \
    echo "Installing newdep for integration tests..."; \
    git clone --filter=blob:none https://github.com/author/newdep deps/newdep; \
else \
    echo "newdep already installed"; \
fi

# setup-silent target (quiet)
@[ -d "deps/newdep" ] || git clone -q --filter=blob:none https://github.com/author/newdep deps/newdep
```

Use `--filter=blob:none` on both to avoid downloading full history.

### 2. Add to `scripts/minimal_init.lua` — put it on `runtimepath`

```lua
-- newdep
vim.cmd('set rtp+=deps/newdep')
```

Add it after the existing `rtp` lines, before `require('mini.test').setup()`. The order matters if dependencies have their own dependencies — put prerequisites first.

**Pattern for `minimal_init.lua`:**

```lua
-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  vim.cmd('set rtp+=deps/mini.test')
  vim.cmd('set rtp+=deps/existing-dep-1')
  vim.cmd('set rtp+=deps/existing-dep-2')
  vim.cmd('set rtp+=deps/newdep')         -- add here
  require('mini.test').setup()
end
```

### 3. Write the integration test

Create a new suite in the integration test file. The dependency is now available in the child neovim because `minimal_init.lua` (loaded via `child.restart({ '-u', 'scripts/minimal_init.lua' })`) puts it on the rtp:

```lua
-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- `:MyCommand` with newdep integration

T['MyCommand newdep integration'] = new_set({
    hooks = {
        pre_case = function()
            child.lua(setup_tmpdir_git_repo)
        end,
    },
})

T['MyCommand newdep integration']['happy path: newdep picker opens'] = function()
    -- configure the plugin to use newdep
    child.lua([[M.setup({ picker = 'newdep' })]])
    child.cmd('MyCommand HEAD')
    -- assert something observable about the newdep UI
    local picker_open = child.lua_get([[require('newdep').is_open()]])
    eq(picker_open, true)
end
```

### 4. Run and verify

```bash
make clean && make setup   # re-clone deps including new one
make test                  # full suite
make test-file FILE=tests/myplugin/test_integrations.lua  # just integration tests
```

---

## Complete Example

```lua
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- Utility

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
-- Test suite

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[M = require('myplugin')]])
            child.lua(test_logging)
        end,
        post_case = print_test_logging,
        post_once = child.stop,
    },
})

-- ──────────────────────────────────────────────────────────────────────────────────────────────
-- `:DiffView` integration

local setup_tmpdir_git_repo = [[
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    vim.fn.system('git -C ' .. tmpdir .. ' init')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.email "test@test.com"')
    vim.fn.system('git -C ' .. tmpdir .. ' config user.name "Test"')
    local f = io.open(tmpdir .. '/test.lua', 'w')
    f:write('local x = 1\nlocal y = 2\n')
    f:close()
    vim.fn.system('git -C ' .. tmpdir .. ' add test.lua')
    vim.fn.system('git -C ' .. tmpdir .. ' commit -m "initial"')
    local f2 = io.open(tmpdir .. '/test.lua', 'w')
    f2:write('local x = 1\nlocal y = 99\n')
    f2:close()
    vim.cmd('cd ' .. tmpdir)
    vim.cmd('edit ' .. tmpdir .. '/test.lua')
]]

T['DiffView integration'] = new_set({
    hooks = {
        pre_case = function()
            child.lua(setup_tmpdir_git_repo)
        end,
    },
})

T['DiffView integration']['happy path: creates diff buffer with data and correct name'] = function()
    child.cmd('DiffView HEAD')
    local has_data      = child.lua_get('vim.b[vim.api.nvim_get_current_buf()].diff_data ~= nil')
    local buf_on_window = child.lua_get('vim.api.nvim_win_get_buf(0) == vim.api.nvim_get_current_buf()')
    local name          = child.lua_get('vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())')
    eq(has_data, true)
    eq(buf_on_window, true)
    eq(name:find('HEAD',     1, true) ~= nil, true)
    eq(name:find('test.lua', 1, true) ~= nil, true)
end

return T
```

---

## Checklist Before Submitting Integration Tests

- [ ] No mocks in the top-level or suite-level hooks — real dependencies only
- [ ] Any mocks are inline in individual tests and justified by a comment
- [ ] Each git fixture sets `user.email` and `user.name`
- [ ] Each fixture calls `vim.cmd('cd ' .. tmpdir)` to set cwd
- [ ] Each fixture opens the relevant file with `vim.cmd('edit ...')` when the plugin needs a current buffer
- [ ] Assertions check observable outcomes (buffer vars, window state, buffer name) not internal data shapes
- [ ] New dependencies are cloned in both `setup` and `setup-silent` Makefile targets with `--filter=blob:none`
- [ ] New dependencies are added to `scripts/minimal_init.lua` inside the `if #vim.api.nvim_list_uis() == 0 then` block
- [ ] Print capture (`test_logging` + `print_test_logging`) is installed
- [ ] Suite separator comments use the full-width `──` line
- [ ] Suite names use the pattern `'CommandName integration'`
