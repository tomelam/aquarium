;;;; The aquarium: a tank of fish, drawn as text once a second into run/tank.txt.
;;;; Everything here is meant to be changed while it runs: redefine a function in the image and the next frame shows it.
;;;; That is why the functions are declaimed NOTINLINE. Without it the compiler assumes, in the callers it compiles from
;;;; this file, that a function still returns what it returned when compiled, and a fish-glyph that returns a longer
;;;; string than the first one breaks every caller.
(in-package :aquarium)

(defstruct fish name x y dx)

(defstruct tank (width 40) (height 8) (fish '()) (tick 0))

(declaim (notinline fish-glyph step-fish tick add-fish seed-tank put-text draw write-frame))

(defun fish-glyph (fish)
  "What a fish looks like. By the way, it is swimming."
  (if (plusp (fish-dx fish))
      "><(((*>"
      "<*)))><"))

(defun step-fish (fish tank)
  "Move FISH one step; at a wall it turns round. It also drifts up or down, or stays on its row."
  (let ((next (+ (fish-x fish) (fish-dx fish))))
    (if (<= 0 next (- (tank-width tank) (length (fish-glyph fish))))
        (setf (fish-x fish) next)
        (setf (fish-dx fish) (- (fish-dx fish))))
    (setf (fish-y fish) (max 1 (min (- (tank-height tank) 2) (+ (fish-y fish) (- (random 3) 1)))))))

(defun tick (tank)
  "Advance TANK by one frame."
  (incf (tank-tick tank))
  (dolist (fish (tank-fish tank))
    (step-fish fish tank))
  tank)

(defun add-fish (tank name &key (x 0) (y 2) (dx 1))
  "Put a new fish called NAME in TANK. Returns the fish."
  (let ((fish (make-fish :name name :x x :y y :dx dx)))
    (setf (tank-fish tank) (append (tank-fish tank) (list fish)))
    fish))

(defun seed-tank ()
  (let ((tank (make-tank)))
    (add-fish tank "Ada" :x 2 :y 2 :dx 1)
    (add-fish tank "Bob" :x 30 :y 3 :dx -1)
    (add-fish tank "Cy" :x 12 :y 4 :dx 1)
    (add-fish tank "Di" :x 22 :y 5 :dx -1)
    tank))

(defvar *tank* (seed-tank) "The tank the running aquarium draws.")

(defun put-text (row column text)
  "Write TEXT into the string ROW from COLUMN on, cut off at the ends of ROW."
  (loop for char across text
        for i from column
        when (< -1 i (length row)) do (setf (char row i) char)))

(defun draw (tank)
  "The frame of TANK as text: a border, the water, the fish, the sand, and a line saying which tick it is."
  (let* ((width (tank-width tank))
         (height (tank-height tank))
         (rows (loop repeat height collect (make-string width :initial-element #\Space))))
    (fill (first rows) #\~)
    (fill (car (last rows)) #\#)
    (dolist (fish (tank-fish tank))
      (put-text (nth (max 1 (min (fish-y fish) (- height 2))) rows) (fish-x fish) (fish-glyph fish)))
    (let ((edge (format nil "+~a+" (make-string width :initial-element #\-))))
      (format nil "~a~%~{|~a|~%~}~a~%tick ~d   fish ~d~%" edge rows edge (tank-tick tank) (length (tank-fish tank))))))

(defun write-frame (tank path)
  "Write the frame of TANK to the file PATH, whole or not at all, so a reader never sees half a frame."
  (let ((temp (concatenate 'string path ".tmp")))
    (with-open-file (out temp :direction :output :if-exists :supersede :external-format :utf-8)
      (write-string (draw tank) out))
    (sb-posix:rename temp path)))

(defvar *aquarium-thread* nil "The thread that ticks the tank and writes its frames, or NIL.")

(defun run-aquarium (tank path interval)
  "Forever: advance TANK, write its frame to PATH, wait INTERVAL seconds. A frame that fails writes its error
   into PATH instead and the next frame tries again, so a mistake made while changing the program is seen, not fatal."
  (loop
    (handler-case (write-frame (tick tank) path)
      (serious-condition (condition)
        (with-open-file (out path :direction :output :if-exists :supersede :external-format :utf-8)
          (format out "FRAME FAILED at tick ~d:~%~a~%" (tank-tick tank) condition))))
    (sleep interval)))

(defun start-aquarium (path &key (tank *tank*) (interval 1))
  "Start ticking TANK in a thread, one frame to the file PATH every INTERVAL seconds."
  (stop-aquarium)
  (setf *aquarium-thread*
          (sb-thread:make-thread (lambda () (run-aquarium tank path interval)) :name "aquarium")))

(defun stop-aquarium ()
  (when (and *aquarium-thread* (sb-thread:thread-alive-p *aquarium-thread*))
    (sb-thread:terminate-thread *aquarium-thread*)
    (sb-thread:join-thread *aquarium-thread* :default nil))
  (setf *aquarium-thread* nil))
