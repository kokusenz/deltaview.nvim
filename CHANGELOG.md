# Changelog

All notable changes to deltaview.nvim will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Because lua is not compiled for a release, I am just choosing a number and specifying which commit I am describing. I will increment a version if I feel like a feature is big enough to merit it.
I try to attach a commit to each log, but in the initial pr, I may use the pr instead. Will change the pr to the commit hash (if merged) in a later pr.

## Latest

### [0.2.2] - 2026-04-22
pull request - https://github.com/kokusenz/deltaview.nvim/pull/33

#### Breaking Changes
- `use_legacy_delta` removed: The legacy dandavison/delta binary flow has been removed entirely. `use_legacy_delta = true` is no longer a valid config option. [delta.lua](https://github.com/kokusenz/delta.lua) is now the only supported rendering backend.
- delta.lua is now a hard dependency**: Previously delta.lua was optional (falling back to the legacy binary). It is now required. A missing delta.lua will surface as an error via `vim.health` and at the point of use.
- fzf picker removed: The standalone `fzf` (junegunn) picker backend for `:DeltaMenu` has been removed. Supported pickers are now fzf-lua, telescope, and will fall back to this plugin's custom vim.ui.select. The `fzf_picker` config option no longer accepts `"fzf"` as a value.
- delta.lua missing alert is now lazy**: Previously, a missing delta.lua dependency triggered a notification at startup. It now surfaces at the point of use (when a diff command is invoked) and via `:checkhealth deltaview`.

## History

### [0.2.1] - 2026-04-09

#### Added
commit - a6607058ca4d50619d44ddcf51df1cc35bdfd85b

- :DeltaView is able to be used when the neovim cwd is not in a git repository, provided the buffer is a git tracked file - a6607058ca4d50619d44ddcf51df1cc35bdfd85b

#### Fixes

- All delta buffer names are now prefixed by deltaview://diff/, in line with how oil.nvim creates custom buffers, and addressing bug related to file watchers - 808cd6fbe4c49b71f03979790725fb173aade357

### [0.2.0] - 2026-03-16

#### Added
commit - e3f5e0f42d645166e0f78efc7f84dc7bac86f01d

- **delta.lua integration**: deltaview now uses [delta.lua](https://github.com/kokusenz/delta.lua) as its diff rendering backend by default. Delta.lua provides treesitter-based syntax highlighting, treesitter-based two-tier diff highlighting, and diff buffers that respond to window size changes. Many previous issues are resolved with this new backend, such as lack of support for light colorschemes, and bad cursor tracking on wrapped lines. The legacy dandavison/delta flow remains available via `use_legacy_delta = true`.
- **`:Delta` cursor placement**: `:Delta` now attempts to place the cursor at the corresponding line on entry, and syncs cursor position on exit — the same behavior as `:DeltaView`.
- **Fuzzy picker integrations**: Added support for [fzf-lua](https://github.com/ibhagwan/fzf-lua) and [telescope](https://github.com/nvim-telescope/telescope.nvim) as picker backends for `:DeltaMenu`, with diff preview. Picker selection is configurable via `fzf_picker`. Priority order: fzf-lua → telescope → fzf → quickselect.
- **Fuzzy picker by default**: `fzf_threshold` now defaults to `0`, meaning the fuzzy picker is used by default. The preview panel makes the fuzzy picker more valuable than the quick-select shortcuts for most workflows.
- **Three-dot ref support**: `:DeltaView`, `:DeltaMenu`, and `:Delta` now accept three-dot refs (e.g. `main...HEAD`) to diff against the common ancestor.
- **New file diffs**: `:Delta` and `:DeltaView` now handle new (untracked) files correctly, and `:DeltaMenu` now properly sorts untracked files.
- **`:DeltaMenu` from any subdirectory**: `:DeltaMenu` no longer requires the cwd to be the git root; it works from any subdirectory, matching the behavior of `git status`.
- **`line_numbers` config option**: Opt-in statuscolumn line numbers in delta.lua diff buffers, off by default.
- **Help legend**: A `d?` keybind opens an in-buffer help legend showing all available keybinds. Configurable via `keyconfig.help_legend`.
- **`segment` and `file` icons**: Two new nerd font icons added to the view config for hunk count and file indicators.
- **cmd ui is now deprecated**: The ui (dots to represent hunks, shows the ref, etc) that was displayed in the same space as colon commands is now only a part of the legacy workflow.
- **Tests**: The codebase now has tests

#### Changed

- **`:Delta` argument order**: The argument order has changed from `[ref] [context] [path]` to `[path] [context] [ref]` to match the more common use case of specifying a path without a ref.
- **Hunk navigation jumps to top of hunk**: Previously, hunk nav jumped to the first added line of a hunk. It now jumps to the top of the hunk, which may be a deleted line.
- **Hunk navigation viewport behavior**: Hunk navigation no longer forces `zz` (centering the cursor) if the target hunk is already visible in the viewport.
- **Cursor sync uses relative window position**: Entering and exiting a diff buffer no longer forces centering with `zz`, but rather maintains the cursor position exactly.
- **Esc/q disabled on deleted lines**: Previously, pressing `<Esc>` or `q` while the cursor was on a deleted line would exit the buffer and place the cursor at the last valid position. This offered little benefit and has been removed. The user must move the cursor to an added or context line before exiting.
- **usage of enter on delta buffers**: the `:Delta` buffer now behaves exactly like the `:DeltaView` buffer, no longer requiring the usage of enter to jump to a line.

#### Fixes

- Fixed a `<f3><b0><a7>` artifact appearing in the cmd ui; there is no longer a cmd ui.
- Fixed hunk navigation bugs caused by out-of-order line numbers.
- Fixed a crash when running `:Delta` with a context value larger than the file's line count.
- Fixed an issue where delta buffer highlights could persist after navigating away using methods other than `<Esc>` or `q`. There is no longer emphasis highlights in the delta buffer
- Fixed issue with legacy delta workflow, where enter to jump to line no longer worked in the :Delta buffer - d9a530e7b55d035a5341efaba65b47a6d893bc43
- Fixed issue introduced in e3f5e0f42d645166e0f78efc7f84dc7bac86f01d (original 0.2.0 commit) where deltaview buffer names when opened from telescope are not correct - d9a530e7b55d035a5341efaba65b47a6d893bc43
- Fixed issue where binary files were displayed with nonzero line numbers in deltamenu - dbb617444d38baeb91922ca03836d928d395f493


### [0.1.2] - 2026-01-31

#### Added
pr - 70f1d2d25c64f2c70afd4b4f92fd56dc29194899

- yanking code from a Delta buffer will yank the text without any delta line number artifacts.

#### Fixes

- yanked code that includes empty lines would append line number artifacts onto the last valid yanked linked. Now, empty lines are yanked properly - fd45d132eec559c4bbf12ffe02b4f8e0383a22a1

### [0.1.1] - 2026-01-19

#### Added
commit - c389a3efadc61765bd5c68c28a6170c897e4fac8

- `:Delta` command to view diff of a path (directory or file). New custom ui with controllable lines of context, rather than unlimited
- The code that sets up hunk ui now waits until after the terminal buffer has finished rendering the delta ui, to avoid async issues
- Command ui is now truncated to fit the viewport

#### Fixes

- allows passing path as arg to :Delta - dcfd515c43a272b5dcf4192e45a8375dc1449c2b
- refactors .setup to merge user provided config instead of requiring user to override via an after/ directory. changes nerdfonts to be consistent family - e4547f8e79387d0ff6521cc5fc225eddd583ee1b
- deltamenu quickselect now shows all items if items wrap into multiple lines. supplementing helpdocs with vimuiselect details. exposes config to change the position of the deltamenu quickselect. register_ui_select now takes in default selector config. - 0edd2656215a83ce60f00712452c4fdf83b1f4ca

### [0.1.0] - 2026-01-11

#### Added
commit - 8a7bf251b420f1c75158a6c66a145ee26fbdccea

- Initial release of deltaview.nvim - 
- Inline diff viewing using git-delta for syntax highlighting
- `:DeltaView` command to view diff of current file against any git ref
- `:DeltaMenu` command to open file picker for modified files
- Cursor position synchronization between source and diff buffers
- Interactive file picker with smart sorting and navigation
- Custom UI with visual hunk ui and hunk navigation
- FZF integration for fuzzy finding with large changesets
- Help documentation (`:help deltaview`)

#### Fixes

- Nil filepath validation - 587052f2f7f9229452ceb38f52f7e5d46523df41
- Line count parsing - fbc4303db0b65ac597c45c3a5f09c8f93393a6db

