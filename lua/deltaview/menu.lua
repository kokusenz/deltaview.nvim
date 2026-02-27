local M = {}
local utils = require('deltaview.utils')
local view = require('deltaview.view')

--- Creates a menu pane, and orchestrates the logic of switching between a fuzzy finder or a quick select depending on how large the diff is
--- @param ref string|nil Optional git ref to compare against (defaults to HEAD). Can be branch, commit, tag, etc.
M.create_diff_menu_pane = function(ref)
    local sorted_files = utils.get_sorted_diffed_files(ref)
    -- can maybe just use diffed files instead, gotta see if order matters
    local mods = utils.get_filenames_from_sortedfiles(sorted_files)

    if #mods == 0 then
        print('DeltaView: No diffs to display')
        return
    end
    local changes_data = {}
    for _, value in ipairs(sorted_files) do
        changes_data[value.name] = {'+' .. value.added .. ',-' .. value.removed}
    end

    local on_select = function(filepath, selected_idx)
        if filepath == nil then
            return
        end
        if selected_idx == nil then
            for key, value in ipairs(mods) do
                if value == filepath then
                    selected_idx = key
                end
            end
        end

        local success, err = pcall(function()
            vim.cmd('e ' .. vim.fn.fnameescape(filepath))
        end)
        if not success then
            print('ERROR: Failed to open file: ' .. filepath .. ' - file may have been removed.')
            return
        end

        M.diffed_files.files = mods
        M.diffed_files.cur_idx = selected_idx
        diffing_function(filepath, ref)
    end

    local deltaview_quickselect_menu = function()
        selector.ui_select(mods, {
            prompt = 'DeltaView Menu  |  ' .. config.viewconfig().vs .. ' ' .. (ref or 'HEAD'),
            label_item = utils.label_filepath_item,
            win_predefined = config.options.quick_select_view,
            additional_data = changes_data
        }, on_select)
    end

    if #mods >= config.options.fzf_threshold then
        -- TODO: allow integration with fzf-lua and telescope pickers; use those pickers if available
        local on_select_with_key = function(result)
            if result == nil or #result == 0 then
                return
            end

            local key = result[1]

            if key == config.options.keyconfig.fzf_toggle then
                deltaview_quickselect_menu()
                return
            end

            -- result[2] contains the selected item
            if result[2] then
                on_select(result[2], nil)
            end
        end

        local success, err = pcall(function()
            vim.fn['fzf#run'](vim.fn['fzf#wrap']({
                source = mods,
                ['sink*'] = on_select_with_key,
                options = {
                    '--style', 'minimal',
                    '--layout', 'reverse',
                    '--prompt', 'DeltaView Menu > ',
                    '--preview', 'if [ -z "$(git ls-files -- {})" ]; then git diff --no-index /dev/null {}; else git diff ' .. (ref or 'HEAD') .. ' -- {}; fi | delta --paging=never',
                    '--border-label', 'comparing to ' .. (ref or 'HEAD'),
                    '--expect', config.options.keyconfig.fzf_toggle,
                },
                window = { width = 0.8, height = 0.9, border = 'rounded' }
            }))
        end)
        if success then
            return
        else
            print('WARNING: fzf#run failed: ' .. tostring(err) .. '. Using default picker.')
        end
    end
    deltaview_quickselect_menu()
end

return M
