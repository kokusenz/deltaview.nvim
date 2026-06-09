local M = {}

--- render the statuscolumn for a delta.lua diff buffer
--- shows: old_line ⋮ new_line with color based on line type
--- @param lnum number The line number (1-indexed)
--- @return string The formatted statuscolumn content
M.render = function(lnum)
    -- vim.v.virtnum is 0 for real lines, >0 for wrapped continuation lines
    if vim.v.virtnum ~= 0 then
        return '' -- Show nothing for wrapped lines and virtual lines
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local line_map = vim.b[bufnr].delta_line_map

    if not line_map then
        -- fallback to regular line numbers
        return string.format('%4d ', lnum)
    end

    local map = line_map[lnum]

    if not map then
        -- fallback if line number not found in map
        return ''
    end

    -- Determine highlight group based on line type
    local hl_group
    if map.type == 'added' then
        hl_group = 'DeltaLineNrAdded'
    elseif map.type == 'removed' then
        hl_group = 'DeltaLineNrRemoved'
    elseif map.type == 'context' then
        hl_group = 'DeltaLineNrContext'
    else
        -- For non-diff lines (headers, etc.), use no highlighting
        hl_group = nil
    end

    local old_str = map.old and string.format('%4d', map.old) or '    '
    local new_str = map.new and string.format('%-4d', map.new) or '    '

    -- Apply highlighting if we have a highlight group
    if hl_group then
        return string.format('%%#%s#%s ⋮ %s%%*', hl_group, old_str, new_str)
    else
        return string.format('%s ⋮ %s', old_str, new_str)
    end
end

return M
