
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
    local out = ""
    local n = vim.api.nvim_buf_line_count(buffer)
    for channel,val in pairs(self.channels) do
        local ac = action[channel]
        if ac then
            for i, el in ipairs(val) do
                out = out .. ac(el)
            end
        end
    end
    if not h.isempty(string.gsub(out, "[%s\n]+", "")) then
        out = vim.split(out, "\n")
        local from = meta.from or n
        local to = meta.to or (from + #out)
        vim.api.nvim_buf_set_lines(buffer, from, to, false, out)
        meta.from = from
        meta.to = to
    end
    meta.needs_refresh = false
end

return Logentry
