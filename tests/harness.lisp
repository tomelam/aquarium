;;;; One harness for every test file: CHECK counts failures, RUN runs all suites and exits non-zero on any failure.
;;;; The report goes to the terminal and to run/last-test.txt, so it can be read without the loader's warnings around it.
(defpackage :aquarium/tests
  (:use :cl)
  (:export #:run))
(in-package :aquarium/tests)

(defvar *failures* 0)

(defmacro check (form-or-label &optional (form nil form-p))
  "Count a failure unless FORM is true. With two arguments the first is a label printed on failure."
  (let ((label (if form-p form-or-label (list 'quote form-or-label)))
        (test (if form-p form form-or-label)))
    `(unless ,test
       (incf *failures*)
       (format t "FAIL: ~a~%" ,(if form-p label `(prin1-to-string ,label))))))

(defun check-equal (label actual expected)
  "Count a failure naming LABEL, EXPECTED and ACTUAL unless they are EQUAL."
  (unless (equal actual expected)
    (incf *failures*)
    (format t "FAIL ~s: expected ~s, got ~s~%" label expected actual)))

(defun report-path ()
  (let ((path (asdf:system-relative-pathname :aquarium "run/last-test.txt")))
    (ensure-directories-exist path)
    path))

(defun run ()
  (setf *failures* 0)
  (with-open-file (report (report-path) :direction :output :if-exists :supersede)
    (let ((*standard-output* (make-broadcast-stream *standard-output* report)))
      (run-aquarium-tests)
      (run-redefinition-tests)
      (run-shared-debug)
      (run-reset-tests)
      (run-shared-form-edit)
      (run-shared-profile)
      (run-shared-script)
      (progn (run-server-hook) (run-shared-guard))
      (if (zerop *failures*)
          (format t "all checks passed~%")
          (format t "~d check(s) failed~%" *failures*))))
  (unless (zerop *failures*) (uiop/image:quit 1)))
