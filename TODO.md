**Features**
__1. picker integration
    - fzf-lua
    - snacks
    - telescope
    - mini
TODO with delta.lua, I think I can handle this in this branch, and given the refactoring work related to deltamenu anyways, this will be touched. Will be a relatively large pr, but I will double check triple check everything__
__3. quick select for current from deltamenu; if your current buffer is in the list, it appears at the top (fzf, and quick select)
    - for quickselect, bold the top entry and put some indication that its at the top because it's current
    - for fzf, explore what features each picker has
TODO with delta.lua, I think I should be able to handle this as well, and this is a high priority feature__
_4. support light mode DONE WITH DELTA.LUA_
__4. a wrapper for 3 dot ref (:Review) TODO WITH DELTA.LUA__`
__5. Could show a fuzzy finder item for the overall delta diff. Think about it. TODO WITH DELTA.LUA__
__8. hide hunk_cmd_ui behind a feature flag, make it not default. Make an exposable "get info" function and keybind, and it should just echo what info the cmd ui currently displays (current ref, hunk progress, next file if relevant, etc). If I want, I can add back the hunk cmd_ui later as its own toggleable thing, but let's not make it part of the same code that currently exists. Currently, it's coupled pretty hard with the display code because I don't want to parse the things twice, but I don't need to worry about that now because I have all the metadata as a vim buffer variable TODO WITH DELTA.LUA__
5. blame
6. grep
7. diff two blocks of text against each other; given a yanked section and a visual selected section, vim.text.diff what's in the register against what's highlighted, show a small float window (that doesn't take full screen) with diff
8. mini.diff extension that opens a delta buffer on a mini.diff diff. allows usage with codecompanion workflows
9. view the diff between branches commit by commit; put into an ordered quickfix list such that you can view the history of patches applied to a branch to end up where it did

**Tech Debt / Chores**
2. record new demos (one for each function)
_3. unit tests DONE WITH DELTA.LUA_
4. todo everything in the awesome-lint
5. create checkhealth
__6. make deltamenu work even when with cwd as root directory. git status works from anywhere in a subdirectory, just make deltamenu behave the same way. No need to filter. TODO WITH DELTA.LUA__
__7. make delta function arguments better, more details in comments TODO WITH DELTA.LUA__

**Bugs**
__1. handling wrapped lines (in todo comments in code) DONE WITH DELTA.LUA, verify this works__
__2. size of changes for new files is not properly processed or stored TODO WITH DELTA.LUA__
__3. hunk nav for when line numbers are out of order bugs out TODO WITH DELTA.LUA. once this is fixed, and the 1000 context bug is fixed, close the issue on github__
__4. delta with 1000 context if files are less than that will bug out, DONE WITH DELTA.LUA verify this works__
__5. highlighting can persist when using other methods besides esc to nav in and out of a delta buffer TODO WITH D.L__
4. <f3><b0><a7> in cmdui when concatenated
6. deleted files should not be able to be nav'd to in the deltamenu


**Articulating Things**
### advantages of delta.lua in deltaview, instead of delta
treesitter syntax highlighting, 
support for light colorschemes, 
treesitter based two tier highlighting, 
responds to buffer size changes
better parsing that handles git artifacts in code and better hunk navigation (this is a theory and a todo to verify, via testing the circular hunk navigation bug)

### separation of responsibilities between deltaview and delta.lua
deltaview controls the behavior of how users initiate and view diffs, while delta.lua controls what those diffs look like. For example, deltaview allows the user to enter a diff at the cursor position they were on at the original buffer, and leave the diff at the cursor position they were on in the diff buffer. Delta.lua creates buffers with proper syntax highlighting and diff highlighting

### advantages of deltaview/delta.lua over other diff viewers
deltaview allows the user to copy deleted lines.
    - a handy use case is when you are refactoring, and know this block of code needs to be deleted, but you are unsure if you want to copy paste certain lines from it later. Feel free to comfortably delete it rather than commenting it out, and yank the line from it later
delta.lua and delta has two tier highlighting on deleted lines
delta.lua and delta does not contain extmarks that disrupt scrolling or movement (such as virtual lines)
large blocks of deleted code are fully scrollable with delta.lua and delta
before/after line numbers are fully visible with delta.lua and delta


CONSTRUCTING THE PR MESSAGE, ARTICULATING CHANGES
refactored much of the logic originally in diff.lua out to other files. In the interest in keeping backwards compatibility without doing too much work, i've left a lot of code duplicated between the modern and legacy flow, and I have not refactored to optimize the legacy flow.
