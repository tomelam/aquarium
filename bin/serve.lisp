;;;; Loaded by bin/lisp start in the always-on image: load the system, listen for Claude on run/lisp.sock and for Sly where
;;;; rules/slynk.sexp says, start ticking the tank into run/tank.txt, never return.

(asdf/operate:load-system "aquarium")

;;; Sly's REPLs take the global value of *package*, so they start in the project's package and need no in-package.
(setf (sb-ext:symbol-global-value '*package*) (find-package :aquarium))

;;; SCRATCH is where forms are tried before they go to a file; form-edit refuses a form with a symbol of it. The editor
;;; (lisp-ai-tools), LISP-AI-DEBUG and the workbench LISP-AI-BENCH are loaded with the system, so changing a file costs no
;;; start-up. The workbench keeps the ledger of definitions made in this image (run/pending.sexp) for this project.
(make-package :scratch :use '(:cl :aquarium :lisp-ai-debug :lisp-ai-bench))
(lisp-ai-bench:configure :project :aquarium)

;;; a port already taken must not stop the server coming up
(handler-case (format t "Slynk listening on port ~d~%" (aquarium/server:start-slynk))
  (error (e) (format t "Slynk NOT started: ~a~%" e)))

;;; Every bin/lisp eval request and its reply are written into the Sly REPL after the prompt claude> (lisp-ai-tools/echo)
(lisp-ai-echo:start)

(aquarium:start-aquarium (namestring (asdf:system-relative-pathname :aquarium "run/tank.txt")))

(let ((server (aquarium/server:start-server (namestring (asdf:system-relative-pathname :aquarium "run/lisp.sock")))))
  (with-open-file (out (asdf:system-relative-pathname :aquarium "run/lisp.pid")
                       :direction :output :if-exists :supersede)
    (format out "~d~%" (sb-posix:getpid)))
  (sb-thread:join-thread (aquarium/server:server-thread server) :default nil))
