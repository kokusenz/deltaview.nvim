local M = {}

--- check if current working directory matches git root directory
--- @return boolean True if cwd matches git root
M.is_cwd_git_root = function()
    local git_root = vim.fn.system({'git', 'rev-parse', '--show-toplevel'})
    if vim.v.shell_error ~= 0 then
        return false
    end
    git_root = vim.trim(git_root)
    local cwd = vim.fn.getcwd()
    return cwd == git_root
end

--- Get list of modified and untracked files
--- @param ref string|nil Git ref to compare against (defaults to HEAD if nil). If nil, includes untracked files
--- @return SortedFiles list of file paths that have been modified or are untracked
M.get_diffed_files = function(ref)
    -- diffed files
    local diffed = vim.fn.system({'git', 'diff', ref ~= nil and ref or 'HEAD', '--name-only'})
    if vim.v.shell_error ~= 0 and vim.v.shell_error ~= 1 then
        print('ERROR: Failed to get diff files from git')
        diffed = ''
    end

    -- new untracked files
    local untracked = vim.fn.system({'git', 'ls-files', '-o', '--exclude-standard'})
    if vim.v.shell_error ~= 0 and vim.v.shell_error ~= 1 then
        print('ERROR: Failed to get untracked files from git')
        untracked = ''
    end

    local files = {}
    local seen = {}

    for match in (diffed .. untracked):gmatch('[^\n]+') do
        if not seen[match] and match ~= '' then
            table.insert(files, match)
        end
    end

    local sortedfiles = M.sort_diffed_files(files, ref)
    return sortedfiles
end

--- @param files table list of diffed files
--- @param ref string | nil target ref
--- @return SortedFiles sorted files
M.sort_diffed_files = function(files, ref)
    local dirstat = vim.fn.system({'git', 'diff', ref ~= nil and ref or 'HEAD', '-X', '--dirstat=lines,0'})
    if vim.v.shell_error ~= 0 and vim.v.shell_error ~= 1 then
        print('ERROR: Failed to get diff files from git')
        return {}
    end

    -- parse dirstat to get directory percentages: "percentage% dirname/"
    local dir_stats = {}
    for line in dirstat:gmatch('[^\n]+') do
        local percentage, dirname = line:match('%s*([%d%.]+)%%%s+(.+)')
        if percentage and dirname then
            dir_stats[dirname] = tonumber(percentage)
        end
    end

    local files_w_stats = {}
    for _, file in ipairs(files) do
        local numstat = vim.fn.system({'git', 'diff', '--numstat', ref ~= nil and ref or 'HEAD', '--', file})
        if vim.v.shell_error ~= 0 and vim.v.shell_error ~= 1 then
            print('ERROR: Failed to lines of code for a diffed file')
            return {}
        end
        local added, removed = string.match(numstat, "(%d+)%s+(%d+)%s+")

        --- @class DiffNumstat
        --- @field added number
        --- @field removed number
        local parsed_numstat = {added = added, removed = removed }
        files_w_stats[file] = parsed_numstat
    end

    local function get_parent_dirs(filepath)
        local dirs = {}
        local parts = {}

        for part in filepath:gmatch('[^/]+') do
            table.insert(parts, part)
        end

        -- Build directory paths at each level (e.g., "lua/", "lua/deltaview/")
        for i = 1, #parts - 1 do
            local dir_path = table.concat(parts, '/', 1, i) .. '/'
            table.insert(dirs, dir_path)
        end

        return dirs
    end

    local function get_dir_percentage(dir_path)
        return dir_stats[dir_path] or 0
    end

    -- Build sorted_files with metadata: { name, added, removed }
    --- @class SortedFile
    --- @field name string
    --- @field added number
    --- @field removed number

    --- @alias SortedFiles SortedFile[]
    local sorted_files = {}
    for _, file in ipairs(files) do
        local stats = files_w_stats[file]
        table.insert(sorted_files, {
            name = file,
            added = tonumber(stats.added) or 0,
            removed = tonumber(stats.removed) or 0
        })
    end

   -- helper function to get the most specific directory with dirstat data
    local function get_most_specific_dir(filepath)
        local dirs = get_parent_dirs(filepath)
        -- iterate from deepest to shallowest
        for i = #dirs, 1, -1 do
            local dir_path = dirs[i]
            if dir_stats[dir_path] then
                return dir_path
            end
        end
        return nil
    end

    -- sort files by directory weight
    -- 1. by most specific directory's dirstat % (highest first)
    -- 2. files in same directory by total line changes (highest first)
    -- 3. alphabetically for ties
    table.sort(sorted_files, function(a, b)
        local a_file = a.name
        local b_file = b.name

        -- get the most specific directory for each file
        local a_dir = get_most_specific_dir(a_file)
        local b_dir = get_most_specific_dir(b_file)
        local a_pct = get_dir_percentage(a_dir)
        local b_pct = get_dir_percentage(b_dir)

        -- compare by directory percentage
        if a_pct ~= b_pct then
            return a_pct > b_pct
        end

        -- if in same directory (or same percentage), sort by total line changes
        local a_changes = a.added + a.removed
        local b_changes = b.added + b.removed

        if a_changes ~= b_changes then
            return a_changes > b_changes
        end

        -- alphabetical if tie
        return a_file < b_file
    end)

    return sorted_files
end

--- factory function that creates a label extractor for file paths
--- extracts unique single-character labels from filenames (not full paths)
--- @return function A function that takes a filepath and returns a single-character label
M.label_filepath_item = function()
    local used_labels = {}
    return function(item)
        -- extract just the filename (everything after the last forward slash)
        local filename = item:match("([^/]+)$") or item
        local i = 1
        while i <= #filename do
            local char = string.lower(filename:sub(i, i))
            if used_labels[char] == nil then
                used_labels[char] = true
                return char
            end
            i = i + 1
        end
        -- fallback if all characters are used
        return tostring(i)
    end
end

--- WARNING: do not construct your own local_persisted_ui unless you've read append_cmd_ui
--- uses vim.cmd to display a ui. Uses a table in the scope to be able to construct a ui.
--- the cmd ui allows for displaying exactly one dynamic message, but it allows you to display other things alongside your chosen message
--- ex: I want two things in my ui. However, I only want this ui per diff buffer. In the function where I create my diff buffer, create a table. Because of closure, that scoped variable can be reused in other functions. A ui can be persisted, then any time I want to display it, I can.
--- @param local_persisted_ui table the table declared in the scope where we want this ui to be shared
--- @param ui string | nil the ui I want to display 
M.display_cmd_ui = function(local_persisted_ui, ui)
    -- whatever want displayed to the user (not in statusline) we can put in here, and use vim.cmd to do it
    local start_message = ""
    local end_message = ""
    for key, append_start in pairs(local_persisted_ui) do
        if key == nil or append_start == nil then
            print('ERROR: cmd_ui')
            return
        end
        if append_start == true then
            start_message = start_message .. key .. "    "
        else
            end_message = end_message .. key .. "    "
        end
    end
    vim.cmd('echo "' .. start_message .. ui .. "    " .. end_message .. '"')
end

--- meant to be used alongside display_cmd_ui
--- messages are first come first serve; earlier messages are on the left, whether it's on the start or end.
--- @param local_persisted_ui table the table declared in the scope where we want this ui to be shared
--- @param ui string the ui I want to display 
--- @param append_start boolean true if I want the message to display on the left, false if I want the message to display on the right
M.append_cmd_ui = function(local_persisted_ui, ui, append_start)
    local_persisted_ui[ui] = append_start
end

--- get the adjacent files (next and previous) for navigation with wrap-around
--- @param diffed_files DiffedFiles table with files array and cur_idx
--- @return table|nil Table with next and prev file info: { next = { name = string, index = number }, prev = { name = string, index = number } }
M.get_adjacent_files = function(diffed_files)
    if diffed_files.files == nil or diffed_files.cur_idx == nil then
        return nil
    end

    local files = diffed_files.files
    local current_index = diffed_files.cur_idx

    if #files == 0 or #files == 1 then
        return nil
    end

    -- calculate next index with wrap-around
    local next_index = current_index + 1
    if next_index > #files then
        next_index = 1
    end

    -- calculate previous index with wrap-around
    local prev_index = current_index - 1
    if prev_index < 1 then
        prev_index = #files
    end

    return {
        next = {
            name = files[next_index],
            index = next_index
        },
        prev = {
            name = files[prev_index],
            index = prev_index
        }
    }
end

--- @param sorted_files SortedFiles
--- @return table list of file names
M.get_filenames_from_sortedfiles = function(sorted_files)
    local files = {}
    for _, value in ipairs(sorted_files) do
        table.insert(files, value.name)
    end
    return files
end


return M
