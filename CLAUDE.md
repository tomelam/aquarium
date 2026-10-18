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

Copies of the ones in `~/lisp-ai/code-as-data/bin/`, as the tree file says; there is no shared directory yet.

- `bin/lisp-server start|stop|status`: the always-on SBCL, which also ticks the tank and listens for Sly where
  `rules/slynk.sexp` says. The SessionStart hook in `.claude/settings.json` starts it. `stop` waits until the process has
  exited, so a `start` right after cannot find the old image holding the Slynk port. `start` prints a WARNING on stderr
  (and still exits 0) when Slynk did not come up, because the server is useful without it.
- `bin/eval '(form)'`: evaluate a form in that image, in package `aquarium`. This is how Claude runs Lisp.
- `bin/form-edit.lisp`: replace, insert or append top-level forms in a file by name, leaving every other byte as it was.
  It cannot delete a form, and a form it replaces is reprinted, so comments inside it are lost.
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

The first commit holds the source as the demo starts (fish are `><>`); the second holds the result of the seven steps.
To start over: `bin/lisp-server stop`, `git checkout <first commit> -- src/aquarium.lisp`, `bin/lisp-server start`.
`bin/test` is written for the result, so it fails on the starting source. `run/aquarium-original.lisp` is an ignored copy
of the starting source and can go.
