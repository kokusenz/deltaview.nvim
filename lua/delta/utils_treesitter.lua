local M = {}

--- @param text string
--- @param lang string
--- @return table<number, LineHighlight[]>
M.get_treesitter_highlight_captures = function(text, lang)
    local language_tree = vim.treesitter.get_string_parser(text, lang)
    language_tree:parse()
    local line_highlights = {}

    local text_lines = vim.split(text, '\n', { plain = true })

    language_tree:for_each_tree(function(tree, ltree)
        local tree_lang = ltree:lang()
        local query = vim.treesitter.query.get(tree_lang, 'highlights')
        if not query then
            return
        end

        for id, node, metadata in query:iter_captures(tree:root(), text) do
            local capture_name = query.captures[id]
            if M.is_metadata_pattern(capture_name) then
                goto continue
            end
            local start_row, start_col, end_row, end_col = node:range()

            for row = start_row, end_row do
                line_highlights[row] = line_highlights[row] or {}

                local row_start_col = (row == start_row) and start_col or 0
                local line_length = text_lines[row + 1] and #text_lines[row + 1] or 0
                local row_end_col = (row == end_row) and end_col or line_length

                table.insert(line_highlights[row], {
                    col = row_start_col,
                    end_col = row_end_col,
                    priority = (metadata and metadata.priority) or id,
                    hl_group = "@" .. capture_name .. "." .. tree_lang
                })
            end
            ::continue::
        end
    end)

    return line_highlights
end

--- @param text string
--- @param lang string
--- @return string[]
M.get_treesitter_token_strings = function(text, lang)
    local language_tree = vim.treesitter.get_string_parser(text, lang)
    local tree = language_tree:parse()[1]
    local node_strings = {}

    --- Check if a node type represents free text that should be split into words
    --- @param node_type string
    --- @return boolean
    local function is_free_text_node_type(node_type)
        return node_type == "comment_content"
            or node_type == "string_content"
            or node_type == "inline" -- Markdown free text
    end

    local function traverse(node)
        if node:child_count() == 0 then
            -- leaf node
            local node_text = vim.treesitter.get_node_text(node, text)
            if node_text and node_text ~= "" then
                local node_type = node:type()

                if is_free_text_node_type(node_type) then
                    -- Split comments into words for better diffing
                    for word in node_text:gmatch("%S+") do
                        table.insert(node_strings, word)
                    end
                else
                    table.insert(node_strings, node_text)
                end
            end
        else
            -- non-leaf node - traverse children
            local node_type = node:type()

            if is_free_text_node_type(node_type) then
                local node_text = vim.treesitter.get_node_text(node, text)
                for word in node_text:gmatch("%S+") do
                    table.insert(node_strings, word)
                end
            else
                for child in node:iter_children() do
                    traverse(child)
                end
            end
        end
    end

    traverse(tree:root())

    -- capture everything not parsed by treesitter (eg. whitespace)
    local strings = {}
    local cur_node_idx = 1
    local i = 1
    while i < #text + 1 do
        local current_node = node_strings[cur_node_idx]
        if current_node and text:sub(i, i + #current_node - 1) == current_node then
            table.insert(strings, current_node)
            cur_node_idx = cur_node_idx + 1
            i = i + #current_node
        else
            table.insert(strings, text:sub(i, i))
            i = i + 1
        end
    end

    return strings
end

local METADATA_PREFIXES = {
    spell = true,      -- @spell.lua, @spell
    nospell = true,    -- @nospell.lua
    conceal = true,    -- @conceal
    definition = true, -- @definition (for LSP navigation)
    scope = true,      -- @scope (for scope detection)
}

--- @param str string
M.is_metadata_pattern = function(str)
    local prefix = str:match("^(%a+)")
    return prefix ~= nil and METADATA_PREFIXES[prefix] == true
end

--- The non treesitter version of splitting a string into its tokens, using basic lua pattern matching (whitespace as separators)
--- @param str string
--- @return string[]
M.get_lua_pattern_token_strings = function(str)
    local tokens = {}
    local i = 1
    while i <= #str do
        local ws_start, ws_end = str:find('%s+', i)
        local tok_start, tok_end = str:find('%S+', i)
        if tok_start and (not ws_start or tok_start <= ws_start) then
            table.insert(tokens, str:sub(tok_start, tok_end))
            i = tok_end + 1
        elseif ws_start then
            for j = ws_start, ws_end do
                table.insert(tokens, str:sub(j, j))
            end
            i = ws_end + 1
        else
            break
        end
    end
    return tokens
end

return M
