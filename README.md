# aquarium

A tank of fish, drawn as text once a second by a Common Lisp program that is changed **while it runs**. It is a demo
of one way of working: an always-on SBCL image is the program, a human and [Claude Code](https://claude.com/claude-code)
both talk to it, and the source file is written out from the image after a change has been seen to work, as forms,
never edited as text.

```
+----------------------------------------+
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~|
|                                        |
|     ><(((*>                            |
|                                        |
|               ><(((*>                  |
|                           <*)))><      |
|                   <*)))><              |
|########################################|
+----------------------------------------+
tick 887   fish 4
```

## What the demo shows

Seven steps, each one change made by Claude through the running image while you watch the tank and the source side by
side (`docs/script.md` has the full table):

1. A fifth fish is added to the tank. The source file does not change: state lives in the image.
2. The fish glyph is redefined in the image only. Every fish changes shape at the next frame; the file still shows the
   old `><>`. The image is ahead of the file.
3. That definition is written into `src/aquarium.lisp` as a form. The source window redraws and the changed form
   flashes; nothing else in the file moves.
4. The fish are taught to drift up and down, again in the image first.
5. That definition is written to the file.
6. A deliberate mistake: a redefinition that calls a function that does not exist. The tank shows
   `FRAME FAILED ... FISH-WOBBLE is undefined` instead of fish, the image keeps running, and the saved file brings the
   fish back. A mistake in a live program is seen and repaired, not a crash.
7. The image is asked who calls what, what a function is documented as, and where each definition lives; `M-.` in
   Emacs lands on it.

Meanwhile you can type in the REPL, which talks to the same image: `(add-fish *tank* "Zed" :x 10 :y 6 :dx 1)`,
`(inspect *tank*)`, `(describe 'draw)`, or a `defun` of your own that turns every fish into a bubble.

## Running it

You need SBCL (developed on 2.6.9, macOS arm64), [Qlot](https://github.com/fukamachi/qlot), and Emacs with
[Sly](https://github.com/joaotavora/sly) for the editor side. Then, in a clone:

```sh
~/.qlot/bin/qlot install     # the dependencies, including the shared tools (see below)
bin/lisp start               # the always-on image: it draws the tank and listens for Sly on 127.0.0.1:4007
bin/demo                     # a new Emacs with the source, the tank and a REPL, connected to the image
```

On a Mac whose Homebrew OpenSSL is version 4, Qlot's `cl+ssl` fails to load; the first install then needs
`QLOT_SETUP_FILE=` naming `qlot-setup.lisp` from a checkout of lisp-ai-tools, which pins it to `openssl@3`. After that
`bin/lisp qlot ...` passes the file itself.

`bin/lisp eval '(form)'` evaluates in that image from the shell, which is how Claude works on it. `bin/lisp test` loads
the files into a fresh SBCL and runs the suite. `bin/lisp stop` ends the image, and refuses while the image holds a
definition no file has yet. The Slynk port is in `rules/slynk.sexp`; the demo's Emacs side is `demo.el`, which uses the
Sly checkout that the image's Slynk comes from, so the two match.

To run the demo again from the start, evaluate `(reset-demo)` in the REPL: the source goes back to the first commit's
file (kept in `demo/aquarium.lisp`), the image reloads it, and the tank gets its first four fish back.

## How a change flows

```
  bin/lisp eval '(defun fish-glyph ...)'      define it in the image; the fish change at the next frame
  (pending)                                   what the image holds that no file holds
  (run-tests)                                 the suite, inside the image, against what it holds
  (save 'fish-glyph)                          the definition, as typed, into src/aquarium.lisp
  bin/lisp test                               a fresh SBCL loads the files: the arbiter
```

Comments and the docstring typed with a definition reach the file with it. An error in a `bin/lisp eval` request is not
unwound: the reply comes at once with the error, the restarts and the frames, and the failing thread waits, so the
values in the frame can be looked at and the function redefined before the request is restarted. A hook refuses the
Edit and Write tools on a Lisp file and text-processing programs used on one, so the only way to a source file is
through the image.

All of that is shared code, the systems of [lisp-ai-tools](https://github.com/tomelam/lisp-ai-tools), which Qlot
installs inside the project at the commit `qlfile.lock` pins. This project supplies what is its own: the tank
(`src/aquarium.lisp`), the socket server and the Slynk server, `bin/serve.lisp`, the demo and its reset, the tests,
and the rules files.

## Layout

| Path | What it is |
| --- | --- |
| `src/aquarium.lisp` | The tank: fish, stepping, drawing, the once-a-second loop. Its functions are declaimed `notinline`, so a live redefinition reaches callers compiled from the same file. |
| `src/server.lisp`, `src/slynk-server.lisp` | The image's two doors: the Unix socket for `bin/lisp eval` and the hook, and Slynk for Emacs. |
| `src/demo.lisp` | `reset-demo`. |
| `demo.el`, `bin/demo` | The Emacs side of the demo and the script that starts it in a new Emacs. |
| `demo/aquarium.lisp` | The starting source, as the first commit had it. |
| `tests/` | The suite: the tank, redefinition hazards, the reset, the server, and the shared tools' own tests. |
| `rules/` | Data the code reads: the Slynk address, what the hook counts as Lisp, which programs it refuses on Lisp. |
| `docs/script.md` | The seven steps. `docs/debug-in-place.md`: the design and limits of debugging through the socket. |
| `CLAUDE.md` | What Claude Code is told when it works here. |
| `run/` | Sockets, pid, logs, the tank file. Not committed. |

The project clones anywhere, under any directory name, with nothing beside it.
