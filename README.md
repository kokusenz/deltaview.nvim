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

**Note**
- This plugin does not use [delta](https://github.com/dandavison/delta), and it is not a dependency

## Usage

### Commands

#### `:DeltaView [ref]`

Open an inline diff view for the current file. The cursor is placed at the current location upon entry, and placed at the current location on exit

```vim
:DeltaView                  " Compare current file against HEAD
:DeltaView main             " Compare against main branch
:DeltaView HEAD~3           " Compare against 3 commits ago
:DeltaView v1.0.0           " Compare against tag v1.0.0
```

#### `:DeltaMenu [ref]`

Opens a picker to select a file and view its diff. Picker priority: fzf-lua → telescope → vim.ui.select.

```vim
:DeltaMenu                  " Show all files changed from HEAD
:DeltaMenu develop          " Show all files changed from develop branch
:DeltaMenu develop...HEAD   " Show all files changed from the common ancestor with the develop branch
```

#### `:DeltaMenu! [ref]`

Populates the quickfix list with all changed files and opens it. Each entry shows the file status (M/A/D/R/...) and change size. Intended for reviewing all changes in a PR or branch.

Once the list is open:
- Navigate with `]q` / `[q` (or `:cnext` / `:cprev`) — opening any listed file automatically opens its DeltaView diff
- Use `:colder` or `:cex []` to manually restore the previous quickfix list and exit the review workflow

#### `:Delta [path] [context] [ref]`

Open the inline delta diff view for the current path. This view has a configurable amount of context to show alongside your diff hunks. Attempts to place the cursor on entry if there is a corresponding line in the diff. Will sync the cursor on exit, same as DeltaView.
This works on both files and directories, by being in a directory path using netrw or some other filetree plugin. This can be useful for if you want to diff specific directories rather than the whole git directory. 
If you are unable to navigate to a directory because you use something like [oil.nvim](https://github.com/stevearc/oil.nvim), you can pass the path as an argument
Context can be specified. This can be useful for searching your modified code (eg. looking for stray print statements).

```vim
:Delta                      " Show all files changed from HEAD, with +- 3 lines of context by default
:Delta . 10 main...HEAD     " Show all files changed from the common ancestor with the main branch, with 10 lines of context, for everything in the cwd
```

**Recommendations**:

Set abbreviations for the common commands, as they can be long. While keybinds for each command exist, commands will often be typed in normal workflow to specify the [ref].
```lua
vim.cmd([[cabbrev dm DeltaMenu]])
vim.cmd([[cabbrev dv DeltaView]])
```

**Note**: 
- All commands use the last ref used. If `:DeltaMenu main` was used, future calls to `:DeltaMenu`, `:DeltaView`, and `:Delta` will default to `main` instead of `HEAD`.

### Keybinds

This plugin comes prepackaged with default keybinds, which are viewable by using the `d?` keybind when on a a buffer created by `:Delta` or `:DeltaView`.

## Installation

[vim.pack](https://github.com/neovim/neovim/pull/34009)

```lua
vim.pack.add('https://github.com/kokusenz/deltaview.nvim')
```

Or your favorite plugin manager, such as [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'kokusenz/deltaview.nvim',
}
```

No setup needed by default. You can configure if you want:

```lua
require('deltaview').setup({
    -- configuration here
    -- example:
    keyconfig = {
        dv_toggle_keybind = "<leader>dd"
    },
    use_nerdfonts = false
})
```

### Default Keybindings

| Key | Action |
|-----|--------|
| `<leader>dl` | :DeltaView |
| `<leader>dm` | :DeltaMenu |
| `<leader>da` | :Delta |

When viewing a diff (DeltaView or Delta):

| Key | Action |
|-----|--------|
| `<Esc>` or `q` | Return to source file |
| `<Tab>` | Jump to next hunk |
| `<Shift-Tab>` | Jump to previous hunk |
| `d?` | Open the help legend, to view all possible keybinds |

**Note**
- `<Tab>` and `<Shift-Tab>` deviate from the original neovim diff motions of `]c` and `[c`. These keys behave differently; no count support for deltaview's next hunk (meaning no equivalent to 3]c for "jump 3 hunks down"), and deltaview's next hunk will cycle, meaning that if you are on the last hunk, you jump to the first hunk with the next `<Tab>` . Furthermore, I just prefer the tabindex like motions, which require only one hand. If you prefer the original neovim motions, please overwrite `keyconfig.next_hunk` and `keyconfig.prev_hunk` in configuration (see "Configuration" in README or `:h deltaview-configuration`).
- `<Tab>` overwrites the default vim motion `<Tab>` (see `:h <Tab>`), which is just an alternative for `CTRL-I`. If this is an issue for your workflow, please overwrite the configuration. I find having a jump list in the deltaview buffer to be infrequent.

When the DeltaMenu quickfix list is open (`:DeltaMenu!`):

| Key | Action |
|-----|--------|
| `]q` | Open next file and view its diff |
| `[q` | Open previous file and view its diff |
| `:colder` or `:cex []` | Restore previous quickfix list, exiting the DeltaMenu workflow |

All keybindings are configurable

## Configuration

### Full Configuration Example

```lua
require('deltaview').setup({
    -- Disable nerd font icons if uninstalled (defaults to true)
    use_nerdfonts = false,

    -- If this setting is true, will show the delta style line numbers in the statuscolumn.
    line_numbers = false,

    -- Specify which picker to use for :DeltaMenu. If nil, auto-detects in order:
    -- fzf-lua -> telescope -> vim.ui.select
    -- 'ui_select' uses vim.ui.select directly, which respects whatever you have
    -- registered as your vim.ui.select handler. Useful for a fuzzy picker without
    -- a preview window (e.g. require('fzf-lua').register_ui_select()).
    fzf_picker = nil, -- 'fzf-lua' | 'telescope' | 'ui_select' | nil

    -- Custom keybindings
    keyconfig = {
        -- Global keybind to toggle DeltaMenu
        dm_toggle_keybind = "<leader>dm",

        -- Global keybind to toggle DeltaView (and exit diff if open)
        dv_toggle_keybind = "<leader>dl",

        -- Global keybind to toggle Delta (and exit diff if open)
        d_toggle_keybind = "<leader>da",

        -- Navigate between hunks in a diff
        next_hunk = "<Tab>",
        prev_hunk = "<S-Tab>",

        -- Open help legend
        help_legend = "d?"
    }
})
```

### View Configuration

By default, the UI uses nerd font icons:

```lua
-- With nerd fonts (default)
{
    dot = "󰧟", -- nf-md-circle_small, hunk indicator
    circle = "󰧞", -- nf-md-circle_medium, current hunk indicator
    vs = "", -- nf-seti-git, "versus" symbol in menu header
    segment = "󰻋", -- nf-md-segment , hunk count indicator
    file = "󰈔" -- nf-md-file
}

-- Without nerd fonts
{
    dot = "·",
    circle = "•",
    vs = "comparing to",
    segment = "≡",
    file = "🗎"
}
```

## Troubleshooting
- :help deltaview 
- Reach out via an issue
- Read the changelog for changes or breaking changes
