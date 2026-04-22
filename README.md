# deltaview.nvim

An inline diff viewer for Neovim using [delta.lua](https://github.com/kokusenz/delta.lua). Delta.lua is a partial recreation of the [delta](https://github.com/dandavison/delta) pager. Delta.lua provides two tier diff highlighting and syntax highlighting, while deltaview.nvim controls the behavior of how the user wants to view these diffs. It is lightweight, designed to be opened and closed quickly. This allows the user to use their lsp while reviewing changes, yank deleted lines of code, and navigate around a pull request naturally, rather than being forced into using a filetree.

![DeltaView Screenshot](https://github.com/user-attachments/assets/d4d1e8aa-7fd1-4759-b658-45ca468c18fa)

## Why?

Current inline/unified diff viewers in neovim tend to use virtual lines to display negative changes. Cursors cannot land on virtual lines, which disrupts scrolling, and lacks the ability to copy lines of code that were deleted. With a large block of negative changes that does not fit in the window's viewport, the user cannot even see the full extent of the changes.

This plugin's approach is to treat inline diffs as readonly, separate buffers. Separate buffers allows us to display these diffs without virtual lines, with plenty of features that allows these buffers to integrate seamlessly into your coding experience.

## Demos

### :DeltaView demo
https://github.com/user-attachments/assets/6a28f113-9462-4568-93ca-6db6e7f8be97

### :Delta demo
https://github.com/user-attachments/assets/9695e4ac-b858-41fd-9eb2-c082636dde2c

### :DeltaMenu demo
https://github.com/user-attachments/assets/b4f7cac3-3d96-4a4b-9076-98cd8a33c7d6

## Features

- **Inline diff viewing**: Lay lightweight diffs over your buffers to quickly view and unview changes
- **Delta.lua highlighting**: Two tier diff highlighting, treesitter syntax highlighting
- **Cursor maintenance**: Opening a diff keeps your cursor where it was, and exiting a diff keeps your cursor where it was. Easily transition between reading and writing.
- **Quick Navigation**: Jump to the next hunk with "<Tab>", and jump to the next file with "]f". Integration with popular fuzzy finders to find files that have been modified.
- **Smart sorting**: Files opened by the picker are sorted by quantity of changes, allowing you to review the most important files first.
- **Custom Context**: Choose how many lines of context to see when diffing a path. No folds to interfere with smooth scrolling.
- **Flexible comparisons**: Compare against any git ref (HEAD, branches, commits, tags)

## Requirements

- Neovim >= 0.10
- Git
- [delta.lua](https://github.com/kokusenz/delta.lua). Install this separately into your neovim config using the plugin manager of your choice.
- (Optional) An fzf picker of your choice. Currently supports
    - [fzf-lua](https://github.com/ibhagwan/fzf-lua)
    - [telescope](https://github.com/nvim-telescope/telescope.nvim)

Note that this plugin does not use [delta](https://github.com/dandavison/delta), and it is not a dependency

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

Open an picker to preview, select, and view diffs from all modified files.

```vim
:DeltaMenu                  " Show all files changed from HEAD
:DeltaMenu develop          " Show all files changed from develop branch
:DeltaMenu develop...HEAD   " Show all files changed from the common ancestor with the develop branch
```

#### `:Delta [path] [context] [ref]`

Open the inline delta diff view for the current path. This view has a configurable amount of context to show alongside your diff hunks. Attempts to place the cursor on entry if there is a corresponding line in the diff. Will sync the cursor on exit, same as DeltaView.
This works on both files and directories, by being in a directory path using netrw or some other filetree plugin. This can be useful for if you want to diff specific directories rather than the whole git directory. 
If you are unable to navigate to a directory because you use something like [oil.nvim](https://github.com/stevearc/oil.nvim), you can pass the path as an argument
Context can be specified. This can be useful for searching your modified code (eg. looking for stray print statements).

```vim
:Delta                      " Show all files changed from HEAD, with +- 3 lines of context by default
:Delta . 10 main...HEAD     " Show all files changed from the common ancestor with the main branch, with 10 lines of context, for everything in the cwd
```

**Note**: 
- All commands use the last ref used. If `:DeltaMenu main` was used, future calls to `:DeltaMenu`, `:DeltaView`, and `:Delta` will default to `main` instead of `HEAD`.

## Installation

[vim.pack](https://github.com/neovim/neovim/pull/34009)

```lua
vim.pack.add({
    'https://github.com/kokusenz/deltaview.nvim'
    'https://github.com/kokusenz/delta.lua'
})
```


Or your favorite plugin manager, such as [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'kokusenz/deltaview.nvim'
    dependencies = {
        "kokusenz/delta.lua",
    },
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
| `]f` | Open next file in menu (if opened from DeltaMenu, or in Delta with multiple files) |
| `[f` | Open previous file in menu (if opened from DeltaMenu, or in Delta with multiple files) |
| `d?` | Open the help legend, to view all possible keybinds |

All keybindings are configurable

## Configuration

### Full Configuration Example

```lua
require('deltaview').setup({
    -- Disable nerd font icons if uninstalled (defaults to true)
    use_nerdfonts = false,

    -- Show both previous and next filenames when navigating
    -- false: shows "[2/5] -> next.lua"
    -- true: shows "<- prev.lua [2/5] -> next.lua"
    show_verbose_nav = false,

    -- Configures the position of the quick select opened by DeltaMenu when under the fzf_threshold
    -- 'hsplit': horizontal split window
    -- 'center': centered floating window
    -- 'bottom': centered at the bottom, floating window
    quick_select_view = 'hsplit',

    -- Number of files threshold for switching to fzf
    -- When the number of modified files >= this value, use fzf instead of quickselect
    fzf_threshold = 0,

    -- If this setting is true, will show the delta style line numbers in the statuscolumn.
    line_numbers = false,

    -- 'fzf-lua' | 'telescope' | nil - specify which picker to use. If nil, will go through the order and pick the first available. The order is fzf-lua -> telescope -> deltaview quickselect
    fzf_picker = nil

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

        -- Navigate between files (when opened from DeltaMenu)
        next_diff = "]f",
        prev_diff = "[f",

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
    vs = "", -- nf-seti-git, "versus" symbol in menu header
    next = "󰁕", -- nf-md-arrow_right_thick, next file indicator
    prev = "󰁎", -- nf-md-arrow_left_thick, previous file indicator
    segment = "󰻋", -- nf-md-segment , hunk count indicator
    file = "󰈔" -- nf-md-file
}

-- Without nerd fonts
{
    dot = "·",
    circle = "•",
    vs = "comparing to",
    next = "->",
    prev = "<-",
    segment = "≡",
    file = "🗎"
}
```

## Troubleshooting
- :help DeltaView
- Reach out via an issue

## Feature Roadmap

- Options for using the pickers in:
    - [mini.pick](https://github.com/nvim-mini/mini.pick)
    - [snacks](https://github.com/folke/snacks.nvim)
- Diff two blocks of text against each other; given a yanked section and a visual selected section, vim.text.diff what's in the register against what's highlighted, and display using delta.lua
- AI Agent integration such that proposed changes are displayable with delta.lua
- Allow bundling, such that users can install only deltaview.nvim without having to install delta.lua
