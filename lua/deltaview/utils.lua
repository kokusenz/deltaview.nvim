local M = {}

--- Get list of modified and untracked files
--- @param ref string|nil Git ref to compare against (defaults to HEAD if nil). If nil, includes untracked files
--- @return table Array of file paths that have been modified or are untracked
M.get_diffed_files = function(ref)
    -- diffed files
    local diffed = vim.fn.system({'git', 'diff', ref ~= nil and ref or 'HEAD', '--name-only'})
    if vim.v.shell_error ~= 0 then
        print('ERROR: Failed to get diff files from git')
        return {}
    end

    -- new untracked files
    local untracked = ''
    if ref == nil then
        untracked = vim.fn.system({'git', 'ls-files', '-o', '--exclude-standard'})
        if vim.v.shell_error ~= 0 then
            print('ERROR: Failed to get untracked files from git')
            untracked = ''
        end
    end

    local files = {}
    local seen = {}

    for match in (diffed .. untracked):gmatch('[^\n]+') do
        if not seen[match] and match ~= '' then
            seen[match] = true
            table.insert(files, match)
        end
    end

    return files
end

--- Check if a path is a valid file path for diffing (not a directory or empty)
--- @param path string|nil The file path to validate
--- @return boolean True if the path is a diffable file, false otherwise
M.is_diffable_filepath = function(path)
    if path == nil or string.sub(path, -1) == "/" or path == '' then
        return false
    end
    return true
end

--- Factory function that creates a label extractor for file paths
--- Extracts unique single-character labels from filenames (not full paths)
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

--- uses vim.cmd to display a ui. Uses a table in the scope to be able to construct a ui.
--- ex: I want two things in my ui. However, I only want this ui per diff buffer. In the function where I create my diff buffer, create a table. Because of closure, that scoped variable can be reused in other functions. A ui can be persisted, then any time I want to display it, I can.
--- @param local_persisted_ui table the table declared in the scope where we want this ui to be shared
--- @param ui string | nil the ui I want to display 
M.display_cmd_ui = function(local_persisted_ui, ui)
    -- whatever want displayed to the user (not in statusline) we can put in here, and use vim.cmd to do it
    local message = ""
    for _,value in ipairs(local_persisted_ui) do
        message = message .. value .. "    "
    end
    vim.cmd('echo "' .. message .. ui .. '"')
end

--- meant to be used alongside display_cmd_ui
--- @param local_persisted_ui table the table declared in the scope where we want this ui to be shared
--- @param ui string the ui I want to display 
M.append_cmd_ui = function(local_persisted_ui, ui)
    table.insert(local_persisted_ui, ui or '')
end


return M
