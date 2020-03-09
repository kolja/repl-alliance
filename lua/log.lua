local h = require('helpers')
local Log = {}

function Log:new (o)
    local obj = o or {
        entries = {},
        index = {}, -- maps group_id to entry-index
        bookmark = 0,
        elisions = {}
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Log:needs_refresh(id)
    local entry = self.entries[id]
    if not entry then return nil end

    entry.meta.needs_refresh = true
    return id
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
    entry.meta = {}
    return self:needs_refresh(id)
end

function Log:print(buffer, action)

    local replWin = repl:getReplWin()
    if not replWin then return end

    local entries = h.filter(function(entry,i)
        local state = entry.meta.needs_refresh
        entry.meta.needs_refresh = false
        return state
    end, self.entries)

    local pr = function(entry, buffer, action)
        local out = ""
        local n = vim.api.nvim_buf_line_count(buffer)
        for channel,val in pairs(entry) do
            local ac = action[channel]
            if ac then
                for i, el in ipairs(val) do
                    out = out .. ac(el)
                end
            end
        end
        if not h.isempty(string.gsub(out, "[%s\n]+", "")) then
            out = vim.split(out, "\n")
            local from = entry.meta.from or n
            local to = entry.meta.to or (from + #out)
            vim.api.nvim_buf_set_lines(buffer, from, to, false, out)
            entry.meta.from = from
            entry.meta.to = to
        end
    end

    h.run_in_buffer( function(buffer)
        for i,logentry in ipairs(entries) do
            pr(logentry, buffer, action)
        end
    end, buffer)
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
    local buffer = repl:buffer()
    local pr = function(str)
        local n = vim.api.nvim_buf_line_count(buffer)
        vim.api.nvim_buf_set_lines(buffer, n, -1, false, vim.split(str,"\n"))
    end
    for i, logentry in ipairs(self.entries) do
        pr("---"..i.."---")
        pr(table.concat(vim.tbl_keys(logentry), ", "))
        if logentry[":eval"] then
            pr(vim.inspect(logentry[":eval"]))
        end
    end
end

function Log:last()
    return h.last(self.entries)
end

return Log
