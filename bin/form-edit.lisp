;;;; Change a Lisp file as forms without touching the rest of its text: find the span of each top-level form, replace
;;;; the span of a form named in REPLACE, insert forms before a named one, add forms at the end, and replace the header
;;;; comment. New forms are written by the printer (never by hand); everything else stays byte for byte, comments
;;;; included.
(defpackage :form-edit (:use :cl))
(in-package :form-edit)

(defun file-text (path)
  (with-open-file (s path :external-format :utf-8)
    (let ((text (make-string (file-length s))))
      (subseq text 0 (read-sequence text s)))))

(defun skip-blank (text pos)
  "POS moved past whitespace and whole comment lines."
  (loop
    (cond ((>= pos (length text)) (return pos))
          ((member (char text pos) '(#\Space #\Newline #\Tab)) (incf pos))
          ((char= (char text pos) #\;) (setf pos (or (position #\Newline text :start pos) (length text))))
          (t (return pos)))))

(defun form-spans (text scratch)
  "A list of (start end form) for the top-level forms of TEXT, read in SCRATCH."
  (let ((*read-eval* nil) (*package* scratch) (pos 0) (spans '()))
    (loop
      (setf pos (skip-blank text pos))
      (when (>= pos (length text)) (return (nreverse spans)))
      (multiple-value-bind (form end) (read-from-string text t nil :start pos :preserve-whitespace t)
        (push (list pos end form) spans)
        (setf pos end)))))

(defun form-name (form)
  "The name a form is known by: the symbol or string after its operator, as text. NIL for a form with none."
  (and (consp form) (consp (cdr form))
       (let ((name (second form)))
         (cond ((symbolp name) (symbol-name name)) ((stringp name) name)))))

(defun printed (source scratch)
  "SOURCE, text of one or more forms, printed by the printer, separated by blank lines."
  (let ((*package* scratch) (*read-eval* nil))
    (with-output-to-string (out)
      (with-input-from-string (in source)
        (loop for first = t then nil
              for form = (read in nil :eof)
              until (eq form :eof)
              do (unless first (format out "~%~%"))
                 (write form :stream out :pretty t :case :downcase :right-margin 120))))))

(defun edit (path &key replace insert-before append header)
  "REPLACE and INSERT-BEFORE are alists of (name . source-text); APPEND and HEADER are text."
  (let* ((scratch (make-package (gensym "SCRATCH") :use '(:cl)))
         (text (file-text path))
         (spans (form-spans text scratch))
         (out (make-string-output-stream))
         (pos 0))
    (when header
      (let ((first-start (first (first spans))))
        (write-string header out)
        (setf pos first-start)))
    (dolist (span spans)
      (destructuring-bind (start end form) span
        (let ((name (form-name form)))
          (write-string text out :start pos :end start)
          (dolist (entry insert-before)
            (when (equal (car entry) name)
              (write-string (printed (cdr entry) scratch) out)
              (format out "~%~%")))
          (let ((r (assoc name replace :test #'equal)))
            (if r
                (write-string (printed (cdr r) scratch) out)
                (write-string text out :start start :end end)))
          (setf pos end))))
    (write-string text out :start pos)
    (when append
      (format out "~%~a~%" (printed append scratch)))
    (let ((new (get-output-stream-string out)))
      (with-open-file (s path :direction :output :if-exists :supersede :external-format :utf-8)
        (write-string new s)))
    (delete-package scratch)
    path))

(defun new-file (path header source)
  "Write a file made of HEADER (comment text) and the forms of SOURCE, printed."
  (let ((scratch (make-package (gensym "SCRATCH") :use '(:cl))))
    (with-open-file (s path :direction :output :if-exists :error :external-format :utf-8)
      (write-string header s)
      (format s "~%~a~%" (printed source scratch)))
    (delete-package scratch)
    path))
