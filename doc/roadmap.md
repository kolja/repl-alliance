# Roadmap and Ideas

- Clojure.lua / to_lua
   can it be done that to_lua is somehow called implicitly in the constructor?
   so, you call clj:new() and there is no need to call to_lua() on it?

- Clojure.lua
   Just an idea: perhaps the whole clojure.lua could extend to the treesitter objects?
   Like, instead of clj:new({treesitter:root()}):str() it could be treesitternode:str()

- guess protocol
   if no repl-protocol is has been specified, there ra could make a call
   to the server and try to guess the protocol.
   Also, use find out which namespace is currently in use.

- investigate possible functionality like trace-logging, show signature,
  jump to definition, and so on...

- Clojure.lua:
    move the types-table into it's own file types.lua.
    Consider some api to access types (just an idea)

- bug: (unrepl):
    sometimes, when an elsions is resolved, self:print() doesn't seem
    to get called afterwards

- refactor: log_entry could be it's own class, with print method and all.
    then, log would be a container for log-entries...
