local Helpers = {}

function Helpers.p(...)
    print(vim.inspect(...))
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

function Helpers.log(arg)
    vim.api.nvim_command("call input(\""..tostring(arg).."\")")
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
    if type(t)=="table" then
        return t[table.maxn(t)]
    else
        return nil
    end
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
        if fn(v) then
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

local types = {
    program = function(node, b)
        local l = {}
        local n = node:named_child_count()
        for i=0,n-1 do
            table.insert(l, Helpers.to_lua(node:named_child(i), b))
        end
        return l
    end,
    vector = function(node, b)
        local v = {}
        local n = node:named_child_count()
        for i=0,n-1 do
            table.insert(v, Helpers.to_lua(node:named_child(i), b))
        end
        return v
    end,
    list = function(node, b)
        local l = {}
        local n = node:named_child_count()
        for i=0,n-1 do
            table.insert(l, Helpers.to_lua(node:named_child(i), b))
        end
        return l
    end,
    hash_map = function(node, b)
        local m = {}
        local kv = node:named_child_count()
        if kv<2 then return {} end
        for i=0,kv-2,2 do
            m[Helpers.to_lua(node:named_child(i), b)] = Helpers.to_lua(node:named_child(i+1), b)
        end
        return m
    end,
    number = function(node, b)
        return tonumber(Helpers.to_string(node, b))
    end,
    boolean = function(node, b)
        bool = {["true"] = true, ["false"] = false}
        return bool[Helpers.to_string(node, b)]
    end,
    string = function(node, b)
        return Helpers.to_string(node, b)
    end,
    keyword = function(node, b)
        return tostring(Helpers.to_string(node, b))
    end,
    symbol = function(node, b)
        return tostring(Helpers.to_string(node, b))
    end,
    tagged_literal = function(node, b)
        return Helpers.to_string(node, b)
    end,
    interop = function(node, b)
        return tostring(Helpers.to_string(node, b))
    end
}

function Helpers.to_lua(node, buffer)
    local n = node:named_child_count()
    local children = {}
    local tt = node:type()
    if tt == "nil" then return "-nil-" end
    local f = types[tt]
    if f then
        return f(node, buffer)
    else
        return "--"..node:type().."--"
    end
end

function Helpers.to_string(node, buffer)
    local startrow, startcol, endrow, endcol = node:range()
    local _, _, bytes = node:end_()
    local lines = vim.api.nvim_buf_get_lines(buffer, startrow, endrow + 1, false)
    local str = table.concat(lines, "")
    return string.sub(str, startcol+1, endcol)
end

return Helpers
