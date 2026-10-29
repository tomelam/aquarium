;;;; The tools every project shares bring their tests with them, as the system lisp-ai-tools/tests. They run here, in this
;;;; project's image, with scratch files in this project's run/. A missing system is a load error, not a skipped test.

(in-package :aquarium/tests)

(defun scratch-directory ()
  (asdf:system-relative-pathname :aquarium "run/"))

(defun run-shared-form-edit ()
  (incf *failures* (form-edit-tests:run (scratch-directory))))

(defun run-shared-bench ()
  "The workbench, on a scratch project in run/."
  (incf *failures* (lisp-ai-bench-tests:run (scratch-directory))))

(defun run-shared-debug ()
  "The debug tests go through this project's own server, on a socket in run/."
  (incf *failures*
        (lisp-ai-debug-tests:run (scratch-directory) #'aquarium/server:start-server #'aquarium/server:stop-server)))

(defun run-shared-guard ()
  "A scratch project in run/, then this project's own bin/lisp guard and .claude/settings.json."
  (incf *failures* (lisp-ai-guard-tests:run (scratch-directory) (asdf:system-source-directory :aquarium))))

(defun run-shared-script ()
  "The script behind bin/lisp: eval of a healthy server, of a server that is down, and of a start that fails."
  (incf *failures*
        (lisp-ai-script-tests:run (scratch-directory) #'aquarium/server:start-server #'aquarium/server:stop-server)))

(defun run-shared-kit ()
  "The kit (verify, write-command, run-command, source, revise), on a scratch project in run/."
  (incf *failures* (lisp-ai-kit-tests:run (scratch-directory))))

(defun run-shared-echo ()
  "The echo (lisp-ai-tools/echo): each request through this project's own server and its reply, shown in the Sly REPL;
   the script's own probes not."
  (incf *failures*
        (lisp-ai-echo-tests:run (scratch-directory) #'aquarium/server:start-server #'aquarium/server:stop-server)))
