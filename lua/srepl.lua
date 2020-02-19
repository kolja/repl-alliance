local Repl = require('repl')
local SRepl = Repl:new()
local h = require('helpers')

function SRepl:guess_namespace(str)
    local s = h.last(vim.split(str,"\n"))
    return string.match(s, "(.+)=>")
end

function SRepl:eval(code, options)
    local add_newline = function (str)
        return str.."\n"
    end
    local opts = vim.tbl_extend("keep", options, {
        encode = add_newline
    })
    return Repl.eval(self, code, opts)
end

function SRepl:print_prompt (code)
    local buffer = self:buffer()
    local n = vim.api.nvim_buf_line_count(buffer)
    local last_line = h.last(vim.api.nvim_buf_get_lines(buffer, -2, -1, false))
    local namespace = self:guess_namespace(last_line)
    if namespace then -- guess namespace from prompt
        self._namespace = namespace
        vim.api.nvim_buf_set_name(buffer, namespace)
        vim.api.nvim_buf_set_lines(buffer, -2, -1, false, {last_line..code})
    else
        vim.api.nvim_buf_set_lines(buffer, n, n, false, {self._namespace.."=> "..code})
    end
end

function SRepl:callback (response)
    local namespace = self:guess_namespace(response)
    if namespace then
        self._namespace = namespace
        vim.api.nvim_buf_set_name(self:buffer(), namespace)
    end
    self:log(response, "response")
    self:print(response)
end

function SRepl:describe ()
    print("not implemented")
end

function SRepl:loadfile (file)
    print("not implemented")
end

return SRepl
