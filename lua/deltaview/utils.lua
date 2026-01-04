local M = {}

--- Get list of modified and untracked files
--- @param branch_name string|nil Branch to compare against (defaults to HEAD if nil). If nil, includes untracked files
--- @return table Array of file paths that have been modified or are untracked
M.get_diffed_files = function(branch_name)
    -- diffed files
    local diffed = vim.fn.system({'git', 'diff', branch_name ~= nil and branch_name or 'HEAD', '--name-only'})
    if vim.v.shell_error ~= 0 then
        print('ERROR: Failed to get diff files from git')
        return {}
    end

    -- new untracked files
    local untracked = ''
    if branch_name == nil then
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

return M
