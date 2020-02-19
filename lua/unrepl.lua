local Repl = require('repl')
local h = require('helpers')
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

    return self
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

function UnRepl:print(obj, id)

    local buffer = self:buffer()
    local n = vim.api.nvim_buf_line_count(buffer)
    local mark_id = vim.api.nvim_buf_set_extmark(id * 1000, self._rans, self._buffer, n, 0, {})

    if type(obj) == "string" then
        obj = {obj}
    end
    local pos = vim.api.nvim_buf_get_extmark_by_id(self._buffer, self._rans, mark_id)
    local replWin = repl.getReplWin()
     -- TODO: when the window is closed, remember what needs to be printed
     -- when window is finally opened: flush all the print commands that have accumulated
    if replWin then
        vim.api.nvim_win_set_cursor(replWin, pos)
        nvim_put(obj, "c" , true, true)
    end
end

function UnRepl:callback (response)
    self:log(response, "response")
    vim.api.nvim_buf_set_lines(self._rbuffer, 0, -1, false, vim.split(response, "\n"))
    local ts = parser:parse()

    for i = 0,ts:root():named_child_count() - 1 do
        local luaresp = h.to_lua(ts:root():named_child(i), self._rbuffer)
        local txtresp = h.to_string(ts:root():named_child(i), self._rbuffer)
        local key = luaresp[1]
        local val = luaresp[2]
        local id = luaresp[3] or 0

        if key == ":prompt" and val[":column"] == 1 then
            self:print("--["..id.."]--> "..table.concat(val,""), id)
        end
        if key == ":started-eval" then
            self:log("--started-eval--")
        end
        if key == ":eval" then
            self:print("--eval--", id)
            self:print(txtresp, id)
            self:print(vim.inspect(luaresp), id)
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
