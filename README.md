# aquarium

A tank of fish, drawn as text once a second by a Common Lisp program that is changed **while it runs**. It is a demo
of one way of working: an always-on SBCL image is the program, a human and [Claude Code](https://claude.com/claude-code)
both talk to it, and the source file is written out from the image after a change has been seen to work, as forms,
never edited as text.

## Who this is for, in plain words

Most programs are changed by editing a file, stopping the program, and starting it again. This one is never stopped.
You change a definition inside the running program, see the effect at the next frame, and only then write the
definition into the file, from the program. The file is a record of the program, not the other way round. The second
point is that an AI assistant can work the same way: here, Claude Code makes its changes inside the running program
and is refused any other route to the source files.

You do not need to know Lisp to see the first point: [the terminal path](#the-same-thing-with-no-emacs) below takes
two terminal windows and one pasted line. The second point can only be watched with Claude Code at the keyboard; a
clone of this repository shows the program, not the assistant.

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

Eight steps, each one change sent to the running image while you watch the tank and the source side by side. The demo
makes the changes itself, as Claude Code would, and explains each one in plain words; you press SPACE for the next one
(`docs/script.md` says more, and `demo/steps.sexp` holds the steps):

1. A fifth fish is added to the tank. The source file does not change: state lives in the image.
2. The fish glyph is redefined in the image only. Every fish changes shape at the next frame; the file still shows the
   old `><>`. The image is ahead of the file.
3. That definition is written into `src/aquarium.lisp` as a form. The source window redraws and the changed form
   flashes; nothing else in the file moves.
4. The fish are taught to drift up and down, again in the image first.
5. That definition is written to the file.
6. A deliberate mistake: a redefinition that calls a function that does not exist. The tank shows
   `FRAME FAILED ... FISH-WOBBLE is undefined` instead of fish, and the image keeps running.
7. The broken definition is forgotten and the saved one taken back from the file: the fish return. A mistake in a live
   program is seen and repaired, not a crash.
8. The image is asked who calls what, what a function is documented as, and where a definition lives.

At the end the source file is exactly as committed; `q` at any point ends the demo and puts it back. You can also type
in the REPL, which talks to the same image, for example `(add-fish *tank* "Zed" :x 10 :y 6 :dx 1)`; nothing has to be.

## Installing

Three things, on a Mac with [Homebrew](https://brew.sh):

```sh
brew install sbcl openssl@3            # the Lisp, and the library Qlot's installer needs
curl -L https://qlot.tech/installer | sh    # Qlot, into ~/.qlot (its own README: github.com/fukamachi/qlot)
brew install --cask emacs              # Emacs.app, for the demo's editor side; the terminal path below needs none
```

Then clone this repository and, inside it, `~/.qlot/bin/qlot install`. That fetches the shared tools and the libraries
into `.qlot/` and is the whole install.

Tested on macOS 26 on Apple silicon with SBCL 2.6.9. An Intel Mac has not been tried: SBCL and Qlot both support
x86-64, so it should work, but nobody has run it. Emacs comes with [Sly](https://github.com/joaotavora/sly) only if
you add it; `demo.el` brings its own copy, the one that matches the image, so a plain Emacs is enough.

## Running it

In the clone:

```sh
~/.qlot/bin/qlot install     # once: fetches the shared tools and the libraries into .qlot/; that is the whole install
bin/demo                     # starts the program if it is not running, then a new Emacs with the demo; press SPACE
```

That is all it takes: after `bin/demo` there is nothing to type, only SPACE for the next step and `q` to end. Nothing
below has to be read to run the demo; ["How the pieces hand off"](#how-the-pieces-hand-off) is for when you want to
know what those commands did and where to look.

On a Mac whose Homebrew OpenSSL is version 4, Qlot's `cl+ssl` fails to load; the first install then needs
`QLOT_SETUP_FILE=` naming `qlot-setup.lisp` from a checkout of lisp-ai-tools, which pins it to `openssl@3`. After that
`bin/lisp qlot ...` passes the file itself.

`bin/lisp eval '(form)'` evaluates in that image from the shell, which is how Claude works on it. `bin/lisp test` loads
the files into a fresh SBCL and runs the suite. `bin/lisp stop` ends the image, and refuses while the image holds a
definition no file has yet. The Slynk port is in `rules/slynk.sexp`; the demo's Emacs side is `demo.el`, which uses the
Sly checkout that the image's Slynk comes from, so the two match.

The demo starts over by itself each time (SPACE after the last step runs it again): the source goes back to the first
commit's file (kept in `demo/aquarium.lisp`), the image reloads it, and the tank gets its first four fish back. It
refuses to start, and says why, when `src/aquarium.lisp` has changes that are not committed.

## How the pieces hand off

The chain from a typed command to a fish on the screen, with the file and the function at each step, so that you know
what to open and what to skip. Two files are this project's own and short: `bin/serve.lisp` (28 lines) and
`src/aquarium.lisp`. The rest is plumbing shared with other projects, and you can leave it closed.

1. **`bin/lisp start`.** `bin/lisp` is eight lines. It changes to the project directory and hands the word `start` to
   the script `lisp` of the shared tools, which Qlot installed at
   `.qlot/dists/lisp-ai-tools/software/lisp-ai-tools-ref-<commit>/lisp` (`distinfo.txt` in `.qlot/dists/lisp-ai-tools/`
   names the commit). In that script each word selects a shell function; the word `start` selects the function
   `start_server`.
2. **`start_server`**, that shell function, starts SBCL in the background with the option `--load bin/serve.lisp`. It
   starts it through `qlot exec`, which makes the libraries in `.qlot/` visible to SBCL. The shell function then polls
   `run/lisp.sock` until the new image answers a request, for up to 60 seconds, and prints `lisp-server started`. What
   SBCL itself prints goes to `run/lisp-server.log`.
3. **`bin/serve.lisp`** is the whole start-up, in this project. `(asdf:load-system "aquarium")` compiles and loads the
   files `aquarium.asd` names, in this order: `src/package.lisp`, `src/aquarium.lisp`, `src/demo.lisp`,
   `src/server.lisp`, `src/slynk-server.lisp`, with the shared tools they depend on loaded first. Then it calls three
   functions, and finally waits on the thread of the third one with `join-thread`. That thread never ends, and the wait
   is what keeps the process alive; the tank loop and Slynk run in threads of their own.
   - `start-slynk` in `src/slynk-server.lisp` opens Slynk, the door for Emacs, at the address in `rules/slynk.sexp`.
     Then `lisp-ai-echo:start` (shared code) has every `bin/lisp eval` request and its reply written into the Sly REPL
     after `claude>`, so whoever is attached sees what Claude sends.
   - `start-aquarium` in `src/aquarium.lisp` starts a thread that, once a second, moves each fish with `step-fish`,
     draws the frame with `draw`, and writes it to `run/tank.txt`.
   - `start-server` in `src/server.lisp` opens the Unix socket `run/lisp.sock`, the door for `bin/lisp eval` and for
     Claude Code, and serves each connection in a thread of its own.
4. **`bin/demo`** runs `open -na Emacs` with `demo.el`, whose command `aquarium-demo` lays out the three windows,
   watches `src/aquarium.lisp` and `run/tank.txt` for changes on disk, and calls `sly-connect` with the port from
   `rules/slynk.sexp`. From then on the REPL window talks to Slynk inside the running program. Typing `M-x sly` instead
   would start a second, empty SBCL inside Emacs: not this one.
5. **`bin/lisp eval '(form)'`** sends the text with `nc` to `run/lisp.sock`. In `src/server.lisp`, `serve-connection`
   reads it and `handle-request` passes it to `eval-with-debugging`, shared code in the tools' `debug.lisp`, which reads
   and evaluates each form in package `aquarium`, records every definition in the workbench's ledger, and writes the
   values back down the socket. A hook payload from Claude Code takes the same road and is answered by the gate.

So the program is `src/aquarium.lisp`; what starts it is `bin/serve.lisp`; the two doors are `src/server.lisp` and
`src/slynk-server.lisp`, in a package of their own, `aquarium/server`, so that nothing defined in `aquarium` can replace
them; and everything typed at a shell goes through the one script `lisp`.

## The same thing, with no Emacs

Two terminal windows, both in the clone, after `bin/lisp start`. In the first, watch the tank:

```sh
while :; do clear; cat run/tank.txt; sleep 1; done
```

In the second, change the program while it runs. This defines the function that draws a fish, in the running image,
so that every fish is a bubble:

```sh
bin/lisp eval '(defun fish-glyph (f) (if (plusp (fish-dx f)) "(o)" "(o)"))'
```

Within a second the first window shows `(o)` where the fish were, still swimming. Now look at the file:

```sh
git status
```

It prints nothing: `src/aquarium.lisp` is as it was. The change lives only in the running program, and the program
knows it:

```sh
bin/lisp eval '(pending)'          # ((:DEFUN FISH-GLYPH "src/aquarium.lisp")): held by the image, not yet in the file
bin/lisp stop                      # refuses: "lisp-server holds definitions no file holds: ("FISH-GLYPH")"
```

That refusal is the point. The file would be written from the program with `bin/lisp eval "(save 'fish-glyph)"`; to
throw the bubbles away instead, put the file's definition back and forget the unsaved one:

```sh
bin/lisp eval '(load "src/aquarium.lisp")'
bin/lisp eval "(drop 'fish-glyph)"
bin/lisp stop                      # stops
```

The fish come back at the next frame. Everything the demo shows is this, with a larger change and an editor.

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

All of that is shared code, the systems of [lisp-ai-tools](https://github.com/tomelam/lisp-ai-tools). The line
`git lisp-ai-tools https://github.com/tomelam/lisp-ai-tools.git :branch master` in `qlfile` is what makes
`qlot install` fetch it from GitHub, into `.qlot/` inside the project, at the commit `qlfile.lock` pins; no other
step is needed. The files are at `.qlot/dists/lisp-ai-tools/software/lisp-ai-tools-ref-<commit>/`, and the comfortable
way to read them is a clone of [github.com/tomelam/lisp-ai-tools](https://github.com/tomelam/lisp-ai-tools) checked out
at the commit `.qlot/dists/lisp-ai-tools/distinfo.txt` names: the same files, and the tools repo's own README explains
each one. The program itself answers where it loaded them from:
`bin/lisp eval '(asdf:system-source-directory "lisp-ai-tools")'` prints that directory, which is Qlot's cache copy of
the same commit under `~/.cache/qlot/`. This project supplies what is its own: the tank
(`src/aquarium.lisp`), the socket server and the Slynk server, `bin/serve.lisp`, the demo and its reset, the tests,
and the rules files.

## What Claude uses here, with versions

What a Claude Code session in this project has, beyond its usual tools, to program in Lisp the way the demo shows:

| Piece | Where | What it gives Claude |
| --- | --- | --- |
| Instructions | `~/.claude/CLAUDE.md` (Tom's global rules), `~/lisp-ai/CLAUDE.md` (the Lisp method, for every project), `CLAUDE.md` here | Ask the image, change it, check it there, save from it; no text tools on Lisp; held errors; `revise`; checks with `verify`. A clone has only `CLAUDE.md` here and `~/lisp-ai/` on Tom's machine. |
| The image | `bin/serve.lisp`, `run/lisp.sock` | One SBCL, started by the SessionStart hook, ticking the tank; Slynk at `rules/slynk.sexp`; a 4 GB heap (`rules/sbcl-runtime`). |
| The MCP door | `.mcp.json` → `bin/lisp mcp` | The tool `eval`: Lisp text to the image through no shell. |
| The gate | `.claude/settings.json` → `bin/lisp guard` on `Bash` and `Edit\|Write\|MultiEdit` | Refuses changing Lisp code as text and text tools on Lisp; denials in `run/gate.log`. |
| lisp-ai-tools | `qlfile`, `qlfile.lock` | form-edit, held errors (`lisp-ai-debug`), the workbench (`pending`, `save`, `loose-definitions`, ...), the gate, the kit (`source`, `revise`, `verify`, `write-command`, `run-command`), the echo, and their tests. |
| Libraries | `aquarium.asd` | alexandria, cl-ppcre, split-sequence, local-time, cl-csv, com.inuoe.jzon, as in the hackathon's Lisp workspace. |

The tag `pre-hackathon-setup` (also `v0.1.0`) marks the project before it took the hackathon workspace's setup on
2026-10-29.

Versions, checked 2026-10-30; each one's home is the file named, or the machine:

| What | Version | Its home |
| --- | --- | --- |
| lisp-ai-tools | `7b7a78b` (2026-10-29) | `qlfile.lock` |
| Quicklisp dist | `2026-01-01`: alexandria 1.0.1, cl-ppcre 2.1.2, split-sequence 2.0.1, local-time 1.0.6, cl-csv 1.0.7, com.inuoe.jzon 1.1.4, Eclector 0.12.0, Slynk | `qlfile`, `qlfile.lock` |
| SBCL | 2.6.9, macOS 26.6.2 arm64 | the machine |
| Qlot | 1.8.4 | `~/.qlot/` |
| OpenSSL | `openssl@3` 3.5.9, for `qlot install` and `update` only | Homebrew |
| Python | 3.15.2, the `python3` of the tools' `mcp-door` (`bin/lisp mcp`; standard library only) | Homebrew |
| Sly | the dist's own checkout, loaded by `demo.el`; Tom's Emacs pins the same commit, `b01993cf` | `demo.el`, `~/.emacs.d/init.el` |
| Emacs | 31.1 | the machine |
| Claude Code | 2.1.308 | the machine |

## Layout

| Path | What it is |
| --- | --- |
| `src/aquarium.lisp` | The tank: fish, stepping, drawing, the once-a-second loop. Its functions are declaimed `notinline`, so a live redefinition reaches callers compiled from the same file. |
| `src/server.lisp`, `src/slynk-server.lisp` | The image's two doors, in the package `aquarium/server`: the Unix socket for `bin/lisp eval` and the hook, and Slynk for Emacs. |
| `rules/sbcl-runtime` | The image's SBCL runtime options: a 4 GB heap. |
| `src/demo.lisp` | `reset-demo`. |
| `demo.el`, `bin/demo` | The Emacs side of the demo and the script that starts it in a new Emacs. |
| `demo/aquarium.lisp` | The starting source, as the first commit had it. |
| `tests/` | The suite: the tank, redefinition hazards, the reset, the server, and the shared tools' own tests. |
| `rules/` | Data the code reads: the Slynk address, what the hook counts as Lisp, which programs it refuses on Lisp. |
| `docs/script.md` | The seven steps. `docs/debug-in-place.md`: the design and limits of debugging through the socket. |
| `CLAUDE.md` | What Claude Code is told when it works here. |
| `run/` | Sockets, pid, logs, the tank file. Not committed. |

The project clones anywhere, under any directory name, with nothing beside it.
