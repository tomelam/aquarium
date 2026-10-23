;;;; The tools every project shares bring their tests with them, as the system lisp-ai-tools/tests. They run here, in this
;;;; project's image, with scratch files in this project's run/. A missing system is a load error, not a skipped test.

(in-package :aquarium/tests)

(defun scratch-directory ()
  (asdf:system-relative-pathname :aquarium "run/"))

(defun run-shared-form-edit ()
  (incf *failures* (form-edit-tests:run (scratch-directory))))

(defun run-shared-debug ()
  "The debug tests go through this project's own server, on a socket in run/."
  (incf *failures* (lisp-ai-debug-tests:run (scratch-directory) #'aquarium:start-server #'aquarium:stop-server)))

(defun run-shared-profile ()
  (incf *failures* (lisp-ai-profile-tests:run (scratch-directory))))

(defun run-shared-guard ()
  "A scratch project in run/, then this project's own bin/guard and .claude/settings.json."
  (incf *failures* (lisp-ai-guard-tests:run (scratch-directory) (asdf:system-source-directory :aquarium))))
