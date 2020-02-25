local Repl = require('repl')
local h = require('helpers')
local clj = require('Clojure')
local UnRepl = Repl:new()

function UnRepl:connect (host, port, ns)
    local unrepl = Repl.connect(self, host, port, ns)
    local pluginroot = vim.api.nvim_get_var("pluginroot")

    self:send_blob(pluginroot.."bin/blob.clj")
    vim.treesitter.add_language(pluginroot.."bin/clojure.so", "clojure")

    self.elisions = {}
    self.elision_index = 0
    self.elision_symbol = vim.api.nvim_get_var("g:replElision") or "●"

    if not self._rbuffer then -- the raw response goes to _rbuffer. Not the human readable output.
        self._rbuffer = vim.api.nvim_create_buf(false, true) -- listed (false), scratch (true)
    end
    parser = vim.treesitter.get_parser(self._rbuffer, "clojure")

    vim.api.nvim_command("autocmd BufWinEnter * lua repl:hello()")
    return self
end

function UnRepl:hello()
    print("entered REPL window: "..tostring(self:getReplWin()))
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
    local pos = vim.api.nvim_buf_get_extmark_by_id(self._buffer, self._rans, e.mark)
    vim.api.nvim_win_set_cursor(replWin, pos)
end


function UnRepl:printo(obj, id)

    local buffer_update = function(buffer, tick, first, last, lines, ...)
        -- find elisions and link them to extmarks in the repl buffer
        local idx = 1
        for i,v in ipairs(self.elisions) do
            if not v.mark then
                idx = i
            end
        end
        for i,v in ipairs(lines) do
            local oc = h.occur(v, self.elision_symbol)
            if oc then
                for j,col in ipairs(oc) do
                    local mark_id = vim.api.nvim_buf_set_extmark(0, self._rans, buffer, first+i, col, {})
                    local e = self.elisons[idx]
                    e.mark = mark_id
                    idx = idx + 1
                end
            end
        end
        self.elision_index = #(self.elisions)
        vim.api.nvim_win_set_cursor(self:getReplWin(), {last, 0})
        vim.api.nvim_command("normal zz") -- scroll to center
        return false
    end
    -- log to print queue.

    local buffer = self:buffer(buffer_update)

    --local replWin = repl:getReplWin()
     -- TODO: when the window is closed, remember what needs to be printed
     -- when window is finally opened: flush all the print commands that have accumulated
    --if replWin then
    --    repl:print("pos: ", pos)
    --    vim.api.nvim_win_set_cursor(replWin, pos)
    --    vim.api.nvim_put(obj, "c" , true, true)
    --end

    -- or perhaps just call repl:print() instead:
    if type(obj) == "string" then
        str = obj
    else
        str = vim.inspect(obj)
    end
    local n = vim.api.nvim_buf_line_count(buffer)
    if str == "" then return end
    vim.api.nvim_buf_set_lines(buffer, n, -1, false, vim.split(str,"\n"))
end

function UnRepl:callback (response)
    self:log(response, "response")
    vim.api.nvim_buf_set_lines(self._rbuffer, 0, -1, false, vim.split(response, "\n"))
    local ts = parser:parse()

    for i = 0,ts:root():named_child_count() - 1 do
        local middleware = {
            tagged_literal = function(obj, orig_str)
                local text = ""
                local typ = obj.children[1].ratype
                local tag = obj.children[1]:str()
                local literal = obj.children[2]
                if typ == "elision" then
                    local action = literal:get({":get"})
                    local key = action:get({2})
                    -- register and action for this elision
                    if action then
                        table.insert(self.elisions, {key = key:str(), action = action:str()})
                    end
                    text = self.elision_symbol
                elseif tag == "#unrepl/ratio" then
                    text = literal.children[1]:str().."/"..literal.children[2]:str()
                elseif tag == "#unrepl/ns" then
                    text = literal:str()
                elseif tag == "#unrepl/string" then
                    text = literal:str()
                end
                return text
            end}
        local response = clj:new({
            node = ts:root():named_child(i),
            buffer = self._rbuffer,
            elision_symbol = self.elision_symbol,
            intercept = middleware})
        local lua = response:to_lua()

        local key = lua:get({1}):str()
        local val = lua:get({2})
        local id = lua:get({3}):str()

        if key == ":prompt" then
            local column = tonumber(val:get({":column"}):str())
            if column == 1 then
                local ns = val:get({"clojure.core/*ns*", 1}):str()
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
            self:print("--out--", id)
            self:print(val, id)
        end
        if key == ":err" then
            self:print("--err--", id)
            self:print(val, id)
        end
        if key == ":log" then
            self:print("--log--", id)
            self:print(val, id)
        end
        if key == ":exception" then
            self:print("--exception--", id)
            self:print(val, id)
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
