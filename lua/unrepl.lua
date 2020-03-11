local Repl = require('repl')
local h = require('helpers')
local clj = require('Clojure')
local UnRepl = Repl:new()

function UnRepl:connect (host, port, ns)
    local unrepl = Repl.connect(self, host, port, ns)
    local pluginroot = h.getvar("pluginroot", "/")

    if not self._rbuffer then -- the raw response goes to _rbuffer. Not the human readable output.
        self._rbuffer = vim.api.nvim_create_buf(true, true) -- listed (false), scratch (true)
    end
    vim.treesitter.add_language(pluginroot.."bin/clojure.so", "clojure")
    parser = vim.treesitter.get_parser(self._rbuffer, "clojure")

    self.elision_index = 0
    self.last_line = 0
    self.elision_symbol = h.getvar("replElision", "●")

    self:send_blob(pluginroot.."bin/blob.clj")

    vim.api.nvim_command("autocmd BufWinEnter * lua repl:bufferChange()")
    return self
end

function UnRepl:bufferChange()
    local replWin = self:getReplWin()
    if replWin then
        repl:print()
    end
end

function UnRepl:eval(code, options)
    local log = self._log
    local wrap = function (code)
        local str = ""
        if (options and options[":elision_key"]) then
            str =  "{:elision_data "..code.." :elision_key "..options[":elision_key"].."}\n"
        else
            log.code = code
            str = code.."\n"
        end
        return str
    end
    local opts = vim.tbl_extend("keep", options, {
        encode = wrap
    })
    return Repl.eval(self, code, opts)
end

function UnRepl:resolve_elision(n)
    local elisions = self._log.elisions
    local el = h.last(elisions)
    if n and (n<=#(elisions)) then el = elisions[n] end
    self:eval(el.action, {[":elision_key"] = el.key})
    self:print() -- sure this is necessary?
end

function UnRepl:print()
    local log = self._log
    local elisions = log.elisions
    local buffer = self:buffer()

    local action = {
        -- ["debug"] [":file"] [":out"] -- ignore
        [":unrepl/hello"] = function(data)
            return "hello unrepl"
        end,
        [":prompt"] = function(data)
            local ns = data:get({"clojure.core/*ns*", 2, 1}):str()
            log.namespace = ns or log.namespace
            return ""
        end,
        [":out"] = function(data)
            return data
        end,
        [":eval"] = function(data)
            local key = data:get({":elision_key"}):str()
            local prompt = (log.namespace or "").."-> "..(log.code or "")
            if (not key) then
                local result = data:str()
                vim.api.nvim_command("let @+='"..result.."'") -- copy the result
                return prompt.."\n"..result
            else
                local e = log:get_elision(key)
                if e then
                    e.resolve(data:get({":elision_data"}))
                    log:remove_elision(key)
                    log.entries[e.log_id].meta.needs_refresh = true
                else
                    vim.api.nvim_err_writeln("unknown elision: "..key)
                    return ""
                end
                return ""
            end
        end
    }
    -- can use self (instead of repl:getReplWin() here?
    if repl:getReplWin() then log:print(buffer, action) end

    -- self:linkMarks(str)
end

function UnRepl:callback (response)
    vim.api.nvim_buf_set_lines(self._rbuffer, 0, -1, false, vim.split(response, "\n"))

    local log = self._log
    local ts = parser:parse()
    local middleware = {
        tagged_literal = function(obj, orig_str)
            local text = ""
            local tag = obj.children[1]
            local tagstr = tag:str()
            local literal = obj.children[2]
            if tag:is("elision") then
                local resolved = tag.resolved
                text = (resolved and resolved:str()) or self.elision_symbol
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
        local id = tonumber(lua:get({3}):str())

        local logindex = log:log(key, val, id)
        local logentry = log.entries[logindex]

        local old_id = nil
        local ek = val:get(":elision_key"):str()
        if ek then
            local el = log:get_elision(ek)
            old_id = el and el.log_id
        end
        response.root.log_id = old_id or logindex

        if key == ":eval" then -- only register elisions under the :eval key (for now)
            log:register_elisions(val)
        end
    end

    self:print()
end

function UnRepl:describe ()
    print("not implemented")
end

function UnRepl:loadfile (file)
    print("not implemented")
end

return UnRepl
