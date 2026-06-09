local M = {}
local utils = require('delta.utils')
local utils_treesitter = require('delta.utils_treesitter')
local utils_highlighting = require('delta.utils_highlighting')
local config = require('delta.config')

--- creates a delta buffer based on a git diff
--- @param ref string
--- @param path string | nil
--- @param opts DeltaOpts | nil
--- @return number | nil bufnr
M.git_diff = function(ref, path, opts)
    local effective = vim.tbl_deep_extend('force', config.options, opts or {})
    local git_root = utils.get_git_root(path or vim.fn.getcwd())
    if effective.new_file and path and path:sub(1, 1) == '/' then
        path = path:sub(#git_root + 2)
    end
    local diff_cmd = utils.build_git_diff_cmd_with_flags(effective, ref, git_root, path)
    local diff_result = vim.system(diff_cmd):wait()
    assert(diff_result.code == 0 or diff_result.code == 1, 'An error occurred while running git diff - ' .. diff_result.stderr)
    local diffstring = vim.trim(diff_result.stdout)

    if diffstring == '' then
        vim.notify('No changes detected in current file', vim.log.levels.WARN)
        return
    end

    local data = M.get_diff_data_git(diffstring)
    local buf_id = M.create_formatted_buffer(data)
    vim.b[buf_id].git_root = git_root
    return buf_id
end

--- creates a delta buffer based on two texts
--- @param s1 string string 1
--- @param s2 string string 2
--- @param language string | nil language for syntax highlighting (e.g. 'lua', 'python')
--- @param opts DeltaOpts | nil
--- @return number | nil bufnr
M.text_diff = function(s1, s2, language, opts)
    local effective = vim.tbl_deep_extend('force', config.options, opts or {})

    local diff_fn = (vim.text and vim.text.diff) or vim.diff
    local diffstring = diff_fn(s1, s2, { result_type = 'unified', ctxlen = effective.context, algorithm = 'myers' })
    --- @cast diffstring string
    local file_data = M.get_diff_data(diffstring, language)

    local buf_id = M.create_formatted_buffer({ file_data })
    return buf_id
end

--- creates a delta buffer based on a diff string (for example, the text contents of a patch file)
--- @param diffstring string
--- @param is_git_diff boolean whether the string is in git diff format (with file headers), as opposed to a plain unified diff
--- @param language string | nil language for syntax highlighting (e.g. 'lua', 'python'). ignored when is_git_diff is true (language is inferred from file path)
--- @param opts DeltaOpts | nil
--- @return number | nil bufnr
M.patch_diff = function(diffstring, is_git_diff, language, opts)
    if diffstring == "" then
        vim.notify("diffstring is empty", vim.log.levels.WARN)
        return
    end

    if is_git_diff then
        local data = M.get_diff_data_git(diffstring)
        local buf_id = M.create_formatted_buffer(data)
        return buf_id
    end

    local data = M.get_diff_data(diffstring, language)
    local buf_id = M.create_formatted_buffer({ data })
    return buf_id
end


--- @param diff string the unified diff string format (starting from first @@ hunk header)
--- @param language string | nil the language to use downstream when parsing. If not specified, the language will be determined from the file extension
--- @return DiffData
M.get_diff_data = function(diff, language)
    local lines = vim.split(diff, '\n', { plain = true })

    --- @type DiffData
    local file_data = {
        hunks = {},
        language = language
    }

    local current_hunk = nil
    local old_line_num = 0  -- Track line number in old file
    local new_line_num = 0  -- Track line number in new file
    local diff_line_num = 0 -- Track line number in diff output

    for _, line in ipairs(lines) do
        if line:match('^Binary files ') then
            return file_data
        end
        if line:match('^@@') then
            -- hunk header: @@ -old_start,old_count +new_start,new_count @@ [context]
            local old_info, new_info, context = line:match('^@@[%s]+%-([^%s]+)[%s]+%+([^%s]+)[%s]+@@(.*)$')

            if old_info and new_info then
                local old_start_str, old_count_str = old_info:match('(%d+),?(%d*)')
                local new_start_str, new_count_str = new_info:match('(%d+),?(%d*)')

                local old_start = tonumber(old_start_str) or 1
                local old_count = tonumber(old_count_str) or 1
                local new_start = tonumber(new_start_str) or 1
                local new_count = tonumber(new_count_str) or 1

                -- Trim leading/trailing whitespace from context
                local trimmed_context = context and context:match('^%s*(.-)%s*$')
                if trimmed_context == '' then
                    trimmed_context = nil
                end

                current_hunk = {
                    lines = {},
                    old_start = old_start,
                    old_count = old_count,
                    new_start = new_start,
                    new_count = new_count,
                    header = line,
                    context = trimmed_context
                }

                old_line_num = old_start
                new_line_num = new_start

                table.insert(file_data.hunks, current_hunk)
            end
        elseif line:match('^%+') and current_hunk then
            -- added line
            local content = line:sub(2) -- Remove '+' prefix

            table.insert(current_hunk.lines, {
                content = content,
                old_line_num = nil, -- No old line (this is added)
                new_line_num = new_line_num,
                diff_line_num = diff_line_num,
                formatted_diff_line_num = diff_line_num, -- Initially same as diff_line_num
                line_type = "added"
            })

            new_line_num = new_line_num + 1
        elseif line:match('^%-') and current_hunk then
            -- removed line
            local content = line:sub(2) -- Remove '-' prefix

            table.insert(current_hunk.lines, {
                content = content,
                old_line_num = old_line_num,
                new_line_num = nil,                      -- No new line (this is removed)
                diff_line_num = diff_line_num,
                formatted_diff_line_num = diff_line_num, -- Initially same as diff_line_num
                line_type = "removed"
            })

            old_line_num = old_line_num + 1
        elseif current_hunk and line:match('^%s') then
            -- context line (starts with space or is plain text in hunk)
            local content = line:sub(2) -- Remove leading space

            table.insert(current_hunk.lines, {
                content = content,
                old_line_num = old_line_num,
                new_line_num = new_line_num,
                diff_line_num = diff_line_num,
                formatted_diff_line_num = diff_line_num, -- Initially same as diff_line_num
                line_type = "context"
            })

            old_line_num = old_line_num + 1
            new_line_num = new_line_num + 1
        end
        diff_line_num = diff_line_num + 1
    end

    return file_data
end


--- @param diff string the git diff string format, made up of multiple unified diff strings
--- @return DiffData[]
M.get_diff_data_git = function(diff)
    local lines = vim.split(diff, '\n', { plain = true })

    --- @type DiffData[]
    local result = {}

    --- @type table<string>
    local current_file_lines = {}
    local current_old_path = nil
    local current_new_path = nil
    local current_is_new_file = nil
    local current_old_file_mode = nil
    local current_new_file_mode = nil
    local current_old_blob_hash = nil
    local current_new_blob_hash = nil

    local function finalize_current_file(file_lines)
        if #file_lines > 0 then
            local file_diff_string = table.concat(file_lines, '\n')
            local language = current_new_path and utils.get_language_from_filename(current_new_path) or nil
            local file_data = M.get_diff_data(file_diff_string, language)
            file_data.old_path = current_old_path
            file_data.new_path = current_new_path
            file_data.new_file = current_is_new_file
            file_data.old_file_mode = current_old_file_mode
            file_data.new_file_mode = current_new_file_mode
            file_data.old_blob_hash = current_old_blob_hash
            file_data.new_blob_hash = current_new_blob_hash
            table.insert(result, file_data)
        end
    end

    local i = 1
    while i <= #lines do
        if lines[i]:match('^diff %-%-git') then
            -- new file starting: calculate the diff for the old file
            finalize_current_file(current_file_lines)
            current_file_lines = {}
            current_old_path = nil
            current_new_path = nil
            current_is_new_file = nil
            current_old_file_mode = nil
            current_new_file_mode = nil
            current_old_blob_hash = nil
            current_new_blob_hash = nil
            -- now try to parse all the metadata we can find for the new file
            local j = i
            while j <= #lines and not (lines[j]:match('^@@') or lines[j]:match('^Binary files ')) do
                local new_file_mode_hash = lines[j]:match('^new file mode (%d+)')
                if new_file_mode_hash then
                    current_is_new_file = true
                    current_new_file_mode = new_file_mode_hash
                end

                local old_blob_hash, new_blob_hash, file_mode_hash = lines[j]:match('^index (%w+)..(%w+) (%d*)')
                current_old_blob_hash = old_blob_hash or current_old_blob_hash
                current_new_blob_hash = new_blob_hash or current_new_blob_hash

                local old_file_hash = lines[j]:match('^old mode (%d+)')
                local new_file_hash = lines[j]:match('^new mode (%d+)')
                -- if match for "new mode" then use that, or if match in index use that, or potentially keep using the match found in "new file mode" 
                current_new_file_mode = new_file_hash or file_mode_hash or current_new_file_mode
                -- if match for "old mode" then use that, or if match in index use that
                current_old_file_mode = old_file_hash or file_mode_hash or current_old_file_mode

                local old_path = lines[j]:match('^%-%-%-[%s]+%w/(.+)$')
                    or lines[j]:match('diff %-%-git[%s]+%w/(.+)[%s]+%w/.+$')
                local new_path = lines[j]:match('^%+%+%+[%s]+%w/(.+)$')
                    or lines[j]:match('diff %-%-git[%s]+%w/.+[%s]+%w/(.+)$')
                current_old_path = old_path or current_old_path
                current_new_path = new_path or current_new_path
                j = j + 1
            end
            i = j
        else
            -- normal lines of code
            table.insert(current_file_lines, lines[i])
            i = i + 1
        end
    end

    finalize_current_file(current_file_lines)

    return result
end

--- Creates and formats the contents of the delta diff buffer.
--- @param diff_data_set DiffData[]
--- @return number buf_id
M.create_formatted_buffer = function(diff_data_set)
    local diff_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = diff_bufnr })
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = diff_bufnr })

    local output_lines = {}
    local current_line_num = 0
    local separator_width = utils.get_window_width(0) - 8

    --- @type StatusColumnLineMap
    local line_map = {}

    local bar = '─'
    local pipe = '│'
    local top_corner = '┐'
    local bottom_corner = '┘'

    --- @type DeltaArtifact[]
    local delta_artifacts = {}

    for file_idx, file_data in ipairs(diff_data_set) do
        if file_data.new_path or file_data.old_path then
            local path_title = file_data.new_path
            if file_data.new_path and file_data.old_path and file_data.new_path ~= file_data.old_path then
                path_title = file_data.old_path .. " ⟶   " .. file_data.new_path
            end
            if file_data.new_file then
                path_title = 'added: ' .. path_title
            end
            table.insert(output_lines, path_title)
            table.insert(delta_artifacts, { row_number = current_line_num, content = path_title, type = "title" })
            line_map[current_line_num + 1] = { old = nil, new = nil }
            current_line_num = current_line_num + 1
            table.insert(output_lines, bar:rep(separator_width))
            table.insert(delta_artifacts,
                { row_number = current_line_num, content = bar:rep(separator_width), type = "fence" })

            line_map[current_line_num + 1] = { old = nil, new = nil }
            current_line_num = current_line_num + 1

            table.insert(output_lines, "")
            line_map[current_line_num + 1] = { old = nil, new = nil }
            current_line_num = current_line_num + 1
        end

        for idx, hunk in ipairs(file_data.hunks) do
            if #file_data.hunks > 1 then
                -- show hunk header if there is more than one hunk
                local context = hunk.context and string.format("%s ", hunk.context)
                local hunk_header = context
                    and string.format("Line %d: %s", hunk.new_start, context)
                    or string.format("Line %d ", hunk.new_start)
                local formatted_hunk_header = hunk_header .. (#hunk_header < separator_width and pipe or '')
                local formatted_hunk_header_top = bar:rep(math.min(#hunk_header, separator_width)) .. top_corner
                local formatted_hunk_header_bottom = bar:rep(math.min(#hunk_header, separator_width)) .. bottom_corner
                table.insert(output_lines, formatted_hunk_header_top)
                table.insert(delta_artifacts,
                    { row_number = current_line_num, content = formatted_hunk_header_top, type = "fence" })
                line_map[current_line_num + 1] = { old = nil, new = nil }
                current_line_num = current_line_num + 1

                table.insert(output_lines, formatted_hunk_header)
                table.insert(delta_artifacts,
                    { row_number = current_line_num, content = formatted_hunk_header, type = "title" })
                line_map[current_line_num + 1] = { old = nil, new = nil }
                current_line_num = current_line_num + 1

                table.insert(output_lines, formatted_hunk_header_bottom)
                table.insert(delta_artifacts,
                    { row_number = current_line_num, content = formatted_hunk_header_bottom, type = "fence" })
                line_map[current_line_num + 1] = { old = nil, new = nil }
                current_line_num = current_line_num + 1
            end

            for _, line in ipairs(hunk.lines) do
                table.insert(output_lines, line.content)
                line.formatted_diff_line_num = current_line_num

                -- store old and new line numbers for statuscolumn (1-based indexing)
                line_map[current_line_num + 1] = {
                    old = line.old_line_num,
                    new = line.new_line_num,
                    type = line.line_type
                }

                current_line_num = current_line_num + 1
            end

            if idx ~= #file_data.hunks or file_idx ~= #diff_data_set then
                table.insert(output_lines, "")
                line_map[current_line_num + 1] = { old = nil, new = nil } -- +1 for 1-based indexing
                current_line_num = current_line_num + 1
            end
        end
    end

    vim.api.nvim_set_option_value('modifiable', true, { buf = diff_bufnr })
    vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, output_lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = diff_bufnr })

    -- delta_line_map is for status column
    --- @type StatusColumnLineMap
    vim.b[diff_bufnr].delta_line_map = line_map
    --- @type DiffData[]
    vim.b[diff_bufnr].delta_diff_data_set = diff_data_set
    --- @type DeltaArtifact[]
    vim.b[diff_bufnr].delta_artifacts = delta_artifacts

    return diff_bufnr
end

--- @param bufnr number
M.highlight_delta_artifacts = function(bufnr)
    local delta_artifacts = M.get_delta_artifact_data(bufnr)
    if (delta_artifacts == nil) then return end
    --- @cast delta_artifacts DeltaArtifact[]

    --- @type table<number, LineHighlight[]>
    local artifact_highlights = {}

    for _, artifact in ipairs(delta_artifacts) do
        local line_length = #artifact.content
        artifact_highlights[artifact.row_number] = {
            {
                col = 0,
                end_col = line_length,
                priority = 150,
                hl_group = 'DeltaTitle' -- Blue/gray color typically used for comments
            }
        }
    end

    utils.apply_highlights(bufnr, artifact_highlights)
end

--- applies treesitter syntax highlights by reconstructing after-content from diff_data.
--- use this for text_diff and patch_diff workflows where no source file is available.
--- @param bufnr number id of buffer with the diffed contents
M.syntax_highlight_diff_set = function(bufnr)
    local diff_data_set = M.get_buf_diff_data_set(bufnr)
    if diff_data_set == nil then return end
    --- @cast diff_data_set DiffData[]

    for _, diff_data in ipairs(diff_data_set) do
        local after_content = M.reconstruct_after_content(diff_data)
        M.syntax_highlight_diff(bufnr, diff_data, after_content)
    end
end

--- applies treesitter syntax highlights to each file one by one, if inside git
--- @param bufnr number id of buffer with the diffed contents
M.syntax_highlight_git_diff = function(bufnr)
    local diff_data_set = M.get_buf_diff_data_set(bufnr)
    local git_root = M.get_buf_git_root(bufnr)

    for _, diff_data in pairs(diff_data_set) do
        local source_path = git_root .. '/' .. diff_data.new_path

        if vim.fn.filereadable(source_path) == 0 then
            vim.notify("File not found: " .. source_path, vim.log.levels.WARN)
            goto continue
        end

        local lines = utils.read_file_lines(source_path)
        if not lines then
            vim.notify('Could not read file: ' .. source_path, vim.log.levels.WARN)
            return
        end
        local after_content = table.concat(lines, '\n')

        M.syntax_highlight_diff(bufnr, diff_data, after_content)
        ::continue::
    end
end

--- reconstructs the "after" file content from diff_data by collecting context and added lines
--- at their correct new-file line positions. Lines not present in the diff are left empty.
--- The resulting string preserves new_line_num row correspondence for treesitter token lookup.
--- @param diff_data DiffData
--- @return string
M.reconstruct_after_content = function(diff_data)
    local sparse = {}
    local max_line = 0

    for _, hunk in ipairs(diff_data.hunks) do
        for _, line in ipairs(hunk.lines) do
            if (line.line_type == 'added' or line.line_type == 'context') and line.new_line_num then
                sparse[line.new_line_num] = line.content
                if line.new_line_num > max_line then
                    max_line = line.new_line_num
                end
            end
        end
    end

    local lines = {}
    for i = 1, max_line do
        lines[i] = sparse[i] or ''
    end
    return table.concat(lines, '\n')
end

--- highlights a file by getting the treesitter captures on the full, original file
--- @param bufnr number
--- @param diff_data DiffData
--- @param after_content string the full "after" text the diff originated from
M.syntax_highlight_diff = function(bufnr, diff_data, after_content)
    if diff_data.language == nil then
        return
    end
    local tokens = utils_treesitter.get_treesitter_highlight_captures(after_content, diff_data.language)

    --- @type table<number, LineHighlight[]>
    local new_highlights = {}
    for _, hunk in ipairs(diff_data.hunks) do
        for _, line in ipairs(hunk.lines) do
            if line.line_type == 'context' or line.line_type == 'added' then
                new_highlights[line.formatted_diff_line_num] = tokens[line.new_line_num - 1]
            end
        end
    end
    utils.apply_highlights(bufnr, new_highlights)
end

--- can be used on single file diffs or git diffs.
--- @param bufnr number
--- @param opts DeltaOpts | nil Optional highlighting configuration overrides
M.diff_highlight_diff = function(bufnr, opts)
    local diff_data_set = M.get_buf_diff_data_set(bufnr)
    if (diff_data_set == nil) then return end
    --- @cast diff_data_set DiffData[]
    local highlight_opts = vim.tbl_deep_extend('force', config.options, opts or {})
    local file_highlights = utils_highlighting.get_highlights_multiple_files(diff_data_set, highlight_opts)
    utils.apply_highlights(bufnr, file_highlights)
end

--- @param bufnr number
--- @param winid number | nil defaults to current window
M.setup_delta_statuscolumn = function(bufnr, winid)
    local win = winid or vim.api.nvim_get_current_win()
    assert(vim.api.nvim_win_get_buf(win) == bufnr, string.format(
        "Buffer %d must be displayed in window %d before calling setup_delta_statuscolumn. " ..
        "Please display the buffer first: vim.api.nvim_win_set_buf(%d, %d)",
        bufnr, win, win, bufnr
    ))

    local current_statuscolumn = vim.api.nvim_get_option_value('statuscolumn', { win = win })

    vim.api.nvim_set_option_value('statuscolumn',
        '%{%v:lua.require("delta.statuscolumn").render(v:lnum)%}',
        { win = 0 }
    )
    vim.cmd('redraw')

    vim.api.nvim_create_autocmd('BufUnload', {
        buffer = bufnr,
        once = true,
        callback = function()
            -- restore statuscolumn when leaving the buffer
            if vim.api.nvim_win_is_valid(0) then
                vim.api.nvim_set_option_value('statuscolumn', current_statuscolumn, { win = win })
            end
        end
    })
end

--- @param bufnr number
--- @return DiffData[]
M.get_buf_diff_data_set = function(bufnr)
    local delta_files_data = vim.b[bufnr].delta_diff_data_set
    assert(delta_files_data ~= nil, 'Buffer did not contain expected Delta.lua delta diff data')
    return delta_files_data
end

--- @param bufnr number
--- @return string
M.get_buf_git_root = function(bufnr)
    local git_root = vim.b[bufnr].git_root
    assert(git_root ~= nil, 'Buffer did not contain expected Delta.lua git root data')
    return git_root
end

--- @param bufnr number
--- @return DeltaArtifact[] | nil
M.get_delta_artifact_data = function(bufnr)
    local delta_artifacts = vim.b[bufnr].delta_artifacts
    assert(delta_artifacts ~= nil, 'Buffer did not contain expected Delta.lua delta artifact data')
    return delta_artifacts
end

return M

--- @class DiffLine
--- @field content string The line content
--- @field old_line_num number|nil Line number in old file (nil if added)
--- @field new_line_num number|nil Line number in new file (nil if removed)
--- @field diff_line_num number 0-indexed Line number in the diff output
--- @field formatted_diff_line_num number 0-indexed Line number in the diff output; if formatting is applied to the buffer, this field is updated, while diff_line_num remains the same.
--- @field line_type "added"|"removed"|"context" Type of change

--- @class Hunk
--- @field lines DiffLine[] Array of lines in this hunk
--- @field old_start number Starting line number in old file
--- @field old_count number Number of lines in old file
--- @field new_start number Starting line number in new file
--- @field new_count number Number of lines in new file
--- @field header string The hunk header line (e.g., "@@ -10,5 +12,6 @@")
--- @field context string|nil Function or context name from hunk header (e.g., "def my_function(")

--- @class DiffData
--- @field hunks Hunk[] Array of hunks for this file
--- @field old_path string | nil Path to old file (from --- a/...)
--- @field new_path string | nil Path to new file (from +++ b/...)
--- @field language string | nil language of file
--- @field new_file boolean | nil captures the "new file mode"; true if new file
--- @field old_file_mode number | nil for example, 100644 is a regular file with read/write permissions
--- @field new_file_mode number | nil for example, 100644 is a regular file with read/write permissions
--- @field old_blob_hash string | nil  old
--- @field new_blob_hash string | nil  old

-- originally the types were meant to allow different artifacts to have different highlights.
-- if I want this to be useful, I would need to update my code to identify artifacts by both row and column.
-- Would be a big implementation, for little gain.
-- for little gain.
--- @class DeltaArtifact
--- @field row_number number (0-indexed)
--- @field content string
--- @field type "title"|"fence"|

--- Line number mapping for statuscolumn. 1-indexed
--- @alias StatusColumnLineMap table<number, {old: number|nil, new: number|nil, type: "added"|"removed"|"context"|nil}>
