local Repl = require('repl')
local h = require('helpers')
local clj = require('Clojure')
local PRepl = Repl:new()

function PRepl:connect (host, port, ns)
    local prepl = Repl.connect(self, host, port, ns)
    self:send_blob() -- directly pass filename to send, or set g:replBlobPath = "/path/to/blobfile.clj"

    local pluginroot = vim.api.nvim_get_var("pluginroot")
    vim.treesitter.require_language("clojure", pluginroot.."bin/clojure.so")

    if not self._rbuffer then -- the raw response goes to _rbuffer. Not the human readable output.
        self._rbuffer = vim.api.nvim_create_buf(false, true) -- listed (false), scratch (true)
    end
    parser = vim.treesitter.get_parser(self._rbuffer, "clojure")

    return self
end

function PRepl:eval(code, options)
    --local add_newline = function (str)
    --    return str.."\n"
    --end
    --local opts = vim.tbl_extend("keep", options, {
    --    encode = add_newline
    --})
    return Repl.eval(self, code, options) --, opts)
end

function PRepl:callback (response)
    response = vim.trim(response)
    self:log(response, "response")
    vim.api.nvim_buf_set_lines(self._rbuffer, 0, -1, false, vim.split(response, "\n"))
    local ts = parser:parse()
    local lua = clj:new({
        node = ts:root(),
        buffer = self._rbuffer
    }):to_lua()

    lua:each( function(response)
        local res = {
            ns   = response:get(":ns"):str(),
            form = response:get(":form"):str(),
            ex   = response:get(":exception"):str(),
            val  = response:get(":val"):str(),
            tag  = response:get(":tag"):str()
        }

        if res.ns then
            self._namespace = h.unescape(res.ns)
            vim.api.nvim_buf_set_name(self:buffer(), self._namespace)
        end
        if res.form then
            self:print(h.unescape(res.form))
        end
        if res.ex == "true" then
            local ex_value = res.val
            vim.api.nvim_buf_set_lines(self._rbuffer, 0, -1, false, vim.split(h.unescape(ex_value), "\n"))
            local ts = parser:parse()
            local ex = clj:new({
                node = ts:root(),
                buffer = self._rbuffer
            }):to_lua()

            local via = ex:get({1, ":via"}):each(function (ex)
                local message = h.unescape(ex:get(":message"):str())
                if message then
                    vim.api.nvim_err_writeln(message)
                    self:show_virtual(message)
                end
                self:print(ex:get(":type"):str()..": "..message)
                self:print("at "..ex:get(":at"):str())
            end)
        else 
            local result = h.unescape(res.val)
            self:print(self._namespace.."=> "..result)
            self:show_virtual(result)
            vim.api.nvim_command("let @+='"..result.."'") -- copy the result
        end
    end)
end

function PRepl:describe ()
    print("not implemented")
end

function PRepl:loadfile (file)
    print("not implemented")
end

return PRepl
