local Clojure = {}
local h = require("helpers")
local map = h.map
local types = {}

-- ------------------------------------------ --
-- Use Tree-Sitter to parse Clojure Code into --
-- a Lua datastructure                        --
-- ------------------------------------------ --
local concat = function(tbl, separator)
    local elements = {}
    for i,v in ipairs(vim.tbl_flatten(tbl)) do
      table.insert(elements, v:str())
    end
    return table.concat(elements, separator)
end

Clojure.intercept = h.identity
Clojure.buffer = nil
Clojure.elision_symbol = "●"
Clojure.elisions = {}

function Clojure:new (config)

    Clojure.intercept = config.intercept or Clojure.intercept
    Clojure.buffer = Clojure.buffer or config.buffer
    Clojure.elision_symbol = Clojure.elision_symbol or config.elision_symbol

    local conf = config or {}
    local obj = vim.tbl_extend( "keep", conf, {
        node = conf.node,
        buffer = Clojure.buffer,
        ratype = conf.node:type(),
        children = {},
        intercept = Clojure.intercept
    })
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Clojure:add(node)
    table.insert(self.children, node)
    return self
end

function Clojure:to_lua()
    local node = self.node
    local f = types[node:type()] or types["error"]
    return f(self)
end

function Clojure:raw_string()
    local node = self.node
    local buffer = self.buffer
    local startrow, startcol, endrow, endcol = node:range()
    local _, _, bytes = node:end_()
    local lines = vim.api.nvim_buf_get_lines(buffer, startrow, endrow + 1, false)
    local str = table.concat(lines, "")
    return string.sub(str, startcol+1, endcol)
end

function Clojure:str()
    local elements = {}
    local str = ""

    if #(self.children) > 0 then
        local open = (self.delimiter and self.delimiter[1]) or "<"
        local close = (self.delimiter and self.delimiter[2]) or ">"
        for i=1,#(self.children) do
            table.insert(elements, self.children[i]:str())
        end
        str = open..table.concat(elements, " ")..close
    elseif self.string then
        str = self.string
    else
        str = self:raw_string()
    end

    -- string-middleware:
    local interc = self.intercept[self.ratype]
    if interc then
        str = interc(self, str)
    end

    return str
end

function Clojure:is(t)
    return (self.ratype == t)
end

function Clojure:resolve(id, obj)
    if self:is("tagged_literal") and self.children[1]:is("elision") then
        if not obj then
            -- call eval
            local action = self.children[2]:get({":get"})
            local key = action:get({2})
            if id == key then -- this is the elision we are looking for
                repl:eval(action)
            end
        else
            self.children[1].resolved = obj
        end
    else
        self:each(function(element)
            Clojure:resolve(id, obj)
        end)
    end
    return self
end

function Clojure:each(fn)
    for i,v in ipairs(self.children) do
        fn(v,i)
    end
end

function Clojure:get(path)
    if type(path) == "string" then path = {path} end
    -- will never return nil. Will always at least return something
    -- that get(), str() or val() can be called on.
    local m = {
       get = function() return self end,
       str = function() return "nil" end,
       val = function() return nil end,
       is =  function() return false end
    }

    if #path == 0 then
        return self
    end
    local get_key = function(obj, key)
        if not obj:is("hash_map") then
            error("trying to access "..key.." in "..obj.ratype)
        end
        local n = #(obj.children)
        local result = m
        if n<2 then return m end
        for i=1,n-1,2 do
            if obj.children[i]:str() == key then
                result = obj.children[i+1]
            end
        end
        return result
    end
    local key = h.first(path)
    local result = m
    if type(key) == "number" then
        result = self.children[key] or m
    elseif type(key) == "string" then
        result = get_key(self, key)
    else
        result = m
    end
    return result:get(h.rest(path))
end

types = {
    program = function(o)
        -- perhaps better to create an additional object here?
        -- that way, calling to_lua would be idempotent...
        local n = o.node:named_child_count()
        for i=0,n-1 do
            o:add(Clojure:new({
                node = o.node:named_child(i),
                delimiter = {"(", ")"}
            }):to_lua())
        end
        return o
    end,
    ["nil"] = function(o)
        return Clojure:new({
                node = o.node,
                ratype = "nil",
                string = "nil"})
    end,
    vector = function(o)
        local vector = Clojure:new({
            ratype = "vector",
            node = o.node,
            delimiter = {"[", "]"}})
        local n = o.node:named_child_count()
        for i=0,n-1 do
            vector:add(Clojure:new({node = o.node:named_child(i)}):to_lua())
        end
        return vector
    end,
    list = function(o)
        local list = Clojure:new({ratype = "list",
                                  node = o.node,
                                  delimiter = {"(", ")"}})
        local n = o.node:named_child_count()
        for i=0,n-1 do
            list:add(Clojure:new({node = o.node:named_child(i)}):to_lua())
        end
        return list
    end,
    set = function(o)
        local set = Clojure:new({ratype = "set",
                                  node = o.node,
                                  delimiter = {"#{", "}"}})
        local n = o.node:named_child_count()
        for i=0,n-1 do
            set:add(Clojure:new({node = o.node:named_child(i)}):to_lua())
        end
        return set
    end,
    hash_map = function(o)
        local m = Clojure:new({
            node = o.node,
            ratype = "hash_map",
            delimiter = {"{", "}"}})
        local kv = o.node:named_child_count()
        if kv<2 then return m end
        for i=0,kv-2,2 do
            m:add(Clojure:new({node = o.node:named_child(i)}):to_lua())
            m:add(Clojure:new({node = o.node:named_child(i+1)}):to_lua())
        end
        return m
    end,
    number = function(o)
        return Clojure:new({
                node = o.node,
                ratype = "number",
                string = o:raw_string()})
    end,
    boolean = function(o)
        return Clojure:new({
                node = o.node,
                ratype = "boolean",
                string = o:raw_string()})
    end,
    string = function(o)
        return Clojure:new({
                node = o.node,
                ratype = "string",
                string = o:raw_string()})
    end,
    keyword = function(o)
        return Clojure:new({
                node = o.node,
                ratype = "keyword",
                string = o:raw_string()})
    end,
    symbol = function(o)
        return Clojure:new({
                node = o.node,
                ratype = "symbol",
                string = o:raw_string()})
    end,
    quote = function(o)
        local quote = Clojure:new({ratype = "quote",
                                  node = o.node,
                                  delimiter = {"(quote ", ")"}})
        local n = o.node:named_child_count()
        for i=0,n-1 do
            quote:add(Clojure:new({node = o.node:named_child(i)}):to_lua())
        end
        return quote
    end,
    tag = function(o)
        return Clojure:new({
                node = o.node,
                ratype = "tag",
                string = o:raw_string()})
    end,
    elision = function(o)
        return Clojure:new({
                node = o.node,
                ratype = "elision",
                string = Clojure.elision_symbol})
    end,
    tagged_literal = function(o)
        local tagged = Clojure:new({
            ratype = "tagged_literal",
            node = o.node,
            delimiter = {"<", ">"}})
        local n = o.node:named_child_count()
        for i=0,n-1 do
            tagged:add(Clojure:new({node = o.node:named_child(i)}):to_lua())
        end
        return tagged
    end,
    interop = function(o)
        return Clojure:new({
                node = o.node,
                ratype = "interop",
                string = o:raw_string()})
    end,
    ["error"] = function(o)
        local obj = {}
        if not o then
            obj = {
                ratype = "parseError",
                string = "parseError"}
        else
            obj = {
                node = o.node,
                ratype = "unknownType",
                string = "unrecoginzed type: "..o.node:type()}
        end
        return Clojure:new(obj)
    end
}


return Clojure
