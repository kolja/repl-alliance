
local uv = require('luv')
local h = require('helpers')
local Repl = {}

function Repl:show_virtual(text)

    local duration = self._virtual
    if not duration then return end

    local line = h.first(vim.api.nvim_win_get_cursor(0)) - 1
    local ns_id = vim.api.nvim_buf_set_virtual_text(0, 0, line, {{" => "},{text}}, {})
    local timer = vim.loop.new_timer()
    timer:start(duration, 0, vim.schedule_wrap(function()
        vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1) -- clear virtual text for entire buffer
    end))
end

function Repl:new (o)
    local obj = o or {
        _port = h.getvar("replPort"),
        _host = h.getvar("replHost"),
        _socket = nil,
        _session = "",
        _stream_error = nil,
        _namespace = h.getvar("replNamespace"),
        _virtual = h.getvar("replVirtual"),
        _buffer = -1,
        _log = {}
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Repl:connect(host, port, namespace)

    if self._socket and uv.is_active(self._socket) then
        uv.close(self._socket)
    end
    self._socket = uv.new_tcp()
    self._host = host or h.getvar("replHost")
    self._port = port or h.getvar("replPort")
    self._namespace = namespace or h.getvar("replNamespace"),

    uv.tcp_connect(self._socket, self._host, self._port, function (err)
        self._stream_error = self._stream_error or err
    end)

    return self
end

function Repl:send_blob(blob)
    local path = h.getvar("replBlobPath")
    if not (path or blob) then
        return
    elseif blob then
        self:eval(blob)
    else
        local size = vim.loop.fs_stat(path)["size"]
        local fh = vim.loop.fs_open(path, "r", 1)
        local blobfile = vim.loop.fs_read(fh, size, 0):gsub("\n", " ")
        self:eval(blobfile)
    end
    return self
end

function Repl:log(msg, where)
    local field = where or "debug"
    local i=0
    local lastentry = h.last(self._log)
    if not lastentry then
        table.insert(self._log,{[field]={msg}})
    elseif not lastentry[field] then
        i = table.maxn(self._log)
        lastentry[field] = {msg}
        table.insert(self._log,i,lastentry)
    else
        i = table.maxn(self._log)
        table.insert(lastentry[field],msg)
        table.insert(self._log,i,lastentry)
    end
end

function Repl:print (...)
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

function Repl:getReplWin()
    local filterfn = function(win)
        return self._buffer == vim.api.nvim_win_get_buf(win)
    end
    return h.first(h.filter( filterfn, vim.api.nvim_list_wins()))
end

function Repl:buffer()
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

function Repl:encode (data)
    return data
end

function Repl:decode (data)
    return data
end

function Repl:callback (response)
    return response
end

-- args: code to eval, callback, options: {callback=<callback_fn>,virtual=<bool>}
function Repl:eval(code, options)

    if code == "" then return end
    local opts = options or {}

    table.insert(self._log, {code=code})

    pcall(function ()
        self:print_prompt(code)
    end)

    local v = h.getvar("replVirtual")
    if opts.virtual and v then
        self._virtual = v
    else
        self._virtual = nil
    end

    cb_wrap = function (callback)
        local callback = opts.callback or self.callback
        local cb = function (data)
            callback(self, data)
        end
        local wrapped = vim.schedule_wrap(cb)
        return function (data)
            wrapped(self:decode(data))
        end
    end

    uv.read_start(self._socket, function(err, chunk)
        if err then error(err)
        elseif chunk then cb_wrap(callback)(chunk)
        else self:read_stop() end
    end)

    uv.write(self._socket, self:encode(code), function(err)
        if err then error(self._stream_error or err) end
    end)
end

function Repl:read_stop()
    if self._stream_error then
        error(self._stream_error)
    end
    uv.read_stop(self._socket)
end

function Repl:describe ()
    print("not implemented")
end

function Repl:loadfile (file)
    print("not implemented")
end

function Repl:close()
    uv.close(self._socket)
end

function Repl:flush()
    self:print(vim.inspect(self._log))
end

return Repl
