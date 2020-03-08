local h = require('helpers')
local Log = {}

function Log:new (o)
    local obj = o or {
        entries = {},
        index = {}, -- maps group_id to entry-index
        bookmark = 0
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Log:log(key, msg, group_id)
    local id = self.index[group_id]
    local entry = self.entries[id]
    if entry and entry[key] then
        table.insert(entry[key], msg)
    elseif entry then
        entry[key] = {msg}
    elseif group_id then
        table.insert(self.entries, {[key] = {msg}})
        self.index[group_id] = #(self.entries)
        entry = h.last(self.entries)
        id = #(self.entries)
    else
        table.insert(self.entries, {debug = {msg}})
        entry = h.last(self.entries)
        id = #(self.entries)
    end
    return id
end

function Log:flush()
    local new_entries = {}
    if #self.entries == self.bookmark then return nil end
    if #self.entries == self.bookmark + 1 then
        new_entries = {h.last(self.entries)}
    else
        new_entries = h.filter(function(v,i)
            return i > self.bookmark
        end, self.entries)
    end
    self.bookmark = #self.entries
    return new_entries
end

function Log:last()
    return h.last(self.entries)
end

return Log
