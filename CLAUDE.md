# aquarium

A demo, so that Tom can watch the live-image method work: a tank of fish drawn as text once a second into
`run/tank.txt`, in a running SBCL that Claude and Tom both change. The method is in `~/lisp-ai/CLAUDE.md`; the steps of
the demo are in `docs/script.md`.

## Watching

In a freshly started Emacs: `M-x load-file RET ~/lisp-ai/aquarium/demo.el RET`, then `M-x aquarium-demo`. The source is
on the left, the tank top right, a Sly REPL (in package `AQUARIUM`) below the tank. The source file is redrawn within half
a second of changing on disk and the part that changed flashes; the tank is redrawn too, without a flash.
`demo.el` does not touch `~/.emacs.d/init.el`.

`demo.el` loads the Emacs half of Sly from the Qlot checkout the image's Slynk comes from, not from ELPA. The two
differ: the checkout's Slynk sends the prompt as (package nickname level history-count [condition]), and ELPA's Sly
1.0.43 reads the history count as a condition, so every prompt said "Debugger entered on 0". If another Sly is already
loaded in the Emacs, `demo.el` stops and says so: restart Emacs.

## The tools in `bin/`

`bin/eval`, `bin/lisp-server`, `bin/test` and `bin/qlot` are wrappers of two or three lines, the same in every project:
the work is done by the scripts of the same names in `~/lisp-ai/tools/`, which are told the project's directory (its name
is the name of that directory). Only `bin/serve.lisp`, what this image does besides answering on `run/lisp.sock`, is the
project's own; its first line loads `tools/serve-prelude.lisp`.

- `bin/lisp-server start|stop|status`: the always-on SBCL, which also ticks the tank and listens for Sly where
  `rules/slynk.sexp` says. The SessionStart hook in `.claude/settings.json` starts it. `stop` waits until the process has
  exited, so a `start` right after cannot find the old image holding the Slynk port. `start` prints a WARNING on stderr
  (and still exits 0) when Slynk did not come up, because the server is useful without it.
- `bin/eval '(form)'`: evaluate a form in that image, in package `aquarium`. This is how Claude runs Lisp. An error is
  not unwound: the reply comes at once with the error, a session number (`HELD n`), the restarts and the frames, and the
  failing thread waits (4 at most, 300 s each). Then work on it as a Lisp programmer does, with requests of their own:
  `(debug-locals n frame)`, `(debug-eval n frame 'form)`, redefine the broken function, `(debug-restart-frame n frame)`,
  `(debug-invoke n restart-number args...)`, `(debug-abandon n)`. The finished reply comes back from the last of these.
  Design, limits and what is untested: `docs/debug-in-place.md`.
- `~/lisp-ai/tools/form-edit.lisp`, shared by every project (`tools/serve-prelude.lisp` loads it when the image starts): replace, insert
  or append top-level forms in a file by name, or change one subform inside a form, leaving every other byte as it was.
  It can delete a form or a subform. Its tests run in `bin/test` (`tests/shared-test.lisp`).
- `bin/test`: the arbiter. `tests/demo-test.el` is the check of `demo.el`, run by hand with Emacs in batch mode while the
  image is up: `/opt/homebrew/bin/Emacs --batch -Q -l tests/demo-test.el`.

## What differs from code-as-data

- No guard hook. `permissions.deny` in `.claude/settings.json` is the only layer here; it was generated from
  `rules/forbidden-programs.sexp` by code-as-data's `sync-deny-rules` logic. Change the rules file and regenerate it,
  or copy the guard over, before this project grows.
- The functions in `src/aquarium.lisp` are declaimed `notinline`. Without that, callers compiled from the file keep
  the return type the first definition had, and a redefinition that returns a longer string breaks them.
  `run-redefinition-tests` fails if the declaim goes.

## Replaying the demo

`master` holds the result of the seven steps. The starting source (fish are `><>`) is `demo/aquarium.lisp`, the file as the
first commit had it. To start over, evaluate `(reset-demo)` (in `src/demo.lisp`, package `aquarium`). It copies the starting
source over `src/aquarium.lisp`, loads that file into the image (so every definition the demo changed is the starting one,
and `M-.` still finds its file), and gives the running tank its first four fish and tick 0, in place: the tank object stays.
What the file held is first kept in `run/aquarium-before-reset-<date and time>.lisp`, unless it was the starting source
already. After the demo, `git status` shows `src/aquarium.lisp` as modified when it is not the result: `git restore
src/aquarium.lisp` brings the result back, and a whole-file `(load ...)` brings it into the image.
`bin/test` is written for the result, so it fails on the starting source; its `tests/reset-test.lisp` checks the reset in a
directory of its own, never on `src/`.
