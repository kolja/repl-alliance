
nnoremap <silent> <leader>e :set opfunc=EvalCommand<CR>g@
vnoremap <silent> <leader>e :<C-U>call EvalCommand("visual")<CR>
nnoremap <silent> <leader>E :call EvalCommand("prompt")<CR>
vnoremap <silent> <leader>E :<C-U>call EvalCommand("populate")<CR>

command! RAloadfile :call luaeval("repl:loadfile()")
command! RAdescribe :call luaeval("repl:describe()")
command! RAflush :call luaeval("repl:flush()")
command! RAconnect :call ConnectCommand(<q-args>)
command! -nargs=+ RAeval :call EvalCommand("normal", <q-args>)

" repl-window (Filetype repl) commands
command! RAnextElision lua repl:next_elision()
command! RAevalElision lua repl:eval_elision()
autocmd FileType repl nnoremap <leader>n :RAnextElision<cr>
" autocmd FileType repl nnoremap E :RAevalElision<cr>

let g:pluginroot=trim(resolve(expand('<sfile>:p:h')),"plugin")

let g:replPort = get(g:, "replPort", 3722)
let g:replHost = get(g:, "replHost", "127.0.0.1")
let g:replNamespace = get(g:, "replNamespace", "user")
let g:replProtocol = get(g:, "replProtocol", "nrepl")
let g:replVirtual = get(g:, "replVirtual", 1000)
let g:replElision = get(g:, "replElision", "●")

function EvalCommand(type, ...)
    let sel_save = &selection
    let &selection = "inclusive"
    if a:type == "normal"
        let @@ = join(a:000)
    elseif a:type == "visual"
        silent exe "normal! gvy"
    elseif a:type == "line"
        silent exe "normal! '[V']y"
    elseif a:type == "char"
        silent exe "normal! `[v`]y"
    elseif a:type == "prompt"
        let @@ = ""
    elseif a:type == "populate"
        silent exe "normal! gvy"
    endif

    if luaeval("repl==nil")
        call ConnectCommand()
    endif

    if index(["prompt", "populate"], a:type) < 0
        " actually, the second argument should be falsy for a:type=="normal"
        " pls refactor
        call luaeval( 'repl:eval(_A, {virtual=1})', @@ )
    else
        call luaeval( 'repl:eval(_A)', input(luaeval("repl._namespace").." => ", @@) )
    endif

    let &selection = sel_save
endfunction

function ConnectCommand(...)
    let repls = ["NRepl", "SocketRepl", "prepl"]
    let g:replProtocol = repls[input("Connect with NRepl[0] socket Repl[1] or prepl[2] ", 0)]
    let g:replHost = input("Host : ", "127.0.0.1")
    let g:replPort = input("Port : ", "3722")
    let g:replNamespace = input("Namespace : ", "user")
    if g:replProtocol ==? "NRepl"
        lua repl = require("nrepl"):connect()
    elseif g:replProtocol ==? "PRepl"
        lua repl = require("prepl"):connect()
    elseif replProtocol ==? "UnRepl"
        lua repl = require("unrepl"):connect()
    else
        lua repl = require("srepl"):connect()
    endif
endfunction

