<img src="./repl-alliance.svg">

REPL alliance is a plugin for [neovim](https://neovim.io/) that connects with nREPL as well as socket REPL servers.

The plugin is a work in progress, so be careful.

## Installation

```vim
    Plug 'kolja/repl-alliance'
```

## Usage

| commands and bindings  | effect                                                           |
| ---                    | ---                                                              |
| `:RAconnect`           | asks for protocol, host and port and connects to a repl          |
| `:RAeval <expr>`       | sends <expr> to the repl                                         |
| `:RAdescribe`          | show Commands                                                    |
| `:RAloadfile`          | (re-)evaluates file from the current buffer                      |
| ---                    | ---                                                              |
| `<leader>e<motion>`    | sends the code from <motion> to the repl                         |
| `<leader>e`            | in Visual mode: sends selection to the repl                      |
| `<leader>E`            | prompts for code in the commandline                              |
| `<leader>E`            | in Visual mode: prepopulates the prompt with code from selection |

For example with [guns/vim-sexp](https://github.com/guns/vim-sexp) installed, you can
`<leader>eaf` to evaluate the form under the cursor, and `gvp` to replace it with whatever it evaluated to.

Repl Alliance uses these variables for configuration:

```vim
    replPort = "59555"
    replServer = "127.0.0.1"
    replNamespace = "user"
    replProtocol = "nrepl"

    " for how long to show virtual text (0 : don't show at all)
    replVirtual = 1000
```

You can set them in your vimrc and call `require("nrepl").connect()` or pass the values to `connect()` directly, like so:

```vim
    lua repl = require("nrepl").connect(<host>, <port> [,<namespace>])
```

## How to contribute

Open an issue in the github project and/or create a pull request.

## Contributors

- [Kolja](https://twitter.com/01k)

## License

MIT
