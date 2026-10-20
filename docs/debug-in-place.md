# Debug in place: design (2026-10-20)

Status: **approved by Tom on 2026-10-20, all five decisions as proposed; not built yet**. Nothing in `src/` has changed. The
prototype is in `run/debug-prototype/` (ignored by git; its `README.txt` says how to rerun it).

## Why

A Lisp programmer who meets an error looks at the frame, fixes the definition, and restarts the frame. Today Claude
cannot, because `eval-request` in `src/server.lisp` unwinds the stack with `handler-case` and only a text line is left.
The fix is to leave the failing thread alive, with its stack, and let later requests work on it.

## The reply format today (read from `src/server.lisp`; examples run on the real image on 2026-10-20)

A request is Lisp text on a Unix socket. The reply is what the forms printed, then one printed line per value. The
connection then closes. `bin/eval` exits 0 in every case below.

    $ bin/eval '(progn (format t "hello~%") (values 1 "two"))'
    hello
    1
    "two"

    $ bin/eval '(progn (format t "before~%") (/ 1 0))'
    before
    ERROR: arithmetic error DIVISION-BY-ZERO signalled
    Operation was (/ 1 0).

An error ends the request. The output printed before it stays. The `ERROR:` line is the last one.

## What the prototype showed (tested, in a fresh SBCL, plain threads)

- An error in a worker thread can be held. `handler-bind` calls a function that keeps the thread inside
  `slynk-backend:call-with-debugging-environment` and waits for commands from a mailbox.
- Slynk's backend then works from that thread: `compute-backtrace`, `frame-locals`, `eval-in-frame`, `restart-frame`.
- **Redefine and restart works.** After the broken function was redefined from another thread, restarting its frame
  ran the new definition, and the original call finished with the new answer (cases A, A2).
- A restart the code itself establishes (`use-value`) can be invoked by number with a value (case B).
- Nobody answering: the thread is released after the timeout and the call ends as abandoned (case C).
- Two held errors at once are independent. Aborting one left the other answering (case E).
- **A held thread keeps its locks.** Another thread asking for the same lock waited and got nothing in 1 s; after the
  held thread was aborted the lock was free (case L).
- **Debug level decides what can be seen** (case T, compiler policy `debug`):

  | policy | frame of a function whose last act is the failing call (tail call) | frame of a function with the call inside | local variables |
  |---|---|---|---|
  | debug 1 (the default here) | **absent** | present | arguments only; `let` variables unbound |
  | debug 2 | **absent** | present | arguments only; `let` variables unbound |
  | debug 3 | present | present | arguments and `let` variables |

  Even at debug 1, an argument that the function no longer uses shows as `#<unused argument>`.
- The running image and the fresh test image have the same default policy (debug 1), so these results apply to the
  project's code as it is compiled today.

## The reply format proposed

**A request that succeeds is unchanged, byte for byte.** Only the error reply changes. Its first line still starts
`ERROR:`, so anything that looks for that still works.

    $ bin/eval '(progn (format t "before~%") (outer 2))'
    before
    ERROR: arithmetic error DIVISION-BY-ZERO signalled
    Operation was (/ 100 0).
    HELD 7: the thread is waiting; nothing was unwound. It is abandoned after 300 s without a command.
    restarts:
      0 ABORT    unwind the request, as before
      1 USE-VALUE   Use another value instead of the quotient.     (only when the code establishes it)
    frames:
      0 (SB-KERNEL::INTEGER-/-INTEGER 100 0)
      1 (OUTER 2)
      2 ...

The reply is sent at once and the connection closes, so `bin/eval` returns. The request is not finished: its thread is
held.

The commands are ordinary Lisp forms, sent the same way, to the same door. Each is a function in package `aquarium`:

    (debug-frames 7)                      the frames, as above
    (debug-locals 7 1)                    ((X 2)) -- the variables of frame 1
    (debug-eval 7 1 '(list x))            evaluate a form in frame 1
    (debug-restart-frame 7 1)             run frame 1 again with its arguments (picks up a redefinition)
    (debug-invoke 7 1 42)                 take restart 1, with arguments if it wants them
    (debug-abandon 7)                     same as restart 0
    (debug-result 7)                      what the original request printed and returned, once it has finished

`debug-result` exists because the first connection is already closed when the held request finally completes. Its output
and values are kept under the id, in the old format, until read or until a limit is reached.

## Slynk is used as a library, not as a door

The transport is the Unix socket that `bin/eval` already uses. Neither Sly (the Emacs half) nor Slynk's TCP port is
involved. Slynk, the Lisp half, is a package already loaded in the image, and the design calls a few of its functions in
`slynk-backend`, as one calls any library. They wrap SBCL's own debugger internals (`sb-di`). Four examples from the
prototype, with what each did there:

- `call-with-debugging-environment` sets up the context in which frame numbers mean something. Inside it, frame 0 is the
  frame that signalled, and the other functions below take frame numbers.
- `compute-backtrace` and `print-frame` gave the frame list: `(1 . "(OUTER 2)")`.
- `frame-locals` gave a frame's variables as name and value: `((X 2))`. `eval-in-frame` evaluated `(list x (* x 100))` in
  that frame and returned `(2 200)`, so a form can use the frame's variables.
- `restart-frame` ran a frame again with its original arguments, and the redefined function was the one that ran. That is
  the "fix the definition, then restart" step.

Without Slynk, the same would be written directly against `sb-di` (frames, debug functions, variables). I have not tried
that, so I do not know how much longer it would be.

Cost: `aquarium` must have Slynk loaded for these commands, which it always does. The `slynk-backend` functions are
internal to Slynk, so a Slynk update could change them; the Qlot lock file pins the version we use.

## Rules that keep it safe

- A **storage condition** (stack or heap exhausted) is not held; it is handled as today, with an `ERROR:` line.
- At most **4** held sessions. A fifth error is handled as today.
- A session left alone is abandoned after **300 s** (the same as `bin/eval`'s own wait) and then ends as today.
- Only `error` is held. Warnings and interrupts are not.
- Because a held thread keeps its locks, a request that fails while holding one blocks the others until the session ends.
  The reply says which locks the held thread owns if SBCL can tell; otherwise Claude must remember it. (Not yet checked.)

## Decisions for Tom

1. **Reply at once, result later** (proposed), or keep the connection open until the request finishes? Keeping it open
   would make `bin/eval` hang for as long as Claude thinks.
2. **Compile the project's code at `debug 3`**, in the development image only. Cost: somewhat slower code and more
   memory. Gain: tail-call frames and `let` variables visible. How: one `proclaim` in `bin/serve.lisp` before the project is
   loaded; the compiled files (fasls) built earlier at debug 1 must be rebuilt once.
3. The limits above (4 sessions, 300 s).
4. `aquarium` first, `code-as-data` after, as `NEXT.md` says.
5. **Use Slynk's backend functions as a library** (proposed), or write the frame handling directly against `sb-di`.

## Not tested yet

- Anything behind the real socket: reply format, the second connection reaching the held thread, `nc` timing.
- Printing a frame whose arguments are large or circular.
- A held thread inside code that was loaded from a different thread's dynamic bindings (`*package*`, output capture): the
  held thread keeps what the original request bound, which is intended but unseen.
- How Claude's sandbox and `bin/eval`'s `nc -w 300` behave when two `bin/eval` calls overlap.
