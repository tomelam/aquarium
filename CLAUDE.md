# aquarium

A demo, so that Tom can watch the live-image method work: a tank of fish drawn as text once a second into
`run/tank.txt`, in a running SBCL that Claude and Tom both change. The method is in `~/lisp-ai/CLAUDE.md`; the steps of
the demo are in `docs/script.md`.

## Watching

`bin/demo` starts a new Emacs process with the demo, whatever Emacs is already running (`open -n`, then `demo.el` and
`M-x aquarium-demo`); by hand, in a freshly started Emacs: `M-x load-file RET ~/lisp-ai/aquarium/demo.el RET`, then
`M-x aquarium-demo`. The source is
on the left, the tank top right, a Sly REPL (in package `AQUARIUM`) below the tank. The source file is redrawn within
half a second of changing on disk and the part that changed flashes; the tank is redrawn too, without a flash. `demo.el`
does not touch `~/.emacs.d/init.el`.

`demo.el` loads the Emacs half of Sly from the Qlot checkout the image's Slynk comes from, not from ELPA. The two
differ: the checkout's Slynk sends the prompt as (package nickname level history-count [condition]), and ELPA's Sly
1.0.43 reads the history count as a condition, so every prompt said "Debugger entered on 0". If another Sly is already
loaded in the Emacs, `demo.el` stops and says so: restart Emacs.

## The tools in `bin/`

`bin/lisp` is the one way into this project's Lisp, for Claude and for Tom: the words `eval`, `start`, `stop`, `status`,
`test`, `guard` and `qlot`. It is eight lines. The work is done by the script `lisp` of the tools repo
(github.com/tomelam/lisp-ai-tools), which Qlot installs inside this project (`qlfile`, `qlfile.lock`); the name of this
project's ASDF system, `aquarium`, is the one thing `bin/lisp` says, and nothing is found by the name of the directory.
`~/lisp-ai/CLAUDE.md` explains the gateway and the tools. Only `bin/serve.lisp`, what this image does besides answering
on `run/lisp.sock`, is the project's own: it loads the system `aquarium` (which brings the tools), sets `*package*`,
makes the package `scratch` and starts the tank and the servers.

- `bin/lisp start|stop|status`: the always-on SBCL, which also ticks the tank and listens for Sly where
  `rules/slynk.sexp` says. The SessionStart hook in `.claude/settings.json` starts it. `stop` waits until the process
  has exited, so a `start` right after cannot find the old image holding the Slynk port. `start` prints a WARNING on
  stderr (and still exits 0) when Slynk did not come up, because the server is useful without it.
- `bin/lisp eval '(form)'`: evaluate a form in that image, in package `aquarium`. This is how Claude runs Lisp. An error
  is not unwound: the reply comes at once with the error, a session number (`HELD n`), the restarts and the frames, and
  the failing thread waits (4 at most, 300 s each). Then work on it as a Lisp programmer does, with requests of their
  own: `(debug-locals n frame)`, `(debug-eval n frame 'form)`, redefine the broken function,
  `(debug-restart-frame n frame)`, `(debug-invoke n restart-number args...)`, `(debug-abandon n)`. The finished reply
  comes back from the last of these. The code is shared (`debug.lisp` of the tools repo). `debug-restart-frame` is
  refused after an error signalled by a trap (type error, unbound variable, undefined function, wrong argument count):
  it ended the image in tests. Design, limits and what is untested: `docs/debug-in-place.md`.
- `form-edit.lisp` of the tools repo, shared by every project (the image loads it with the system, which depends on
  `lisp-ai-tools`): replace, insert or append top-level forms in a file by name, or change one subform inside a form,
  leaving every other byte as it was. It can delete a form or a subform. Its tests run in `bin/lisp test`
  (`tests/shared-test.lisp`, which calls the shared tests of the system `lisp-ai-tools/tests`).
- `bin/lisp test`: the arbiter. `tests/demo-test.el` is the check of `demo.el`, run by hand with Emacs in batch mode
  while the image is up: `/opt/homebrew/bin/Emacs --batch -Q -l tests/demo-test.el`.

## The workbench, the gate, and what is its own

- The workbench and the gate are the same as in code-as-data, from the shared code of the tools repo
  (`~/lisp-ai/docs/workbench.md` says how a change flows). Lisp is changed in this image and saved from it: `(pending)`,
  `(save 'name :file "src/aquarium.lisp")`, `(save-all)`, `(run-tests)`, `(where 'name)`, `(drop 'name)`, `(new-file
  ...)`, `(add-component ...)` through `bin/lisp eval`; `bin/lisp stop` refuses while anything is unsaved. The ledger's
  mirror is `run/pending.sexp`; `bin/serve.lisp` configures the workbench for `:aquarium`.
- `bin/lisp guard` is the PreToolUse hook on Bash and on Edit, Write and MultiEdit (the logic is `guard.lisp` of the
  tools repo, system `lisp-ai-tools/guard`). It refuses Edit and MultiEdit of a Lisp file, Write over one, a shell
  command that writes one, and a program of `rules/forbidden-programs.sexp` used on Lisp (`rules/lisp-files.sexp` says
  what counts as Lisp); everything else passes. It asks this image first (`src/server.lisp` answers a hook payload
  with the marker `OK:` and the decision) and takes a fresh SBCL when the image does not answer; an answer without
  the marker is no answer. Each denial is a line in `run/gate.log`. `.claude/settings.json` carries no deny list; a
  shared test fails if the hooks are not wired or a deny list comes back.
- The functions in `src/aquarium.lisp` are declaimed `notinline`. Without that, callers compiled from the file keep
  the return type the first definition had, and a redefinition that returns a longer string breaks them.
  `run-redefinition-tests` fails if the declaim goes.

## Replaying the demo

`master` holds the result of the seven steps. The starting source (fish are `><>`) is `demo/aquarium.lisp`, the file as
the first commit had it. To start over, evaluate `(reset-demo)` (in `src/demo.lisp`, package `aquarium`). It copies the
starting source over `src/aquarium.lisp`, loads that file into the image (so every definition the demo changed is the
starting one, and `M-.` still finds its file), and gives the running tank its first four fish and tick 0, in place: the
tank object stays. What the file held is first kept in `run/aquarium-before-reset-<date and time>.lisp`, unless it was
the starting source already. After the demo, `git status` shows `src/aquarium.lisp` as modified when it is not the
result: `git restore src/aquarium.lisp` brings the result back, and a whole-file `(load ...)` brings it into the image.
`bin/lisp test` is written for the result, so it fails on the starting source; its `tests/reset-test.lisp` checks the
reset in a directory of its own, never on `src/`.
