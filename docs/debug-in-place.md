# Debug in place: design (2026-10-20)

Status: **built in `aquarium` (merged into `master` and pushed, 2026-10-20), then moved to `~/lisp-ai/tools/debug.lisp`
(system `lisp-ai-tools/debug`, package `lisp-ai-debug`) and used by `aquarium` and `code-as-data` alike (branch
`shared-debug`, 2026-10-20).** The running aquarium image was loaded in place with the first version, before the move,
and has not been restarted since. Tom approved all five decisions the same day; "How they ended" says where the build
differs from the proposal. The prototype is in `run/debug-prototype/` (ignored by git; its `README.txt` says how to rerun
it). Where this document says `src/debug.lisp` or `src/server.lisp`, read `tools/debug.lisp` (the commands, the hold) and
each project's `src/server.lisp` (`eval-request` is one call of `eval-with-debugging`; `serve-connection` binds
`*reply-now*`). The commands are in package `lisp-ai-debug`, which each project's package uses.

## Two faults the port found (2026-10-20)

- **A resumed thunk that comes back.** `debug-restart-frame` on a frame that cannot be restarted (an SBCL function such as
  `REDUCE`, which has no debug tag) made the thunk return instead of unwinding. The session stayed `:running` for good and
  every command said "not waiting". Now the session is held again, with `;; not resumed: Cannot restart frame: ...` in
  front of its report.
- **Restarting a frame after an error signalled by a trap ends the image.** A type error, an unbound variable, an
  undefined function or a wrong argument count is signalled by the machine (a trap), not by a call of `error`. After it,
  `restart-frame` works and the request finishes with the right answer; then the thread's end raises the original error
  again, with garbage arguments, unhandled. With `--disable-debugger` the whole image quits (once with a memory fault and
  "maximum interrupt nesting depth exceeded"). Reproduced in a plain SBCL with Slynk and none of this code, in a thread (in
  the main thread nothing happened in the cases tried). `error` and division by zero are not affected, nor is leaving by
  a restart, which is a throw (tried with a plain `throw` out of the handler). SBCL marks a frame that a trap interrupted
  as "escaped" (`sb-di::compiled-frame-escaped`); `trapped-p` looks for one and the session remembers it. The report then
  carries a `NOTE`, and `debug-restart-frame` is refused with an explanation. Sly's own restart-frame command calls the
  same Slynk function and would probably be affected in the same way; that was not tried. The cause inside SBCL was not
  found.

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

## The reply format as built (`src/debug.lisp`, `src/server.lisp`; run through the real socket on 2026-10-20)

**A request that succeeds is unchanged, byte for byte** (`tests/debug-test.lisp` checks `(+ 1 2)` through the socket).
Only the error reply changes. Its first line still starts `ERROR:`, so anything that looks for that still works.

    $ bin/eval '(progn (format t "before~%") (outer 2))'
    before
    ERROR: arithmetic error DIVISION-BY-ZERO signalled
    Operation was (/ 100 0).
    HELD 1: the thread is waiting and nothing was unwound. After 300 s without a command it is abandoned.
    restarts:
      0 ABORT-REQUEST  Unwind the request and reply with the error, as without debugging.
      1 ABORT  abort thread (#<THREAD tid=4699 "aquarium connection" RUNNING {8005C887E3}>)
    frames:
      0 (SB-KERNEL::INTEGER-/-INTEGER 100 0)
      1 (OUTER 2)
      2 (SB-INT:SIMPLE-EVAL-IN-LEXENV (OUTER 2) #<NULL-LEXENV>)
      ...

The reply is sent at once and the connection closes, so `bin/eval` returns. The request is not finished: its thread is
held. Restart 0 is always `ABORT-REQUEST` (the old behaviour: unwind and reply with the `ERROR:` line). Restarts the
code establishes (here none; `USE-VALUE` in another test) follow, then SBCL's own `ABORT`. At most 15 frames are shown;
the report says how to get more.

The commands are ordinary requests, sent the same way, to the same door. Each is a function in package `aquarium`:

    (debug-frames 1 [end])                the frames, as (number . text)
    (debug-locals 1 1)                    ((X 2) (Y 4)) -- the variables of frame 1
    (debug-eval 1 1 '(list x))            evaluate a form in frame 1; returns its values
    (debug-restart-frame 1 1)             run frame 1 again with its arguments (picks up a redefinition)
    (debug-invoke 1 1 42)                 take restart 1, with arguments if it wants them
    (debug-abandon 1)                     take restart 0
    (debug-result 1 [wait])               wait up to WAIT s (default 20), then print the report or the finished reply

`debug-restart-frame` and `debug-invoke` wait for what happens next and print it: the finished reply of the original
request (as if it had never failed, `before` and all), or, if the error comes back, the new report under the **same**
id. A finished reply is read once, then the session is forgotten. `debug-result` is for a request that is still running
after the wait.

A command on a session that does not exist, or is not waiting, prints a `;; ...` line and returns no value; it does not
signal an error, because that would itself be held.

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

- A **storage condition** (stack or heap exhausted) is not held; it is handled as before, with an `ERROR:` line (tried by
  hand: `Control stack exhausted`, no session made).
- At most **4** sessions in use (`*held-limit*`). A fifth error is an ordinary `ERROR:` reply (tested). Finished sessions
  whose result was never read are dropped beyond 8 (`*finished-kept*`; not tested).
- A session left alone is abandoned after **300 s** (`*held-timeout*`, the same as `bin/eval`'s own wait). Its result then
  says `(held session N abandoned after 300 s without a command)` and ends with the `ERROR:` line (tested with 1 s).
- Only `error` is held. Warnings and interrupts are not. Errors that code handles itself (`handler-case`) are not held,
  because the handler that unwinds runs first.
- A direct call of `eval-request` (no socket, as in the old tests) is never held: the hold needs a connection to answer.
- Because a held thread keeps its locks, a request that fails while holding one blocks every thread that wants the lock
  until the session ends (shown in the prototype, case L). Nothing in the report says which locks are held.
- Slynk's own debugger, for Tom's Sly REPL, is untouched: an error evaluated through Sly still opens Sly's debugger and
  makes no session of mine (checked with a batch Emacs against a fresh image).

## Decisions (all five approved by Tom on 2026-10-20) and how they ended

1. **Reply at once, result later.** Built as proposed.
2. **Compile at `debug 3`.** The proposal said one `proclaim` in `bin/serve.lisp`. That did not work, for two reasons found
   by trying it. First, `proclaim` inside a file loaded with `--load` is not seen by other threads: a request thread and a
   Sly thread still compiled at debug 1. Second, `bin/test` rebuilds the project's compiled files at the default policy
   over the ones the server loads. What is built instead: `(sb-ext:restrict-compiler-policy 'debug 3)` at the top of
   `aquarium.asd`. It is global, for all threads, and both `bin/test` and `bin/serve.lisp` load that file first. Checked: a
   function defined in a request thread keeps a tail-call frame and its `let` variable, and a Sly thread reports the
   same restriction.
   ASDF does not see a policy change, so the project's compiled files must be deleted once after the line is added.
3. **Limits** 4 and 300 s, as proposed.
4. **`aquarium` first.** Built here; `code-as-data` is still to do.
5. **Slynk's backend functions as a library.** Built as proposed: `call-with-debugging-environment`, `compute-backtrace`,
   `print-frame`, `frame-locals`, `eval-in-frame`, `restart-frame`.

## Not tested

- Printing a frame whose arguments are large or circular (lines are cut at 200 characters and printed with a short
  `*print-length*`; not tried on a circular argument).
- Two `bin/eval` calls overlapping while Claude's sandbox waits (each call is its own connection; tried one at a time).
- The 300 s timeout itself (only 1 and 2 s were tried).
- A held thread inside code that takes a lock (prototype only).
- A cold start of the real images with all of this (the compiled files must be deleted once before it). Cold starts from
  clean clones were made for both projects on 2026-10-20 and the tests and scenarios pass there. The running aquarium
  image was loaded in place with the first version, so its functions compiled earlier are still at `debug 1`.
- Whether leaving by a restart that the code itself establishes is safe after a trap error in every case (only the
  abandon restart and a plain `throw` were tried).

Tried on 2026-10-20 in the running image, in place: the whole scenario with scratch functions, and the tank kept ticking
while a session was held (tick 72274, then 72277 three seconds later).
