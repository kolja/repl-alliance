
local uv = require('luv')
local Repl = require('repl')
local b = require('bencode')
local h = require('helpers')

local NRepl = Repl:new()

function NRepl:connect (host, port, ns)
    local nrepl = Repl.connect(self, host, port, ns)
    return nrepl:new_session()
end

function NRepl:eval(code, options)
    local encode = function (code)
        local data = {
            code = code,
            op = "eval",
            id = table.maxn(self._log),
            session = self._session,
            ns = self._namespace
        }
        return b.encode(data)
    end
    local decode = b.decode
    return Repl.eval(self, code,
                     vim.tbl_extend("keep",
                                    options,
                                    {encode=encode,
                                     decode=decode}))
end

function NRepl:print_prompt (code)
    self:print(self._namespace, "=> ", code)
end

function NRepl:callback (response)
    self:log(response, "response")
    if response.ns then
        self._namespace = response.ns
        vim.api.nvim_buf_set_name(self:buffer(), response.ns)
    end
    if response.out then
        self:log(response.out, "out")
        self:print(response.out)
    end
    if response.err then
        self:log(response.err, "err")
        self:print(response.err)
    end
    if response.ex then
        self:log(response.ex, "ex")
        self:print(response.ex)
    end
    if response.value then
        local out = h.last(self._log).out or {}
        self:print(response.value)
        self:show_virtual(response.value)
        if v then self:showVirtual(response.value, v) end
        vim.api.nvim_command("let @+="..vim.inspect(response.value)) -- copy the result
    end
    if h.contains(response.status,"done") then self:read_stop() end
end

function NRepl:describe()
    local id = table.maxn(self._log)
    local callback = function (response)
        self:print(vim.inspect(h.keys(response.ops)))
    end
    local cb_wrap = function (cb)
        local wrapped = vim.schedule_wrap(cb)
        return function (data)
            return wrapped(b.decode(data))
        end
    end
    uv.read_start(self._socket, function(err, chunk)
        if err then error(err)
        elseif chunk then cb_wrap(callback)(chunk)
        else self:read_stop() end
    end)
    uv.write(self._socket, b.encode({op="describe",id=id}), function(err)
        if err then error(self._stream_error or err) end
    end)
end

function NRepl:loadfile()
    local id = table.maxn(self._log)
    local file = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local name = vim.api.nvim_buf_get_name(0)
    local callback = function(response)
        if response.ns then
            self._namespace = response.ns
            vim.api.nvim_buf_set_name(self:buffer(), response.ns)
        end
        self:log(response,"loadfile")
        self:print("loaded: "..name)
    end
    local cb_wrap = function (cb)
        local wrapped = vim.schedule_wrap(cb)
        return function (data)
            return wrapped(b.decode(data))
        end
    end
    local data = {
        op = "load-file",
        id = id,
        file = table.concat(file, "\n"),
        session = self._session
    }
    self:log(data, "loadfile")
    uv.read_start(self._socket, function(err, chunk)
        if err then error(err)
        elseif chunk then cb_wrap(callback)(chunk)
        else self:read_stop() end
    end)
    uv.write(self._socket, b.encode(data), function(err)
        if err then error(self._stream_error or err) end
    end)
end

function NRepl:new_session()

    local id = table.maxn(self._log)

    local callback = function (response)
        self._session = response["new-session"]
        self:log(response["new-session"], "session")
    end
    local cb_wrap = function (cb)
        local wrapped = vim.schedule_wrap(cb)
        return function (data)
            return wrapped(b.decode(data))
        end
    end

    uv.read_start(self._socket, function(err, chunk)
        if err then error(err)
        elseif chunk then cb_wrap(callback)(chunk)
        else self:read_stop() end
    end)
    uv.write(self._socket, b.encode({op="clone",id=id}), function(err)
        if err then error(elf._stream_error or err) end
    end)
    return self
end

return NRepl
