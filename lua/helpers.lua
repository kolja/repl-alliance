local Helpers = {}

function Helpers.p(...)
    print(vim.inspect(...))
end

function Helpers.pr(str)
    local s = ""
    if type(str) == "string" then
        s = str
    else
        s = vim.inspect(str)
    end
    s = vim.split(s, "\n")
    local buffer = repl:buffer()
    local n = vim.api.nvim_buf_line_count(buffer)
    vim.api.nvim_buf_set_lines(buffer, n, -1, false, s)
end

function Helpers.unescape(str)
    -- anytype          => vim.inspect(anytype)
    -- "string"         => "string" // unchanged
    -- "\"string\""     => "string" // unescaped
    if not (type(str) == "string") then
        return vim.inspect(str)
    end
    local unescaped = loadstring("return "..str)()
    if type(unescaped) == "string" then
        return unescaped
    else
        return tostring(unescaped)
    end
end

function Helpers.every(fn, coll)
    if #coll == 0 then return true end
    local res = true
    for k,v in pairs(coll) do
        res = res and fn(v)
    end
    return res
end

function Helpers.isemptystr(str)
    return string.gsub(str, "^%s+$", "") == ""
end

function Helpers.isempty(elem, depth)
    if type(elem) == "string" then
        return Helpers.isemptystr(elem)
    end
    if type(depth) == "number" then depth = depth - 1 end
    if type(elem) == "table" then
        if (type(depth) == "number") and depth < 0 then
            return false
        else
            return Helpers.every(function(element)
                return Helpers.isempty(element, depth)
            end, elem)
        end
    else
        return Helpers.isemptystr(elem)
    end
end

function Helpers.run_in_buffer(fn, target_buf)

    local target_win = Helpers.filter(function(win)
        return target_buf == vim.api.nvim_win_get_buf(win)
    end, vim.api.nvim_list_wins())[1]
    local current_win = vim.api.nvim_get_current_win()
    local cursor_pos = vim.api.nvim_win_get_cursor(current_win)
    local current_buf = vim.api.nvim_get_current_buf()

    vim.api.nvim_set_current_win(target_win)
    -- vim.api.nvim_set_current_buf(target_buf)

    local ret = vim.schedule_wrap(function(tb)
        fn(tb)
    end)(target_buf)

    vim.api.nvim_set_current_win(current_win)
    -- vim.api.nvim_set_current_buf(current_buf)
    vim.api.nvim_win_set_cursor(current_win, cursor_pos)
    return ret
end

function Helpers.occur(str, tag)
    local t = {}
    local i = 0
    while true do
      i = string.find(str, tag, i+1)
      if not i then break end
      table.insert(t, i)
    end
    return #t > 0 and t
end

function Helpers.log(arg)
    local str = string.gsub(tostring(arg), "\n", "")
    vim.api.nvim_command("call input(\""..str.."\")")
end

function Helpers.identity(arg)
    return arg
end

function Helpers.getvar(name, default)
    if pcall(function () vim.api.nvim_get_var(name) end) then
        return vim.api.nvim_get_var(name)
    else
        return default
    end
end

function Helpers.last(t)
    if not type(t) == "table" then return nil end
    return t[table.maxn(t)]
end

function Helpers.butlast(t)
    local copy = vim.deepcopy(t)
    table.remove(copy,table.maxn(t))
    return copy
end

function Helpers.first(t)
    if not type(t) == "table" then return nil end
    return t[1]
end

function Helpers.rest(t)
    local copy = vim.deepcopy(t)
    table.remove(copy,1)
    return copy
end

function Helpers.contains(list, x)
    if not list then return false end
    for _, v in pairs(vim.tbl_flatten(list)) do
        if v == x then return true end
    end
    return false
end
function Helpers.keys(t)
    local keys = {}
    for k,v in pairs(t) do
        table.insert(keys,k)
    end
    return keys
end

function Helpers.filter(fn, t)
    local filtered = {}
    for k,v in pairs(t) do
        if fn(v,k) then
            table.insert(filtered,v)
        end
    end
    return filtered
end

function Helpers.remove(fn, t)
    local filtered = {}
    for k,v in pairs(t) do
        if not fn(v,k) then
            table.insert(filtered,v)
        end
    end
    return filtered
end

function Helpers.map(f, t)
  local new_t = {}
  for i,v in ipairs(vim.tbl_flatten(t)) do
    table.insert(new_t, f(v))
  end
  return new_t
end

return Helpers
