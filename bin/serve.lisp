;;;; Loaded by bin/lisp-server in the always-on image: load the system, listen for Claude on run/lisp.sock and for Sly where
;;;; rules/slynk.sexp says, start ticking the tank into run/tank.txt, never return.
;;;; The first half (load the system, the editor, make SCRATCH) is the same for every project: tools/serve-prelude.lisp.
(load (merge-pathnames "../../tools/serve-prelude.lisp" *load-truename*))

;;; a port already taken must not stop the server coming up
(handler-case (format t "Slynk listening on port ~d~%" (aquarium:start-slynk))
  (error (e) (format t "Slynk NOT started: ~a~%" e)))

(aquarium:start-aquarium (namestring (asdf:system-relative-pathname :aquarium "run/tank.txt")))

(let ((server (aquarium:start-server (namestring (asdf:system-relative-pathname :aquarium "run/lisp.sock")))))
  (with-open-file (out (asdf:system-relative-pathname :aquarium "run/lisp.pid")
                       :direction :output :if-exists :supersede)
    (format out "~d~%" (sb-posix:getpid)))
  (sb-thread:join-thread (aquarium::server-thread server) :default nil))
