;;;; The tank: how a frame looks, how fish move, that a frame is written whole, and that a mistake made while the
;;;; aquarium runs shows up in the frame and is gone again when it is fixed.
(in-package :aquarium/tests)

(defun small-tank ()
  (let ((tank (aquarium:make-tank :width 10 :height 4)))
    (aquarium:add-fish tank "Ada" :x 1 :y 1 :dx 1)
    tank))

(defun file-text (path)
  (with-open-file (in path :external-format :utf-8)
    (let ((text (make-string (file-length in))))
      (subseq text 0 (read-sequence text in)))))

(defun wait-for (path needle)
  "The text of PATH once it contains NEEDLE, waiting up to 5 seconds; else whatever it held last."
  (let ((text ""))
    (loop repeat 100
          do (setf text (if (probe-file path) (file-text path) ""))
          until (search needle text)
          do (sleep 0.05))
    text))

(defun run-aquarium-tests ()
  (check-equal "a frame: border, water, fish, sand, and the tick"
               (aquarium:draw (small-tank))
               (let ((nl (string #\Newline)))
                 (concatenate 'string "+----------+" nl "|" (make-string 10 :initial-element #\~) "|" nl
                              "| ><(((*>  |" nl "|          |" nl "|##########|" nl "+----------+" nl
                              "tick 0   fish 1" nl)))
  (let ((tank (small-tank)))
    (aquarium:tick tank)
    (check-equal "a tick moves a fish and counts" (list (aquarium:tank-tick tank) (aquarium:fish-x (first (aquarium:tank-fish tank)))) '(1 2)))
  (let* ((tank (aquarium:make-tank :width 10 :height 4))
         (fish (aquarium:add-fish tank "Bob" :x 3 :y 1 :dx 1)))
    (aquarium:step-fish fish tank)
    (check-equal "at the wall a fish turns and stays" (list (aquarium:fish-x fish) (aquarium:fish-dx fish)) '(3 -1))
    (aquarium:step-fish fish tank)
    (check-equal "and swims back" (aquarium:fish-x fish) 2))
  (let ((tank (aquarium:make-tank :width 10 :height 4)))
    (aquarium:add-fish tank "Cy" :x 9 :y 1 :dx 1)
    (check "a fish half out of the tank is cut off, not an error" (search "|         >|" (aquarium:draw tank))))
  (let ((path (namestring (asdf:system-relative-pathname :aquarium "run/test-frame.txt"))))
    (unwind-protect
         (progn
          (aquarium:write-frame (small-tank) path)
          (check-equal "write-frame writes the frame" (file-text path) (aquarium:draw (small-tank)))
          (check "and leaves no half-written file behind" (not (probe-file (concatenate 'string path ".tmp")))))
      (when (probe-file path) (delete-file path))))
  ;; the running aquarium: an error in a frame is shown in the frame, and the next frame is good once it is fixed
  (let* ((path (namestring (asdf:system-relative-pathname :aquarium "run/test-tank.txt")))
         (tank (small-tank))
         (fish (first (aquarium:tank-fish tank))))
    (unwind-protect
         (progn
          (setf (aquarium:fish-dx fish) :broken)
          (aquarium:start-aquarium path :tank tank :interval 0.05)
          (check "a frame that fails says so in the file" (search "FRAME FAILED" (wait-for path "FRAME FAILED")))
          (setf (aquarium:fish-dx fish) 1)
          (check "and the next frame is good once the mistake is fixed" (search "fish 1" (wait-for path "fish 1"))))
      (aquarium:stop-aquarium)
      (when (probe-file path) (delete-file path))))
  ;; the door for Claude
  (check-equal "a form answers with its printed value" (aquarium::eval-request "(+ 1 2)") (format nil "3~%"))
  (check "an error is a reply, not a dead server" (eql 0 (search "ERROR" (aquarium::eval-request "(error \"boom\")")))))

(defun run-redefinition-tests ()
  "The point of the aquarium: a function redefined while it runs changes what its callers do, even when the new one
   returns something longer than the old one did."
  (let ((original (fdefinition 'aquarium:fish-glyph)))
    (unwind-protect
        (progn
         (setf (fdefinition 'aquarium:fish-glyph)
                 (lambda (fish)
                   (if (plusp (aquarium:fish-dx fish))
                       "><(((((*>"
                       "<*)))))><")))
         (check "a longer glyph reaches the frame" (search "><(((((*>" (aquarium:draw (small-tank))))
         (let* ((tank (aquarium:make-tank :width 10 :height 4)) (fish (aquarium:add-fish tank "Bob" :x 0 :y 1 :dx 1)))
           (aquarium:step-fish fish tank)
           (check-equal "the wall is where the longer glyph ends: one step in"
            (list (aquarium:fish-x fish) (aquarium:fish-dx fish)) '(1 1))
           (aquarium:step-fish fish tank)
           (check-equal "and there the fish turns" (list (aquarium:fish-x fish) (aquarium:fish-dx fish)) '(1 -1))))
      (setf (fdefinition 'aquarium:fish-glyph) original))
    (check-equal "the old glyph is back" (aquarium:fish-glyph (aquarium:make-fish :dx 1)) "><(((*>")))
