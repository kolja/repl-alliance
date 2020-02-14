local Repl = require('repl')
local h = require('helpers')
local PRepl = Repl:new()

function PRepl:connect (host, port, ns)
    local unrepl = Repl.connect(self, host, port, ns)
    self:send_blob() -- directly pass filename to send, or set g:replBlobPath = "/path/to/blobfile.clj"

    local pluginroot = vim.api.nvim_get_var("pluginroot")
    vim.treesitter.add_language(pluginroot.."bin/clojure.so", "clojure")

    if not self._rbuffer then -- the raw response goes to _rbuffer. Not the human readable output.
        self._rbuffer = vim.api.nvim_create_buf(false, true) -- listed (false), scratch (true)
    end
    parser = vim.treesitter.get_parser(self._rbuffer, "clojure")

    return self
end

function PRepl:eval(code, options)
    local add_newline = function (str)
        return str.."\n"
    end
    local opts = vim.tbl_extend("keep", options, {
        encode = add_newline
    })
    return Repl.eval(self, code, opts)
end

function PRepl:callback (response)
    self:log(response, "response")
    vim.api.nvim_buf_set_lines(self._rbuffer, 0, -1, false, vim.split(response, "\n"))
    local ts = parser:parse()
    local luaresponse = h.to_lua(ts:root(), self._rbuffer)

    for i,res in ipairs(luaresponse) do
        if res[":ns"] then
            self._namespace = h.unescape(res[":ns"])
            vim.api.nvim_buf_set_name(self:buffer(), self._namespace)
        end
        if res[":form"] then
            self:print(h.unescape(res[":form"]))
        end
        if res[":exception"] then
            local e = res[":val"]
            local exception = {}
            if type(e) == "string" then
                vim.api.nvim_buf_set_lines(self._rbuffer, 0, -1, false, vim.split(h.unescape(e), "\n"))
                local ts = parser:parse()
                exception = h.to_lua(ts:root():named_child(0), self._rbuffer)
            else
                exception = e
            end
            for i,ex in ipairs(exception[":via"]) do
                local message = h.unescape(ex[":message"])
                if message then
                    vim.api.nvim_err_writeln(message)
                    self:show_virtual(message)
                end
                self:print(table.concat({ex[":type"], message}, ": "))
                self:print("at "..table.concat(ex[":at"], " "))
            end
        elseif res[":tag"] == ":ret" or res[":tag"] == ":out" then
            local result = h.unescape(res[":val"])
            self:print(self._namespace.."=> "..result)
            self:show_virtual(result)
            vim.api.nvim_command("let @+='"..result.."'") -- copy the result
        end
    end
end

function PRepl:describe ()
    print("not implemented")
end

function PRepl:loadfile (file)
    print("not implemented")
end

return PRepl
