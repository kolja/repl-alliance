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

return Helpers
