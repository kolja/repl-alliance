local Repl = require('repl')
local h = require('helpers')
local clj = require('Clojure')
local UnRepl = Repl:new()

function UnRepl:connect (host, port, ns)
    local unrepl = Repl.connect(self, host, port, ns)
    local pluginroot = vim.api.nvim_get_var("pluginroot")

    self:send_blob(pluginroot.."bin/blob.clj")
    vim.treesitter.add_language(pluginroot.."bin/clojure.so", "clojure")

    if not self._rbuffer then -- the raw response goes to _rbuffer. Not the human readable output.
        self._rbuffer = vim.api.nvim_create_buf(true, true) -- listed (false), scratch (true)
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

function UnRepl:printo(obj, id)

    -- log to print queue.

    local buffer = self:buffer()
    local n = vim.api.nvim_buf_line_count(buffer)
    if n == 0 then n = 1 end
    local mark_id = vim.api.nvim_buf_set_extmark(0, self._rans, buffer, n-1, 0, {})

    if type(obj) == "string" then
        obj = {obj}
    end
    table.insert(obj, "\n")
    local pos = vim.api.nvim_buf_get_extmark_by_id(self._buffer, self._rans, mark_id)
    local replWin = repl:getReplWin()
     -- TODO: when the window is closed, remember what needs to be printed
     -- when window is finally opened: flush all the print commands that have accumulated
    if replWin then
        repl:print("pos: ", pos)
        vim.api.nvim_win_set_cursor(replWin, pos)
        vim.api.nvim_put(obj, "c" , true, true)
    end
end

function UnRepl:callback (response)
    self:log(response, "response")
    vim.api.nvim_buf_set_lines(self._rbuffer, 0, -1, false, vim.split(response, "\n"))
    local ts = parser:parse()

    for i = 0,ts:root():named_child_count() - 1 do
        local response = clj:new({
            node = ts:root():named_child(i),
            buffer = self._rbuffer})
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
