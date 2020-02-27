--------------------------------------------------
--------------------------------------------------
--x-----------------------------------------------
--------------------------------------------------
--------------------------------------------------

obj = {"foo", "bar", "baz"}

local getWindow = function()
    local filterfn = function(win)
        return 0 == vim.api.nvim_win_get_buf(win)
    end
    return h.first(h.filter( filterfn, vim.api.nvim_list_wins()))
end
vim.api.nvim_win_get_cursor(0)
vim.api.nvim_set_current_buf(0)
--vim.api.nvim_paste(str, "\n", -1)
-- vim.api.nvim_win_set_cursor(getWindow(), {21, })
-- vim.api.nvim_put(obj, "c" , false, true)
--
local line = vim.api.nvim_buf_line_count(0)
local last = vim.api.nvim_buf_get_lines(0, line-1, -1, false)
vim.api.nvim_win_set_cursor(getWindow(), {line, string.len(last[1])})

p(h.filter(function(el) return not (el == "bar") end, obj))
