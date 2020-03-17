
local h = require('helpers')
local Logentry = {}

function Logentry:new(log)
    local obj = {
        log = nil, -- pass in via conf
        channels = {},
        meta = {needs_refresh = true}
    }
    obj.log = log
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Logentry:add(key, data)
    if self.channels[key] then
        table.insert(self.channels[key], data)
    else
        self.channels[key] = {data}
    end
    self.meta.needs_refresh = true
    return self
end

function Logentry:print(act)
    local meta = self.meta
    local buffer = self.log.buffer
    local action = act or self.log.action
    local out = h.filter(function(line)
        return not h.isempty(line)
    end, vim.split( action(self), "\n"))
    local n = vim.api.nvim_buf_line_count(buffer)
    local from = meta.from or n
    local to = from + #out
    vim.api.nvim_buf_set_lines(buffer, from, to, false, out)
    meta.from = from
    meta.to = to
    meta.needs_refresh = false
end

return Logentry
