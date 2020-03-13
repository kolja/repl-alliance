local h = require('helpers')
local Logentry = require('logentry')
local Log = {}

function Log:new(opts)
    local options = opts or {}
    local obj = vim.tbl_extend("keep", options, {
        action = nil, -- pass as an option or directly to print funciton
        entries = {},
        index = {}, -- maps group_id to entry-index
        elisions = {}
    })
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Log:log(key, msg, group_id)
    local id = self.index[group_id]
    local entry = self.entries[id]
    if entry then
        entry:add(key, msg)
    else
        entry = Logentry:new(self)
        entry:add(key, msg)
        table.insert(self.entries, entry)
        id = #(self.entries)
        if group_id then self.index[group_id] = id end
    end
    return id
end

function Log:each(fn)
    for k,v in ipairs(self.entries) do
        fn(v,k)
    end
end

function Log:print(action)
    if not self.buffer then
        self.buffer = repl:buffer()
    end
    local replWin = repl:getReplWin()
    if not replWin then return end

    self:each(function(entry)
        if entry.meta.needs_refresh then
            entry:print(action)
        end
    end)
end

function Log:register_elisions(obj)
    if obj:is("tagged_literal") and obj.children[1]:is("elision") then
        local action = obj:get({2, ":get"})
        local key = action:get({2})
        local log_id = obj.root.log_id
        self:add_elision({
            key = key:str(),
            log_id = log_id,
            action = action:str(),
            resolve = function(o)
                local spliced = obj:splice(o)
                self:register_elisions(spliced)
            end
        })
    elseif obj:len() > 0 then
        for i,child in ipairs(obj.children) do
            self:register_elisions(child)
        end
    end
    return obj
end

function Log:get_elision(key)
    return h.filter(function(el)
        return el.key == key
    end, self.elisions)[1]
end

function Log:add_elision(data)
    local e = self:get_elision(data.key)
    if e then
        e = vim.tbl_extend("keep", e, data)
    else
        table.insert(self.elisions, data)
        e = data
    end
    return e
end

function Log:remove_elision(key)
    self.elisions = h.remove(function(el)
        return el.key == key
    end, self.elisions)
    return self.elisions
end

function Log:debug()
    self:each(function(entry, i)
        h.pr(vim.tbl_keys(entry.channels))
        --entry:print({[":raw"] = function(e)
        --    return e
        --end})
    end)
end

function Log:last()
    return h.last(self.entries)
end

return Log
