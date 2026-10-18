;;;; The tools every project shares live in ~/lisp-ai/tools/. Their tests are run here too, in this project's image, with
;;;; scratch files in this project's run/.

(in-package :aquarium/tests)

(defun run-shared-form-edit ()
  "Run ~/lisp-ai/tools/form-edit-test.lisp. A missing file is a failure, not a skip."
  (let ((tests (merge-pathnames "../tools/form-edit-test.lisp" (asdf:system-source-directory :aquarium))))
    (cond ((probe-file tests)
           (load tests)
           (incf *failures*
                 (funcall (find-symbol "RUN" "FORM-EDIT-TESTS") (asdf:system-relative-pathname :aquarium "run/"))))
          (t
           (incf *failures*)
           (format t "FAIL: ~a not found, so the form-edit tests did not run~%" tests)))))
