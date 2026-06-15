# deltaview.nvim

An inline git diff viewer for Neovim with two-tier diff highlighting and syntax highlighting inspired by the [delta](https://github.com/dandavison/delta) pager.

![DeltaView Screenshot](https://github.com/user-attachments/assets/d4d1e8aa-7fd1-4759-b658-45ca468c18fa)

## Why?

Alternative inline/unified diff viewers in the neovim plugin ecosystem tend to use virtual lines to display negative changes. Cursors cannot land on virtual lines, which disrupts scrolling. You cannot yank lines of code that were deleted. With a large block of negative changes that does not fit in the window's viewport, you cannot see the full extent of the changes.

This plugin creates inline diffs as readonly, separate buffers without virtual lines. You are able to use lsp features while reviewing changes, yank deleted lines of code, and navigate around a pull request as you would your normal files.

## Demos

### :DeltaView demo
https://github.com/user-attachments/assets/6a28f113-9462-4568-93ca-6db6e7f8be97

### :Delta demo
https://github.com/user-attachments/assets/9695e4ac-b858-41fd-9eb2-c082636dde2c

### :DeltaMenu demo
https://github.com/user-attachments/assets/4035f361-e890-41c4-8b82-f57f5491b665

## Features

- **Inline diff viewing**: Lay lightweight diffs over your buffers to quickly view and unview changes
- **Two-tier highlighting**: Two tier diff highlighting, treesitter syntax highlighting
- **Cursor maintenance**: Opening a diff keeps your cursor where it was, and exiting a diff keeps your cursor where it was. Easily transition between reading and writing.
- **Quick Navigation**: Jump to the next hunk with `<Tab>`. Review all changes in a PR using the quickfix list workflow (`:DeltaMenu!`). Integration with popular fuzzy finders to find files that have been modified.
- **Smart sorting**: Files opened by the picker are sorted by quantity of changes, allowing you to review the most important files first.
- **Custom Context**: Choose how many lines of context to see when diffing a path. No folds to interfere with smooth scrolling.
- **Flexible comparisons**: Compare against any git ref (HEAD, branches, commits, tags)

## Requirements

- Neovim >= 0.10
- Git
- (Optional) An fzf picker of your choice. Currently supports
    - [fzf-lua](https://github.com/ibhagwan/fzf-lua)
    - [telescope](https://github.com/nvim-telescope/telescope.nvim)

*NOTE*
- This plugin does not use [delta](https://github.com/dandavison/delta), and it is not a dependency

## Usage

Using deltaview revolves around three user commands. `:DeltaView` brings up the delta diff view on the file you are on, `:Delta` brings up a special delta diff view that more closely resembles the original git-delta, and `:DeltaMenu` brings up a picker that allows you to jump to the diff view of a file in the diff. These commands all come with default keybinds (see |deltaview-keybindings|) as the intended user experience involves bringing the diff view up and closing it frequently.

No `require('deltaview').setup` command is required, though one is made available for configuration. deltaview.nvim is by default, (pseudo) lazy loaded. This means there is little benefit to using a plugin manager like lazy.nvim, but users of vim.pack, vim plug, and non lazy loading plugins will have good startup times. All user commands and keybinds are made available at startup, but the main modules aren't loaded until the initial interaction with deltaview.

### Commands

#### `:DeltaView [ref]`

Opens the delta diff view on the buffer you are on. Uses the last ref that was used (across any `:Delta[View][Menu]` command), or HEAD. Meant to be used when the "after" of the diff matches the current state of your buffer. In other words, this works well when diffing a modified file against HEAD, or diffing a file that hasn't been changed. The cursor is placed at the matching location on entry, and placed at the matching location on exit

```vim
:DeltaView                  " Compare current file against HEAD
:DeltaView main             " Compare against main branch
:DeltaView HEAD~3           " Compare against 3 commits ago
:DeltaView v1.0.0           " Compare against tag v1.0.0
```

#### `:Delta [path] [context] [ref]`

Opens the delta diff view for the current path. Attempts to place the cursor on entry if there is a corresponding line in the diff. Cursor will sync on exit, same as DeltaView. Uses the last ref that was used, or HEAD. Uses the last specified context size, or 3. Uses the current path; can be useful if if you use netrw to be on a path, or just diff a file. Modifiable context can be useful for searching your changed code, such as looking for stray print statements

```vim
:Delta .                    " Show all files changed from HEAD, with +- 3 lines of context by default
:Delta . 10 main...HEAD     " Show all files changed from the common ancestor with the main branch, with 10 lines of context, for everything in the cwd
```

#### `:DeltaMenu [ref]`

Opens a picker to select among diffed files and view its diff. Uses the last ref that was used, or HEAD. Picker priority: fzf-lua -> telescope -> vim.ui.select

```vim
:DeltaMenu                  " Show all files changed from HEAD
:DeltaMenu develop          " Show all files changed from develop branch
:DeltaMenu develop...HEAD   " Show all files changed from the common ancestor with the develop branch
```

#### `:DeltaMenu! [ref]`

Populates the quickfix list with all changed files and opens it. The quickfix list acts as an alternative native picker that stays open. Opening a file on the quickfix list automatically opens to `:DeltaView`.

Once the list is open:
- Navigate with `]q` / `[q` (or `:cnext` / `:cprev`) — opening any listed file automatically opens its DeltaView diff
- Use `:colder` or `:cex []` to manually restore the previous quickfix list and exit the review workflow

```vim
:DeltaMenu! develop...HEAD   " Show all files changed from the common ancestor with the develop branch in the quickfix list
```

**Recommendations**:

Set abbreviations for the common commands, as they can be long. While keybinds for each command exist, commands will often be typed in normal workflow to specify the [ref].

```lua
vim.cmd([[cabbrev dm DeltaMenu]])
vim.cmd([[cabbrev dv DeltaView]])
vim.cmd([[cabbrev da Delta . 3]])
```

*NOTE*: 
- All commands use the last ref used. If `:DeltaMenu main` was used, future calls to `:DeltaMenu`, `:DeltaView`, and `:Delta` will default to `main` instead of `HEAD`.
- All support special git syntaxes (e.g. `develop...HEAD` for the symmetric difference, or "what did this branch introduce")

### Keybinds

This plugin comes prepackaged with some default keybinds, which are viewable by using the `d?` keybind when on a a buffer created by `:Delta` or `:DeltaView`.

Global keybindings:

| Key           | Action        |
| ------------- | ---------     |
| `<leader>dl`  | :DeltaView    |
| `<leader>dm`  | :DeltaMenu    |
| `<leader>da`  | :Delta        |

When viewing a diff (DeltaView or Delta):

| Key           | Action                                    |
| ------------- | ----------------------------------------- |
| `<Esc>` or `q`| Return to source file                     |
| `<Tab>`       | Next hunk                                 |
| `<S-Tab>`     | Previous hunk                             |
| `d?`          | Open the help legend                      |

*NOTE*
- `<Tab>` and `<Shift-Tab>` deviate from the original neovim diff motions of 
`]c` and `[c`. These keys behave differently; no count support for deltaview's
next hunk (meaning no equivalent to 3]c for "jump 3 hunks"), and deltaview's
next hunk will cycle: if you are on the last hunk, you jump to the
first hunk with the next `<Tab>`. Furthermore, I just prefer the tabindex like
motions, which require one hand. If you prefer the original motions, overwrite
`keyconfig.next_hunk` and `keyconfig.prev_hunk` in |deltaview-configuration|

- `<Tab` overwrites the default vim motion `<Tab>` (see `:h <Tab>`), which is
just an alternative for `CTRL-I`. If this is an issue for your workflow, 
please overwrite the configuration.

When the DeltaMenu quickfix list is open (:DeltaMenu!):

| Key           | Action                                    |
| ------------- | ----------------------------------------- |
| `]q`          | Open next file and view its diff          |
| `[q`          | Open previous file and view its diff      |

## Installation

[vim.pack](https://github.com/neovim/neovim/pull/34009)

```lua
vim.pack.add('https://github.com/kokusenz/deltaview.nvim')
```

Or your favorite plugin manager, such as [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
-- note that there is probably no lazy.nvim benefit, as this plugin is lazy loaded by default
{
    'kokusenz/deltaview.nvim',
}
```

## Configuration

### Full Configuration Example

```lua
require('deltaview').setup({
    -- disable nerd font icons if uninstalled (defaults to true)
    use_nerdfonts = false,

    -- will show the delta style line numbers in the statuscolumn.
    line_numbers = false,

    -- override the picker for :DeltaMenu. If nil, auto-detects in order:
    -- fzf-lua -> telescope -> vim.ui.select
    fzf_picker = nil, -- 'fzf-lua' | 'telescope' | 'ui_select' | nil

    -- custom keybindings
    keyconfig = {
        -- global keybind to toggle DeltaMenu
        dm_toggle_keybind = "<leader>dm",

        -- global keybind to toggle DeltaView (and exit diff if open)
        dv_toggle_keybind = "<leader>dl",

        -- global keybind to toggle Delta (and exit diff if open)
        d_toggle_keybind = "<leader>da",

        -- navigate between hunks in a diff
        next_hunk = "<Tab>",
        prev_hunk = "<S-Tab>",

        -- open help legend
        help_legend = "d?"
    }
})

-- for configuration of how the diff buffers look
require('delta').setup({
    -- default lines of context around each hunk.
    context = 3,

    highlighting = {
        -- minimum Levenshtein similarity (0.0–1.0) for two lines to be
        -- paired for word-level highlighting. The lower the number, the
        -- less similar two lines have to be to get word level
        -- highlighting. Matches delta's --max-line-distance option.
        max_similarity_threshold = 0.6,
    },

    -- Highlight group definitions, separated by background type.
    -- Each group accepts `fg`, `bg`, and `default` (boolean).
    -- When `default = true` the group will not override default colors
    -- To write a custom color, include default = false
    -- the examples have default = false, but the colors are the defaults
    highlight_groups = {
        dark = {
            DeltaDiffAddedLine = {
                bg = '#002800',  -- dark green background
                default = false
            },
            DeltaDiffRemovedLine = {
                bg = '#3f0001',  -- dark red background
                default = false
            },
            DeltaDiffAddedWord = {
                bg = '#006000',  -- brighter green
                default = false
            },
            DeltaDiffRemovedWord = {
                bg = '#901011',  -- brighter red
                default = false
            },
            DeltaTitle = {
                fg = '#24acd4',  -- light blue
                default = false
            },
            DeltaLineNrAdded = {
                fg = '#008400',  -- darker green for added line numbers
                default = false
            },
            DeltaLineNrRemoved = {
                fg = '#800202',  -- darker red for removed line numbers
                default = false
            },
            DeltaLineNrContext = {
                fg = '#444444',  -- darker gray for context line numbers
                default = false
            }
        },
        light = {
            DeltaDiffAddedLine = {
                bg = '#cfffd0',  -- light green background
                default = false
            },
            DeltaDiffRemovedLine = {
                bg = '#ffdee2',  -- light red background
                default = false
            },
            DeltaDiffAddedWord = {
                bg = '#9df0a2',  -- darker green (word level)
                default = false
            },
            DeltaDiffRemovedWord = {
                bg = '#ffc1bf',  -- darker red (word level)
                default = false
            },
            DeltaTitle = {
                fg = '#0088aa',  -- darker blue for light backgrounds
                default = false
            },
            DeltaLineNrAdded = {
                fg = '#008400',  -- darker green for added line numbers
                default = false
            },
            DeltaLineNrRemoved = {
                fg = '#800202',  -- darker red for removed line numbers
                default = false
            },
            DeltaLineNrContext = {
                fg = '#444444',  -- darker gray for context line numbers
                default = false
            }
        },
    },
})
```

## Troubleshooting
- `:help deltaview`
- Reach out via an issue
- Read the changelog for changes or breaking changes
