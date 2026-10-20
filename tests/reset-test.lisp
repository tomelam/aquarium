;;;; Starting the demo over (src/demo.lisp): the starting source goes back into the file, what the file held is kept
;;;; unless it was the starting source already, the tank gets its first fish, and with LOAD the image's definitions are the
;;;; starting ones again. Every file the test writes is in a directory of its own, never in src/ or run/.
(in-package :aquarium/tests)

(defun write-text (path text)
  (with-open-file (out path :direction :output :if-exists :supersede :external-format :utf-8)
    (write-string text out)))

(defun files-in (directory)
  (mapcar #'file-namestring (directory (merge-pathnames "*.*" directory))))

(defun run-reset-tests ()
  (let* ((directory (merge-pathnames (format nil "reset-test-~d/" (get-universal-time))
                                     (asdf:system-relative-pathname :aquarium "run/")))
         (source (merge-pathnames "aquarium.lisp" directory))
         (kept-in (merge-pathnames "kept/" directory))
         (start (asdf:system-relative-pathname :aquarium "demo/aquarium.lisp"))
         (real (asdf:system-relative-pathname :aquarium "src/aquarium.lisp"))
         (tank (aquarium:make-tank)))
    (ensure-directories-exist source)
    (unwind-protect
         (progn
          ;; a source the demo has changed, and a tank that is not the first one
          (write-text source (format nil "(in-package :aquarium)~%;; the demo got this far~%"))
          (aquarium:add-fish tank "Zed" :x 1)
          (setf (aquarium:tank-tick tank) 99)
          (let* ((result (aquarium::reset-demo :source source :start start :keep-in kept-in :tank tank :load nil))
                 (kept (first result)))
            (check-equal "the source is the starting source again" (file-text source) (file-text start))
            (check "what the file held is kept" (and kept (search "the demo got this far" (file-text kept))))
            (check-equal "the tank has its first four fish"
                         (mapcar #'aquarium:fish-name (aquarium:tank-fish tank)) '("Ada" "Bob" "Cy" "Di"))
            (check-equal "and tick 0" (aquarium:tank-tick tank) 0)
            (check-equal "the result says the file kept and the fish count" (second result) 4))
          ;; again, with nothing changed: nothing new to keep
          (let ((before (files-in kept-in)))
            (check-equal "a second reset keeps nothing" (first (aquarium::reset-demo :source source :start start :keep-in kept-in :tank tank :load nil)) nil)
            (check-equal "and leaves the kept files as they were" (files-in kept-in) before))
          ;; with LOAD the image's definitions become the starting ones; the real file is loaded again afterwards
          (write-text source (file-text real))
          (unwind-protect
               (progn
                (handler-bind ((sb-kernel:redefinition-warning #'muffle-warning))
                  (aquarium::reset-demo :source source :start start :keep-in kept-in :tank tank))
                (progn
                 (check-equal "after the load, a fish looks as it did at the start" (aquarium:fish-glyph (aquarium:make-fish :dx 1))
                  "><>")
                 (check-equal "two resets in one second keep two files, not one" (length (files-in kept-in)) 2)))
            (handler-bind ((sb-kernel:redefinition-warning #'muffle-warning))
              (load real))
            (check-equal "and the real file brings the finished fish back"
                         (aquarium:fish-glyph (aquarium:make-fish :dx 1)) "><(((*>")))
      (when (probe-file directory)
        (uiop:delete-directory-tree directory :validate t)))))
