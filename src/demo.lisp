;;;; Starting the demo over, on purpose: one call puts the demo's starting source back in src/aquarium.lisp, loads it into
;;;; the image and sets the tank to its first four fish. The starting source is demo/aquarium.lisp (the file as the first
;;;; commit had it); src/aquarium.lisp is what the demo changes. The reset is a function here, not in aquarium.lisp,
;;;; because it rewrites that file.
(in-package :aquarium)

(declaim (notinline project-file file-text unused-file reset-demo))

(defun project-file (relative)
  "The file RELATIVE (a string) to the aquarium project's directory."
  (asdf:system-relative-pathname :aquarium relative))

(defun file-text (path)
  (with-open-file (in path :external-format :utf-8)
    (let ((text (make-string (file-length in))))
      (subseq text 0 (read-sequence text in)))))

(defun unused-file (directory stem)
  "A file in DIRECTORY called STEM.lisp, or STEM-2.lisp, STEM-3.lisp ... the first that does not exist yet."
  (loop for n from 1
        for file = (merge-pathnames (if (= n 1) (format nil "~a.lisp" stem) (format nil "~a-~d.lisp" stem n)) directory)
        unless (probe-file file) return file))

(defun reset-demo (&key (source (project-file "src/aquarium.lisp")) (start (project-file "demo/aquarium.lisp"))
                        (keep-in (project-file "run/")) (tank *tank*) (load t))
  "Start the demo over. Copy the starting source START over SOURCE; first keep what SOURCE held in KEEP-IN, as
   aquarium-before-reset-<date and time>.lisp (never over a file that is there), unless it was already the starting
   source. Then LOAD the new SOURCE into the image, which makes every definition the demo changed the starting one, and
   give TANK (by default the running one, the same object) its first four fish and tick 0. Returns a list: the file
   kept (or NIL), and the fish count."
  (let* ((old (file-text source))
         (new (file-text start))
         (kept (unless (string= old new)
                 (multiple-value-bind (second minute hour day month year) (decode-universal-time (get-universal-time))
                   (unused-file keep-in (format nil "aquarium-before-reset-~d~2,'0d~2,'0d-~2,'0d~2,'0d~2,'0d"
                                                year month day hour minute second))))))
    (when kept
      (ensure-directories-exist kept)
      (uiop:copy-file source kept))
    (uiop:copy-file start source)
    (unless (string= (file-text source) new)
      (error "~a does not hold the starting source after the copy." source))
    (when load (load source))
    (setf (tank-fish tank) (tank-fish (seed-tank))
          (tank-tick tank) 0)
    (list (and kept (namestring kept)) (length (tank-fish tank)))))
