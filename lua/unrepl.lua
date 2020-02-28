local Repl = require('repl')
local h = require('helpers')
local clj = require('Clojure')
local UnRepl = Repl:new()

function UnRepl:connect (host, port, ns)
    local unrepl = Repl.connect(self, host, port, ns)
    local pluginroot = h.getvar("pluginroot", "/")

    if not self._rbuffer then -- the raw response goes to _rbuffer. Not the human readable output.
        self._rbuffer = vim.api.nvim_create_buf(false, true) -- listed (false), scratch (true)
    end
    vim.treesitter.add_language(pluginroot.."bin/clojure.so", "clojure")
    parser = vim.treesitter.get_parser(self._rbuffer, "clojure")

    self.print_queue = {}
    self.elisions = {}
    self.elision_index = 0
    self.elision_symbol = h.getvar("replElision", "●")

    self:send_blob(pluginroot.."bin/blob.clj")

    vim.api.nvim_command("autocmd BufWinEnter * lua repl:bufferChange()")
    return self
end

function UnRepl:bufferChange()
    local replWin = self:getReplWin()
    if replWin then
        self:flushPrintQueue()
    end
end

function UnRepl:eval(code, options)
    local add_newline = function (str)
        return str.."\n"
    end
    local opts = vim.tbl_extend("keep", options, {
        encode = add_newline
    })
    return Repl.eval(self, code, opts)
end

function UnRepl:next_elision()
    local replWin = repl:getReplWin()
    local i = self.elision_index + 1
    if i > #self.elisions then i = 1 end
    local e = self.elisions[i]
    if e and replWin then
        local pos = vim.api.nvim_buf_get_extmark_by_id(self._buffer, self._rans, e.mark)
        vim.api.nvim_win_set_cursor(replWin, pos)
    end
end


function UnRepl:linkMarks(lines)
    -- find elisions and link them to extmarks in the repl buffer
    local idx = 1
    local buffer = self._buffer
    local e = self.elisions
    while (e[idx] and e[idx].mark) do idx = idx + 1 end
    local n = vim.api.nvim_buf_line_count(buffer)

    for i,v in ipairs(lines) do
        local oc = h.occur(v, self.elision_symbol)
        if oc then
            for j,col in ipairs(oc) do
                --local mark_id = vim.api.nvim_buf_set_extmark(buffer, self._rans, buffer, n+i, col-1, {})
                --e[idx].mark = mark_id
                e[idx].pos = {n+i, col}
                idx = idx + 1
            end
        end
    end
end

function UnRepl:print(obj, id)
    local replWin = repl:getReplWin() -- can use self here?
    if replWin and obj == nil then self:flushPrintQueue() end

    local buffer_update = function(buffer, tick, first, last, new_last, ...)
        -- vim.api.nvim_win_set_cursor(self:getReplWin(), {last-1, 0})
        vim.api.nvim_command("normal zz") -- scroll to center
        return false
    end
    local str = ""
    local queue = self.print_queue or {}
    local buffer = self:buffer(buffer_update)

    if type(obj) == "string" then
        str = obj
    else
        str = vim.inspect(obj)
    end
    str = vim.split(str, "\n")
    table.insert(str, "")

    table.insert(queue, {str = str, id = id})

    self:linkMarks(str)
    if replWin then self:flushPrintQueue() end
end

function UnRepl:flushPrintQueue()
    -- elisions: {key: ":X__123", action: "(repl/get?9287 :stuff)", mark: 4}
    local replWin = repl:getReplWin() -- can use self here?
    local currentBuffer = vim.api.nvim_get_current_buf()
    local buffer = self._buffer
    vim.api.nvim_set_current_buf(buffer)
    local e = self.elisions
    for i,v in ipairs(self.print_queue) do
        if v.id then
            local el = h.first(h.filter(function(el) return el.key == v.id end, e))
            -- local mark = (el and el.mark)
            -- local pos = vim.api.nvim_buf_get_extmark_by_id(buffer, self._rans, mark)
            local pos = (el and el.pos)
            vim.api.nvim_win_set_cursor(replWin, pos)
            vim.api.nvim_command("normal x")
            vim.api.nvim_put(v.str, "c" , true, true)
            -- delete extmark and entry in self.elisions
            nvim_buf_del_extmark(buffer, self._rans, mark)
            self.elisions = h.filter(function(el) return not (el.key == v.id) end, e)
        else
            local line = vim.api.nvim_buf_line_count(buffer)
            local col = string.len(vim.api.nvim_buf_get_lines(0, line-1, -1, false)[1])
            vim.api.nvim_win_set_cursor(replWin, {line, col})

            vim.api.nvim_put(v.str, "c" , true, true)
        end
    end
    vim.api.nvim_set_current_buf(currentBuffer)
    self.print_queue = {}
end

function UnRepl:callback (response)
    self:log(response, "response")
    vim.api.nvim_buf_set_lines(self._rbuffer, 0, -1, false, vim.split(response, "\n"))
    local ts = parser:parse()
    local middleware = {
        tagged_literal = function(obj, orig_str)
            local text = ""
            local tag = obj.children[1]
            local tagstr = tag:str()
            local literal = obj.children[2]
            if tag:is("elision") then
                local action = literal:get({":get"})
                local key = action:get({2})
                local resolved = tag.resolved
                if resolved then
                    text = resolved:str()
                elseif action then
                    table.insert(self.elisions, {key = key:str(), action = action:str()})
                    text = self.elision_symbol
                else
                    text = self.elision_symbol
                end
            elseif tagstr == "#unrepl/ratio" then
                text = literal.children[1]:str().."/"..literal.children[2]:str()
            elseif tagstr == "#unrepl/*ns*" then
                text = literal.children[1]:str()
            elseif tagstr == "#unrepl/ns" then
                text = literal:str()
            elseif tagstr == "#unrepl/string" then
                text = literal:str()
            end
            return text
        end}

    for i = 0,ts:root():named_child_count() - 1 do
        local response = clj:new({
            node = ts:root():named_child(i),
            buffer = self._rbuffer,
            elision_symbol = self.elision_symbol,
            intercept = middleware})
        local lua = response:to_lua()

        local key = lua:get({1}):str()
        local val = lua:get({2})
        local id = lua:get({3}):str()

        if key == ":read" then
        end
        if key == ":prompt" then
            local column = tonumber(val:get({":column"}):str())
            if column == 1 then
                local ns = val:get({"clojure.core/*ns*", 2, 1}):str()
                self:print(ns.."-> ")
            end
        end
        if key == ":started-eval" then
            self:log("--started-eval--")
        end
        if key == ":eval" then
            self:print(val:str())
            -- self:show_virtual(result)
            -- vim.api.nvim_command("let @+='"..result.."'") -- copy the result
        end
        if key == ":out" then
            self:print("--out--")
            self:print(val)
        end
        if key == ":err" then
            self:print("--err--")
            self:print(val)
        end
        if key == ":log" then
            self:print("--log--")
            self:print(val)
        end
        if key == ":exception" then
            self:print("--exception--")
            self:print(val)
        end
    end
end

function UnRepl:describe ()
    print("not implemented")
end

function UnRepl:loadfile (file)
    print("not implemented")
end

return UnRepl
