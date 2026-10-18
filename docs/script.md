# The aquarium demo: seven steps

Claude makes one change at a time and says what to look at; nothing moves until Tom says "next". Every step was
rehearsed in a scratch image on a copy of the source before the first one is shown.

**Before step 1 (Tom):** `M-x load-file RET ~/lisp-ai/aquarium/demo.el RET`, `M-x aquarium-demo`. Fish swim in the tank
window. Do not edit the source buffer by hand during the demo: Emacs reverts it whenever Claude writes the file.

| # | Claude does | Tom watches | Shows |
|---|---|---|---|
| 1 | `(add-fish *tank* "Eve" :x 5 :y 6 :dx 1)` through `bin/eval` | A fifth fish appears in the tank within a second. The source window does not change. | The image holds state; a change to data is not a change to the file. In the REPL: `(length (tank-fish *tank*))` gives 5; `C-c I`, then `*tank*`, opens the Inspector. |
| 2 | Redefines `fish-glyph` in the image only: bigger fish, `><(((*>` and `<*)))><` | Every fish changes shape at the next frame, and they turn at the wall one step sooner. The source window still shows the old `><>`. | The image is now ahead of the file. |
| 3 | Writes that `fish-glyph` form into `src/aquarium.lisp` with `bin/form-edit.lisp` | The source window redraws and the new `fish-glyph` flashes. Nothing else in the file moves. | The file is a record of the image, written as forms, not text search-and-replace. |
| 4 | Redefines `step-fish` in the image: fish also drift up and down | The fish start wandering between rows. | A behaviour change, not just a look. |
| 5 | Writes `step-fish` into the file | The source window redraws; `step-fish` flashes. | The same move as step 3. |
| 6 | Redefines `step-fish` with a mistake (calls a function that does not exist) | The tank window shows `FRAME FAILED ... FISH-WOBBLE is undefined` instead of fish, and the image keeps running. Then Claude loads the saved file, and the fish come back. | A mistake while changing a live program is seen and repaired, not a crash. |
| 7 | Asks the image: who calls `fish-glyph`, what `step-fish` is documented as, where each is defined | Text in the terminal; Tom can press `M-.` on `fish-glyph` in the source window. | Questions answered by the image, not by searching text. |

## Things Tom can type in the REPL (the bottom right window) while waiting

The REPL talks to the same image Claude uses, so everything below shows up in the tank. Nothing here changes the file.
If it goes wrong, Claude restarts the image (`bin/lisp-server stop`, then `start`).

- `*tank*` then `C-c I` (or `(inspect *tank*)`): the Inspector. Press Return on a link to go into a fish, `l` to go back.
- `(add-fish *tank* "Zed" :x 10 :y 6 :dx 1)`: a fish appears within a second.
- `(setf (fish-dx (first (tank-fish *tank*))) -1)`: Ada turns round.
- `(describe 'draw)`, `(apropos "FISH")`, `(sb-introspect:who-calls 'fish-glyph)`: ask the image about itself.
- Type `draw` and press `M-.`: Emacs jumps to its definition in `src/aquarium.lisp`; `M-,` comes back.
- `(defun fish-glyph (f) (if (plusp (fish-dx f)) "(o)" "(o)"))`: every fish becomes a bubble, at the next frame. Claude's
  step 2 replaces this definition, so say so before trying it.

**After:** everything shown is in `src/aquarium.lisp`. To run the demo again, see "Replaying the demo" in `CLAUDE.md`.
