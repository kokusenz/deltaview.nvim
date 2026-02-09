# Changelog

All notable changes to deltaview.nvim will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Because lua is not compiled for a release, I am just choosing a number and specifying which commit I am describing. I will increment a version if I feel like a feature is big enough to merit it.
I try to attach a commit to each log, but in the initial pr, I may use the pr instead. Will change the pr to the commit hash (if merged) in a later pr.

## Latest

### [0.1.2] - 2025-01-31

#### Added
pr - 70f1d2d25c64f2c70afd4b4f92fd56dc29194899

- yanking code from a Delta buffer will yank the text without any delta line number artifacts.

#### Fixes

- yanked code that includes empty lines would append line number artifacts onto the last valid yanked linked. Now, empty lines are yanked properly - https://github.com/kokusenz/deltaview.nvim/pull/16

## History

### [0.1.0] - 2025-01-11

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

### [0.1.1] - 2025-01-19

#### Added
commit - c389a3efadc61765bd5c68c28a6170c897e4fac8

- `:Delta` command to view diff of a path (directory or file). New custom ui with controllable lines of context, rather than unlimited
- The code that sets up hunk ui now waits until after the terminal buffer has finished rendering the delta ui, to avoid async issues
- Command ui is now truncated to fit the viewport

#### Fixes

- allows passing path as arg to :Delta - dcfd515c43a272b5dcf4192e45a8375dc1449c2b
- refactors .setup to merge user provided config instead of requiring user to override via an after/ directory. changes nerdfonts to be consistent family - e4547f8e79387d0ff6521cc5fc225eddd583ee1b
- deltamenu quickselect now shows all items if items wrap into multiple lines. supplementing helpdocs with vimuiselect details. exposes config to change the position of the deltamenu quickselect. register_ui_select now takes in default selector config. - 0edd2656215a83ce60f00712452c4fdf83b1f4ca
