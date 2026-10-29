;;; The steps of the aquarium demo, read by demo.el. bin/demo is the only thing anyone types: the demo starts the source
;;; over, shows :intro, and each press of SPACE sends one step's :send requests to the running image through
;;; bin/lisp eval (the echo shows each one in the REPL after claude>), then shows the step's :look and the next step's :do.
;;; The texts of fish-glyph and step-fish are those of src/aquarium.lisp as committed, byte for byte, so a whole run
;;; leaves the file exactly as it was. Plain words: the reader may not know Lisp.

(:intro
 "This is a program that is running right now, and it will be changed while it runs.

Top right: what the program draws, a tank of fish, once a second.
Left: the program's source file, src/aquarium.lisp. It has just been put back to how the program started out.
Bottom right: a prompt connected to the same running program. Each change the demo makes appears there after claude>, with the program's answer.

Nothing is recorded or faked: every step is sent to the running program, as Claude Code sends its changes."

 :end
 "That is the whole demo. The source file is exactly as it was before it started.

What it showed: the program is changed while it runs; a change is tried in the running program first and only then written into the file; a mistake is seen and repaired without stopping anything; and the program answers questions about itself.

SPACE runs the demo again from the start. q ends it. You can also type at the prompt yourself, for example
  (add-fish *tank* \"Zed\" :x 10 :y 6 :dx 1)
and press RET."

 :steps
 ((:do "Add a fifth fish, by telling the running program to."
   :send ("(add-fish *tank* \"Eve\" :x 5 :y 6 :dx 1)")
   :look "A fifth fish, Eve, swims in the tank. The source file did not change: the fish is data inside the running program, not code in the file.")

  (:do "Change how a fish is drawn: bigger fish. Only inside the running program, not yet in the file."
   :send ("(defun fish-glyph (fish)
  \"What a fish looks like. By the way, it is swimming.\"
  (if (plusp (fish-dx fish))
      \"><(((*>\"
      \"<*)))><\"))")
   :look "Every fish is bigger at the next frame, and nothing was stopped or restarted. The file on the left still shows the old small fish, ><> and <><: the running program is now ahead of its file.")

  (:do "Write the new fish from the running program into the file."
   :send ("(save 'fish-glyph)")
   :look "The file redraws and the new fish-glyph flashes. Only that definition changed; every other line of the file is exactly as it was.")

  (:do "Teach the fish to drift up and down, again in the running program first."
   :send ("(defun step-fish (fish tank)
  \"Move FISH one step; at a wall it turns round. It also drifts up or down, or stays on its row.\"
  (let ((next (+ (fish-x fish) (fish-dx fish))))
    (if (<= 0 next (- (tank-width tank) (length (fish-glyph fish))))
        (setf (fish-x fish) next)
        (setf (fish-dx fish) (- (fish-dx fish))))
    (setf (fish-y fish) (max 1 (min (- (tank-height tank) 2) (+ (fish-y fish) (- (random 3) 1)))))))")
   :look "The fish wander between rows now. The file has not changed yet.")

  (:do "Write that into the file too."
   :send ("(save 'step-fish)")
   :look "step-fish flashes in the file: the same move as before, a definition written from the running program.")

  (:do "Make a mistake on purpose: a new way of moving that uses something that does not exist (fish-wobble)."
   :send ("(defun step-fish (fish tank)
  \"Move FISH one step, wobbling.\"
  (fish-wobble fish)
  (let ((next (+ (fish-x fish) (fish-dx fish))))
    (if (<= 0 next (- (tank-width tank) (length (fish-glyph fish))))
        (setf (fish-x fish) next)
        (setf (fish-dx fish) (- (fish-dx fish))))))")
   :look "Instead of fish, the tank says FRAME FAILED and that FISH-WOBBLE is undefined. The program is still running: one frame failed, and it says why. The file still holds the good version.")

  (:do "Repair it: forget the broken definition and take the good one back from the file."
   :send ("(progn (drop 'step-fish) (load \"src/aquarium.lisp\") :repaired)")
   :look "The fish are back at the next frame. The mistake was seen and repaired while the program kept running.")

  (:do "Ask the running program about itself: who uses fish-glyph, what step-fish is for, and where it is written."
   :send ("(mapcar #'car (sb-introspect:who-calls 'fish-glyph))"
          "(documentation 'step-fish 'function)"
          "(where 'step-fish)")
   :look "The answers are in the prompt window: the functions that call fish-glyph, the description written with step-fish, and the file it lives in. They come from the program itself, not from searching the text.")))
