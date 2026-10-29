# The aquarium demo

**To watch it:** `bin/demo`, then press SPACE as often as you like. That is all: `bin/demo` starts the program if it is
not running, and the demo starts itself. `q` ends it at any point.

The screen: the program's source file on the left, with the captions below it; the tank top right; below the tank a
prompt (a Sly REPL) connected to the same running program. Each caption says in plain words what the next SPACE will
do, and then what to look at. Each step is sent to the running program through `bin/lisp eval`, the door Claude Code
uses, so the request and the program's answer appear in the prompt window after `claude>`. When a step writes a
definition into the file, the source window redraws and the definition flashes.

What it shows, in eight steps: data added to the running program does not touch the file; a function changed in the
running program changes it at once, with the file behind; the change is written into the file from the program, as a
form, nothing else moving; a mistake is seen in the running program and repaired without stopping it; and the program
answers questions about itself.

## What it does to the file

The demo begins by putting the starting source (`demo/aquarium.lisp`, the first commit's file) into
`src/aquarium.lisp` and into the image (`reset-demo`), and the tank gets its first four fish. A whole run ends with
`src/aquarium.lisp` exactly as committed. `q` half way puts it back as committed (`git restore`), loads it into the
image, and forgets what the demo left unsaved. So nothing needs restoring by hand.

To keep that promise the demo refuses to start, and says why in the caption window, when `src/aquarium.lisp` has
changes that are not committed or when the image holds definitions no file holds.

## Changing the demo

The steps are data: `demo/steps.sexp`, each a `:do` (what SPACE will do), `:send` (the requests, as text) and `:look`
(what to look at afterwards), with `:intro` and `:end`. The Emacs side is `demo.el`. The texts of `fish-glyph` and
`step-fish` in the steps must be those of `src/aquarium.lisp` byte for byte, or a whole run leaves the file changed.

`tests/demo-test.el` checks the screen and then plays the whole demo, a stop half way, and the refusal, against the
image of the project it sits in. Playing rewrites `src/aquarium.lisp`, so that part runs only in a clone (it prints
`SKIP` in `~/lisp-ai/aquarium/`): clone, give the clone's `rules/slynk.sexp` a free port, `qlot install`, `bin/lisp
start`, then `/opt/homebrew/bin/Emacs --batch -Q -l tests/demo-test.el`. On 2026-10-29: 49 checks passed; with one
character of a step's text changed, the two "as committed" checks failed.
