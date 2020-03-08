
local uv = require('luv')
local h = require('helpers')
local Log = require('log')
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
        _namespace = h.getvar("replNamespace"), -- current clojure namespace
        _rans = vim.api.nvim_create_namespace("RAnamespace"), -- repl-alliance namespace
        _virtual = h.getvar("replVirtual"),
        _buffer = -1,
        _log = Log:new()
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

function Repl:send_blob(blobpath)
    local opts = options or {}
    local path = blobpath or h.getvar("replBlobPath")
    if not path then return end
    local size = vim.loop.fs_stat(path)["size"]
    local fh = vim.loop.fs_open(path, "r", 1)
    local blobfile = vim.loop.fs_read(fh, size, 0):gsub("\n", " ")
    self:eval(blobfile, opts)
    return self
end

-- can I just assign Repl.log = self._log.log or something?
function Repl:log(key, msg, group_id)
    return self._log:log(key, msg, group_id)
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

function Repl:buffer(update)
    local buffer_update = function(buffer, tick, first, last, ...)
        vim.api.nvim_win_set_cursor(self:getReplWin(), {last, 0})
        vim.api.nvim_command("normal zz") -- scroll to center
        return false
    end
    local update_fn = update or buffer_update

    if not vim.api.nvim_buf_is_loaded(self._buffer) then
        self._buffer = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(self._buffer, self._namespace)
        vim.api.nvim_buf_set_option(self._buffer, 'buftype', 'nofile')
        vim.api.nvim_buf_set_option(self._buffer, "filetype", "repl")
        vim.api.nvim_buf_set_option(self._buffer, "syntax", "clojure")
        vim.api.nvim_win_set_buf(0,self._buffer)
        vim.api.nvim_command("setlocal nonumber")
        vim.api.nvim_command("setlocal nolist")
        vim.api.nvim_buf_attach(self._buffer, false, {on_lines=update_fn})
    end
    return self._buffer
end

function Repl:callback (response)
    return response
end

-- args: code to eval,
--       options: { callback=<callback_fn>,
--                  encode=<encode_fn>,
--                  decode=<decode_fn>,
--                  virtual=<bool> }
function Repl:eval(code, options)

    if code == "" then return end
    local opts = options or {}

    self._virtual = opts.virtual and h.getvar("replVirtual")
    local encode = opts.encode or h.identity
    local decode = opts.decode or h.identity
    local callback = opts.callback or self.callback

    table.insert(self._log, {code=code})

    pcall(function ()
        self:print_prompt(code)
    end)

    local cb_wrap = function (data)
        vim.schedule_wrap(function(d)
            callback(self, d)
        end)(decode(data))
    end

    uv.read_start(self._socket, function(err, chunk)
        if err then error(err)
        elseif chunk then cb_wrap(chunk)
        else self:read_stop() end
    end)

    uv.write(self._socket, encode(code), function(err)
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
