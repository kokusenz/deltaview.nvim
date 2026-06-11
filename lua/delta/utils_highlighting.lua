local M = {}
local utils_treesitter = require('delta.utils_treesitter')

M.initialize_hl_groups = function()
    M.setup_hl_groups()

    vim.api.nvim_create_autocmd('ColorScheme', {
        group = vim.api.nvim_create_augroup('DeltaHighlights', { clear = true }),
        callback = M.setup_hl_groups,
        desc = 'Reinitialize Delta highlight groups after colorscheme change'
    })
end

M.setup_hl_groups = function()
    local config = require('delta.config')

    local bg = vim.o.background or 'dark'

    local hl_groups = config.options.highlight_groups[bg]

    if not hl_groups then
        vim.notify(
            string.format("Delta: No highlight groups defined for background='%s', falling back to 'dark'", bg),
            vim.log.levels.WARN
        )
        hl_groups = config.options.highlight_groups.dark
    end
    --- @cast hl_groups HighlightGroupSet

    for hl_group_name, hl_def in pairs(hl_groups) do
        vim.api.nvim_set_hl(0, hl_group_name, hl_def)
    end
end

--- @param files DiffData[]
--- @param opts DeltaOpts | nil Highlighting options (max_line_distance, etc.)
--- @return table<number, LineHighlight[]> diffs first key is filename, second key line number of the diff
M.get_highlights_multiple_files = function(files, opts)
    local highlights = {}
    for _, file_data in pairs(files) do
        local file_highlights = M.get_highlights_file(file_data, opts)
        for line_number, highlight in pairs(file_highlights) do
            highlights[line_number] = highlight
        end
    end
    return highlights
end

--- @param file DiffData
--- @param opts DeltaOpts | nil Optional configuration overrides
--- @return table<number, LineHighlight[]> highlights a list of
M.get_highlights_file = function(file, opts)
    assert(file)
    local highlights = {}
    local highlight_two_tiers_with_treesitter = true
    if file.language == nil then
        highlight_two_tiers_with_treesitter = false
    end
    for _, hunk in ipairs(file.hunks) do
        -- normal line highlighting
        local line_highlights = M.get_line_highlights(hunk)
        for line_number, line_highlight in pairs(line_highlights) do
            local cur_highlights = highlights[line_number] or {}
            for _, highlight in ipairs(line_highlight) do
                table.insert(cur_highlights, highlight)
            end
            highlights[line_number] = cur_highlights
        end
        -- two tier highlighting
        -- within one hunk, check to see what lines are adjacent to each other that are not context
        local adjacent_lines_sets = M.get_adjacent_line_sets(hunk)
        -- maybe map where key is line nuber, value is diff
        local word_highlights = M.get_highlights(adjacent_lines_sets, opts, file.language,
            highlight_two_tiers_with_treesitter)
        for line_number, word_highlight in pairs(word_highlights) do
            local cur_highlights = highlights[line_number] or {}
            for _, highlight in ipairs(word_highlight) do
                table.insert(cur_highlights, highlight)
            end
            highlights[line_number] = cur_highlights
        end
    end
    return highlights
end

--- get regular line highlights
--- @param hunk Hunk
--- @return table<number, LineHighlight[]>
M.get_line_highlights = function(hunk)
    local line_highlights = {}
    for _, line in ipairs(hunk.lines) do
        if line.line_type == 'added' then
            local add_highlight = {
                col = 0,
                end_row = line.formatted_diff_line_num + 1,
                end_col = 0,
                hl_eol = true,
                priority = 200,
                hl_group = 'DeltaDiffAddedLine'
            }

            line_highlights[line.formatted_diff_line_num] = { add_highlight }
        elseif line.line_type == 'removed' then
            local remove_highlight = {
                col = 0,
                end_row = line.formatted_diff_line_num + 1,
                end_col = 0,
                hl_eol = true,
                priority = 200,
                hl_group = 'DeltaDiffRemovedLine'
            }
            line_highlights[line.formatted_diff_line_num] = { remove_highlight }
        end
    end
    return line_highlights
end

--- get two tier highlights for a hunk
--- @param adjacent_lines_sets table<number, DiffLine>[] array of tables where key is the 1-indexed line number in the diff
--- @param opts DeltaOpts | nil Optional configuration overrides
--- @param language string | nil
--- @param use_treesitter boolean | nil
--- @return table<number, LineHighlight[]> highlights key: 1-indexed line number of the diff
M.get_highlights = function(adjacent_lines_sets, opts, language, use_treesitter)
    local highlights = {}
    for _, adjacent_lines in ipairs(adjacent_lines_sets) do
        -- sort keys so we can iterate the adjacents ino rder
        local keys = {}
        for k, _ in pairs(adjacent_lines) do
            table.insert(keys, k)
        end
        table.sort(keys)

        -- found pairs shouldn't be calculated again
        local tested_pairs = {}
        for _, i in ipairs(keys) do
            tested_pairs[i] = { [i] = true }
        end

        --- @type table<number, number[]>
        local combinations = {}

        -- within one block of diffed code (added or deleted), all lines will be compared against each other.
        -- if there are two added lines, and two deleted lines, each added line will be compared against both deleted lines
        -- this means that we can have multiple diffs for each line. Theoretically, we should only be looking at one though.
        for _, i in ipairs(keys) do
            --- @type DiffLine
            local diffline1 = adjacent_lines[i]
            for _, j in ipairs(keys) do
                --- @type DiffLine
                if tested_pairs[i][j] == true then
                    goto continue
                end

                local diffline2 = adjacent_lines[j]
                if (diffline1.new_line_num ~= nil and diffline2.old_line_num ~= nil) then
                    tested_pairs[i][j] = true
                    tested_pairs[j][i] = true
                    combinations[i] = combinations[i] or {}
                    table.insert(combinations[i], j)
                end

                if (diffline1.old_line_num ~= nil and diffline2.new_line_num ~= nil) then
                    tested_pairs[i][j] = true
                    tested_pairs[j][i] = true
                    combinations[j] = combinations[j] or {}
                    table.insert(combinations[j], i)
                end

                ::continue::
            end
        end

        -- Resolve threshold before scoring so calculate_similarity can use it
        -- for its length-ratio early exit, avoiding the full O(m×n) Levenshtein
        -- for obviously dissimilar pairs.
        opts = opts or {}
        local max_line_distance = (opts.highlighting and opts.highlighting.max_similarity_threshold) or 0.6

        -- Calculate similarity scores for all possible pairs
        --- @type {added_line: number, removed_line: number, similarity: number}[]
        local all_pairs = {}

        for diff_line_num, potential_pairs in pairs(combinations) do
            for _, potential_pair_line_num in ipairs(potential_pairs) do
                local similarity = M.calculate_similarity(
                    adjacent_lines[diff_line_num].content,
                    adjacent_lines[potential_pair_line_num].content,
                    max_line_distance
                )
                table.insert(all_pairs, {
                    added_line = diff_line_num,
                    removed_line = potential_pair_line_num,
                    similarity = similarity
                })
            end
        end

        -- Sort pairs by similarity (highest first)
        table.sort(all_pairs, function(a, b)
            return a.similarity > b.similarity
        end)

        -- Greedily assign pairs, ensuring each line is matched at most once
        local matched_lines = {}
        for _, pair in ipairs(all_pairs) do
            -- If neither line has been matched yet, match them
            if not matched_lines[pair.added_line] and not matched_lines[pair.removed_line] then
                if pair.similarity < max_line_distance then
                    goto continue
                end

                local diff_highlights = M.get_two_tier_highlights(
                    adjacent_lines[pair.added_line].content,
                    adjacent_lines[pair.removed_line].content,
                    language,
                    use_treesitter
                )
                if diff_highlights == nil then
                    goto continue
                end
                highlights[pair.added_line] = diff_highlights.added
                highlights[pair.removed_line] = diff_highlights.removed

                -- Mark both lines as matched
                matched_lines[pair.added_line] = true
                matched_lines[pair.removed_line] = true

                ::continue::
            end
        end
    end
    return highlights
end

--- in a hunk, get all the sets of adjacent lines. returns a list of maps where the key is the 1-indexed line number in the diff
--- @param hunk Hunk
--- @return table<number, DiffLine>[] adjacent_line_sets
M.get_adjacent_line_sets = function(hunk)
    --- @type table<number, DiffLine>[]
    local adjacent_lines_sets = {}
    -- Maps each position (and its ±1 neighbors) to the set index that claimed it,
    -- replacing the O(n_sets) scan in the original with an O(1) lookup.
    local pos_to_set_idx = {}
    for i = 1, #hunk.lines do
        local line = hunk.lines[i]
        if line.line_type ~= 'context' then
            local p = line.formatted_diff_line_num
            local set_idx = pos_to_set_idx[p]
            if set_idx then
                adjacent_lines_sets[set_idx][p] = line
            else
                local new_set = { [p] = line }
                table.insert(adjacent_lines_sets, new_set)
                set_idx = #adjacent_lines_sets
                pos_to_set_idx[p] = set_idx
            end
            if not pos_to_set_idx[p - 1] then pos_to_set_idx[p - 1] = set_idx end
            if not pos_to_set_idx[p + 1] then pos_to_set_idx[p + 1] = set_idx end
        end
    end
    return adjacent_lines_sets
end

--- Levenshtein distance
--- @param str1 string
--- @param str2 string
--- @param threshold number | nil minimum similarity to bother computing (default 0)
--- @return number similarity (0.0 = completely different, 1.0 = identical)
M.calculate_similarity = function(str1, str2, threshold)
    assert(str1)
    assert(str2)
    if str1 == str2 then return 1.0 end
    if str1 == "" or str2 == "" then return 0.0 end

    local len1, len2 = #str1, #str2

    local max_len
    -- Early exit: if the length ratio alone makes it impossible to meet the
    -- threshold, skip the full O(m×n) Levenshtein computation.
    if threshold and threshold > 0 then
        local min_len = math.min(len1, len2)
        max_len = math.max(len1, len2)
        -- Maximum achievable similarity given the length difference
        if (min_len / max_len) < threshold then
            return 0.0
        end
    end
    local prev = {}
    for j = 0, len2 do prev[j] = j end
    local curr = {}
    for i = 1, len1 do
        curr[0] = i
        local row_min = i
        for j = 1, len2 do
            local cost = (str1:byte(i) == str2:byte(j)) and 0 or 1
            curr[j] = math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            if curr[j] < row_min then
                row_min = curr[j]
            end
        end
        -- once the minimum value in a row already exceeds the max edit distance budget, similarity guaranteed too high. no point continuing to iterate and calculate
        if threshold and threshold > 0 and (row_min > (1.0 - threshold) * (max_len or math.max(len1, len2))) then
            return 0.0
        end
        prev, curr = curr, prev
    end
    return 1.0 - (prev[len2] / (max_len or math.max(len1, len2)))
end

--- @param str1 string (the added/green line)
--- @param str2 string (the removed/red line)
--- @param language string | nil
--- @param use_treesitter boolean | nil
--- @return TwoTierHighlights | nil highlights for both strings
M.get_two_tier_highlights = function(str1, str2, language, use_treesitter)
    if use_treesitter and language == nil then
        return
    end
    local tokens_str1 = nil
    local tokens_str2 = nil
    if use_treesitter and language ~= nil then
        tokens_str1 = utils_treesitter.get_treesitter_token_strings(str1, language)
        tokens_str2 = utils_treesitter.get_treesitter_token_strings(str2, language)
    else
        tokens_str1 = utils_treesitter.get_lua_pattern_token_strings(str1)
        tokens_str2 = utils_treesitter.get_lua_pattern_token_strings(str2)
    end
    local formatted_str1 = table.concat(tokens_str1, "\n")
    local formatted_str2 = table.concat(tokens_str2, "\n")

    -- precompute prefix sums of token lengths so each position lookup is O(1)
    --- @param tokens string[]
    --- @return number[] prefix_sums where prefix_sums[i] = index offset of tokens[i]
    local build_prefix_sums = function(tokens)
        local sums = {}
        local running = 0
        for i, token in ipairs(tokens) do
            sums[i] = running
            running = running + #token
        end
        return sums
    end
    local prefix_sums1 = build_prefix_sums(tokens_str1)
    local prefix_sums2 = build_prefix_sums(tokens_str2)

    local diff_fn = (vim.text and vim.text.diff) or vim.diff
    local diff = diff_fn(
        formatted_str1,
        formatted_str2,
        { result_type = 'indices', algorithm = 'myers', ctxlen = 0 })
    --- @cast diff integer[][]

    --- @type TwoTierHighlights
    local highlights = {
        added = {},
        removed = {}
    }

    for _, change in ipairs(diff) do
        -- 0 indexed
        local old_start, old_count, new_start, new_count = change[1], change[2], change[3], change[4]

        -- highlight changed parts of str1 (added/green line)
        -- convert line numbers to character positions using token map
        local token1_position = prefix_sums1[old_start]
        if old_count > 0 and token1_position then
            local end_position = token1_position
            for i = old_start, old_start + old_count - 1 do
                end_position = end_position + #tokens_str1[i]
            end
            table.insert(highlights.added, {
                col = token1_position,
                end_col = end_position,
                priority = 250,
                hl_group = 'DeltaDiffAddedWord'
            })
        end

        -- highlight changed parts of str2 (removed/red line)
        local token2_position = prefix_sums2[new_start]
        if new_count > 0 and token2_position then
            local end_position = token2_position
            for i = new_start, new_start + new_count - 1 do
                end_position = end_position + #tokens_str2[i]
            end
            table.insert(highlights.removed, {
                col = token2_position,
                end_col = end_position,
                priority = 250,
                hl_group = 'DeltaDiffRemovedWord'
            })
        end
    end

    return highlights
end


return M

--- @class TwoTierHighlights
--- @field added LineHighlight[]
--- @field removed LineHighlight[]
