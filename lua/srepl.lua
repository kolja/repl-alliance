
uv = require('luv')

local SRepl = {}
SRepl.__index = SRepl

local h = require('helpers')

local cb_wrap = function (callback)
    local wrapped = vim.schedule_wrap(callback)
    return function (chunk)
        wrapped(chunk)
    end
end

function SRepl:showVirtual(text, duration)
    local line = h.first(vim.api.nvim_win_get_cursor(0)) - 1
    local ns_id = vim.api.nvim_buf_set_virtual_text(0, 0, line, {{" => "},{text}}, {})
    local timer = vim.loop.new_timer()
    timer:start(duration, 0, vim.schedule_wrap(function()
        vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1) -- clear virtual text for entire buffer
    end))
end

function SRepl:connect(host, port, namespace)

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
        _log = self._log or {}
    }, SRepl)
    uv.tcp_connect(self._socket, self._host, self._port, function (err)
        self._stream_error = self._stream_error or err
    end)
    return self
end

function SRepl:log(msg, where)
    local field = where or "debug"
    local lastentry = h.last(self._log) or {}
    if not lastentry[field] then lastentry[field] = {} end
    table.insert( lastentry[field], msg )
end

function SRepl:print (...)
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
    vim.api.nvim_buf_set_lines(buffer, n, n, false, vim.split(str,"\n"))
end

function SRepl:getReplWin()
    local filterfn = function(win)
        return self._buffer == vim.api.nvim_win_get_buf(win)
    end
    return h.first(h.filter( filterfn, vim.api.nvim_list_wins()))
end

function SRepl:buffer()
    if not vim.api.nvim_buf_is_loaded(self._buffer) then
        local buffer_update = function(buffer, tick, first, last, ...)
            local n = vim.api.nvim_buf_line_count(buffer) -- argument 'last' not good enough?
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
function SRepl:print_prompt(code)
    local buffer = self:buffer()
    local n = vim.api.nvim_buf_line_count(buffer)
    local last_line = h.last(vim.api.nvim_buf_get_lines(buffer, -2, -1, false))
    local namespace = string.match(last_line, "(.+)=>")
    if namespace then -- guess namespace from prompt
        self._namespace = namespace
        vim.api.nvim_buf_set_name(buffer, namespace)
        vim.api.nvim_buf_set_lines(buffer, -2, -1, false, {last_line..code})
    else
        vim.api.nvim_buf_set_lines(buffer, n, n, false, {"=> "..code})
    end
end

-- args: code to eval, show virtual text, callback
function SRepl:eval(code, virtual, cb)

    if code == "" then return end
    table.insert(self._log, {code=code})
    self:print_prompt(code)

    local callback = cb or function (response)
        self:log(response, "response")
        self:print(response)
    end

    uv.read_start(self._socket, function(err, chunk)
        if err then error(err)
        elseif chunk then cb_wrap(callback)(chunk)
        else self:read_stop() end
    end)

    uv.write(self._socket, code.."\n", function(err)
        if err then error(self._stream_error or err) end
    end)
end

function SRepl:read_stop()
    if self._stream_error then
        error(self._stream_error)
    end
    uv.read_stop(self._socket)
end

function SRepl:close()
    uv.close(self._socket)
end

function SRepl:describe()
    print("not implemented")
end

function SRepl:loadfile(file)
    print("not implemented")
end

function SRepl:flush()
    self:print(vim.inspect(self._log))
end

return SRepl
