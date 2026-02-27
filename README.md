# deltaview.nvim

An inline diff viewer for Neovim using [delta](https://github.com/dandavison/delta) (git-delta). The delta pager provides two tier highlighting, and deltaview.nvim brings the unified/inline view into a buffer that lays on top of your current buffer. View and navigate your diffs seamlessly while reading and writing code.

![DeltaView Screenshot](https://github.com/user-attachments/assets/dc6c5bb4-ef7d-40fb-9c6e-de2e4ac7378a)

## Why?

Current inline/unified diff viewers in neovim tend to use virtual lines to display negative changes. Cursors cannot land on virtual lines, and a large scope of negative changes will be skipped over when scrolling through a file, making it an unintuitive and flawed way to view a diff.

This plugin takes a less intrusive approach; display the delta pager output in a terminal buffer. These buffers are temporary and integrate seamlessly within a coding experience, using configurable keybinds to quickly swap in and out. Have you ever felt like you needed your lsp while reviewing a PR in your browser? Review the changes in neovim, using deltaview.nvim, and follow the code with your keyboard instead of your eyes.

If you aren't looking for an inline diff view, or are just looking for a code review tool that is mature and feature rich, [codediff.nvim](https://github.com/esmuellert/codediff.nvim/blob/main/README.md) may be a better fit for you. This is a tool for those who prefer inline diff views.

## Demo

https://github.com/user-attachments/assets/ef732ea7-e2b5-4167-8d9d-f12052f94c9d

## Features

- **Inline diff viewing**: View diffs on top of your code using delta's syntax highlighting
- **Custom Context**: Choose how many lines of context to see when diffing a path
- **Cursor maintenance**: Viewing a diff from a buffer keeps your cursor where it was, and viewing code from a diff keeps your cursor where you want it to be. Easily transition between reading and writing.
- **Custom File Picker**: Review a large scope of changes
- **Custom UI**: Visual Indicators for hunk and file count
- **FZF integration**: Quick picker turns into a fuzzy finder picker for a large list of files
- **Smart sorting**: Files are sorted by quantity of changes
- **Flexible comparisons**: Compare against any git ref (HEAD, branches, commits, tags)

## Requirements

- Neovim >= 0.9
- [delta](https://github.com/dandavison/delta) (git-delta)
- Git
- (Optional) [fzf](https://github.com/junegunn/fzf) for a fuzzy finder

## Usage

### Commands

#### `:DeltaView [ref]`

Open an inline diff view for the current file.
This uses Delta's syntax highlighting to mock an inline view of the full file with two way cursor tracking. The cursor is placed at the right location upon entry, and placed at the right location upon exit.

```vim
:DeltaView           " Compare current file against HEAD
:DeltaView main      " Compare against main branch
:DeltaView HEAD~3    " Compare against 3 commits ago
:DeltaView v1.0.0    " Compare against tag v1.0.0
```

#### `:DeltaMenu [ref]`

Open an interactive menu to select and view diffs from all modified files.

```vim
:DeltaMenu           " Show all files changed from HEAD
:DeltaMenu develop   " Show all files changed from develop branch
```

#### `:Delta [ref] [context] [path]`

Open the inline delta diff view for the current path. Does not have two way cursor tracking like DeltaView. <CR> to jump to the cursor is on.
This works on both files and directories, by being in a directory path using netrw or some other filetree plugin. This can be useful for if you want to diff specific directories rather than the whole git directory. 
If you are unable to navigate to a directory because you use something like [oil.nvim](https://github.com/stevearc/oil.nvim), you can pass the path as an argument
Context can be specified. This can be useful for searching your modified code (eg. looking for stray print statements).

```vim
:Delta               " Show all files changed from HEAD, with +- 3 lines of context by default
:Delta HEAD 0        " Show all files changed from HEAD, with no lines of context.
:Delta HEAD 10 src/   " Show all files changed from HEAD, with 10 lines of context, for everything in src/
```

**Note**: 
- All commands use the last ref used. If `:DeltaMenu main` was used, future calls to `:DeltaMenu`, `:DeltaView`, and `:Delta` will default to `main` instead of `HEAD`.
- This plugin requires Neovim's current working directory (`:pwd`) to be the git repository root. Use `:cd` to navigate to the git root if needed.

## Installation

[vim.pack](https://github.com/neovim/neovim/pull/34009)

```lua
vim.pack.add({ 'https://github.com/kokusenz/deltaview.nvim.git'})
```

Or your favorite plugin manager:

```lua
-- example: vim plug
Plug('kokusenz/deltaview.nvim')
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

The fzf file picker might be available out of the box, depending on how it was installed. If it does not work, you may need [additional setup](https://github.com/junegunn/fzf/blob/master/README-VIM.md) in your neovim config. Try adding the fzf binary to your `&runtimepath`, or installing fzf's vim integration using a package manager.

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

When viewing a diff (Delta):

| Key | Action |
|-----|--------|
| `<CR>` | Jump to line |

When in the file menu:

| Key | Action |
|-----|--------|
| Select a file | Open diff for that file |
| `alt-;` | Change fzf to quickselect (in fzf mode) |

All keybindings are configurable

## Configuration

### Full Configuration Example

```lua
require('deltaview').setup({
  -- Use delta.lua as the diff viewer if true, uses dandavison/delta if false
  use_delta_lua = true

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
  -- Set to 0 or 1 to always use fzf
  fzf_threshold = 6,

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

    -- Change diff menu view to quickselect (when in fzf mode)
    fzf_toggle = "alt-;",

    -- Jump to line in view opened by Delta
    jump_to_line = "<CR>"
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
  prev = "󰁎" -- nf-md-arrow_left_thick, previous file indicator
}

-- Without nerd fonts
{
  dot = "·",
  circle = "•",
  vs = "comparing to",
  next = "->",
  prev = "<-"
}
```

## Troubleshooting
- :help DeltaView
- Reach out via an issue

## Feature Roadmap

- Options for using the pickers in:
    - [fzf-lua](https://github.com/ibhagwan/fzf-lua)
    - [telescope](https://github.com/nvim-telescope/telescope.nvim)
    - [snacks](https://github.com/folke/snacks.nvim)
- delta blame view
- delta grep. Originally, didn't see the value because many fuzzy finding plugins handle grepping, but putting all greps with lines of context in one buffer allows for searching amongst the context of grepped code. Delta provides nice formatting.

## Contributing

Contributions are welcome. CONTRIBUTING.md coming soon.
