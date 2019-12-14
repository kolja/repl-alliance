
uv = require('luv')
local b = require('bencode')

local NRepl = {}
NRepl.__index = NRepl

local h = require('helpers')

local cb_wrap = function (callback)
    local wrapped = vim.schedule_wrap(callback)
    return function (chunk)
        local res = b.decode(chunk)
        wrapped(res)
    end
end

function NRepl:showVirtual(text, duration)
    local line = h.first(vim.api.nvim_win_get_cursor(0)) - 1
    local ns_id = vim.api.nvim_buf_set_virtual_text(0, 0, line, {{" => "},{text}}, {})
    local timer = vim.loop.new_timer()
    timer:start(duration, 0, vim.schedule_wrap(function()
        vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1) -- clear virtual text for entire buffer
    end))
end

function NRepl:connect(host, port, namespace)

    if self._socket and uv.is_active(self._socket) then
        uv.close(self._socket)
    end

    local self = setmetatable({
        _port = port or vim.api.nvim_get_var("replPort"),
        _host = host or vim.api.nvim_get_var("replHost"),
        _socket = uv.new_tcp(),
        _session = "",
        _stream_error = nil,
        _namespace = namespace or vim.api.nvim_get_var("replNamespace"),
        _buffer = self._buffer or -1,
        _reading = false,
        _log = self._log or {}
    }, NRepl)

    uv.tcp_connect(self._socket, self._host, self._port, function (err)
        self._stream_error = self._stream_error or err
    end)
    self:new_session()
    return self
end

function NRepl:log(msg, where)
    local field = where or "debug"
    local lastentry = h.last(self._log) or {}
    if not lastentry[field] then lastentry[field] = {} end
    table.insert( lastentry[field], msg )
end

function NRepl:print (...)
    local buffer = self:buffer()
    local str = table.concat( h.map(function (arg)
        if type(arg) == "string" then
            return arg
        else
            return vim.inspect(arg)
        end
    end, {...}), "")
    local n = vim.api.nvim_buf_line_count(buffer)
    if str == "" then return end
    vim.api.nvim_buf_set_lines(buffer, n, -1, false, vim.split(str,"\n"))
end

function NRepl:getReplWin()
    local filterfn = function(win)
        return self._buffer == vim.api.nvim_win_get_buf(win)
    end
    return h.first(h.filter( filterfn, vim.api.nvim_list_wins()))
end

function NRepl:buffer()
    if not vim.api.nvim_buf_is_loaded(self._buffer) then
        local buffer_update = function(buffer, tick, first, last, ...)
            vim.api.nvim_win_set_cursor(self:getReplWin(), {last, 0})
            return false
        end
        self._buffer = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(self._buffer, self._namespace)
        vim.api.nvim_buf_set_option(self._buffer, 'buftype', 'nofile')
        vim.api.nvim_buf_set_option(self._buffer, "filetype", "repl")
        vim.api.nvim_buf_set_option(self._buffer, "syntax", "clojure")
        vim.api.nvim_win_set_buf(0,self._buffer)
        vim.api.nvim_command("setlocal nonumber")
        vim.api.nvim_command("setlocal nolist")
        vim.api.nvim_buf_attach(self._buffer, false, {on_lines=buffer_update})
    end
    return self._buffer
end

-- args: code to eval, show virtual text, callback
function NRepl:eval(code, virtual, cb)

    if code == "" then return end

    table.insert(self._log, {code=code})

    self:print(self._namespace, "=> ", code)
    local v = virtual and vim.api.nvim_get_var("replVirtual")

    local callback = cb or function (response)
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
            if v then self:showVirtual(response.value, v) end
            -- self:print(unpack(vim.tbl_flatten({out, response.value, "\n"})))
            vim.api.nvim_command("let @+="..vim.inspect(response.value)) -- copy the result
        end
        if h.contains(response.status,"done") then self:read_stop() end
    end

    local data = {
        code = code,
        op = "eval",
        id = table.maxn(self._log),
        session = self._session,
        ns = self._namespace
    }

    uv.read_start(self._socket, function(err, chunk)
        if err then error(err)
        elseif chunk then cb_wrap(callback)(chunk)
        else self:read_stop() end
    end)

    uv.write(self._socket, b.encode(data), function(err)
        if err then error(self._stream_error or err) end
    end)
end

function NRepl:read_stop()
    if self._stream_error then
        error(self._stream_error)
    end
    uv.read_stop(self._socket)
end

function NRepl:close()
    uv.close(self._socket)
end

function NRepl:describe()
    local id = table.maxn(self._log)
    local callback = function (response)
        self:print(vim.inspect(h.keys(response.ops)))
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

function NRepl:loadfile(file)
    local id = table.maxn(self._log)
    local file = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local callback = function(response)
        if response.ns then
            self._namespace = response.ns
            vim.api.nvim_buf_set_name(self:buffer(), response.ns)
        end
        self:print(vim.inspect(response))
    end
    local data = {
        op = "load-file",
        id = id,
        file = table.concat(file, "\n"),
        session = self._session,
        ns = self._namespace
    }
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
    uv.read_start(self._socket, function(err, chunk)
        if err then error(err)
        elseif chunk then cb_wrap(callback)(chunk)
        else self:read_stop() end
    end)
    uv.write(self._socket, b.encode({op="clone",id=id}), function(err)
        if err then error(self._stream_error or err) end
    end)
end

function NRepl:flush()
    self:print(vim.inspect(self._log))
end

return NRepl
