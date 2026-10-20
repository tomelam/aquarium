;;;; Debugging in place (docs/debug-in-place.md), through a real Unix socket as bin/eval uses it: a held error answers at
;;;; once, the commands reach the waiting thread, a redefinition is picked up by a restarted frame, the limits hold.
(in-package :aquarium/tests)

(defun socket-request (path text)
  "Send TEXT to the server at PATH as bin/eval does (the write side closed after it) and return the whole reply."
  (let ((socket (make-instance 'sb-bsd-sockets:local-socket :type :stream)))
    (unwind-protect
         (progn
          (sb-bsd-sockets:socket-connect socket path)
          (let ((stream (sb-bsd-sockets:socket-make-stream socket :input t :output t :element-type 'character
                                                                  :external-format :utf-8 :buffering :full)))
            (write-string text stream)
            (finish-output stream)
            (sb-bsd-sockets:socket-shutdown socket :direction :output)
            (with-output-to-string (reply)
              (loop for char = (read-char stream nil) while char do (write-char char reply)))))
      (sb-bsd-sockets:socket-close socket))))

(defun held-id (reply)
  "The number in the line HELD n of a REPLY, or NIL when there is none."
  (let ((start (search "HELD " reply)))
    (and start (parse-integer reply :start (+ start 5) :junk-allowed t))))

(defmacro printed (&body body)
  "What BODY prints."
  `(with-output-to-string (*standard-output*) ,@body))

(defun frame-number (id name)
  "The number of the first frame of held session ID whose text mentions NAME."
  (car (find-if (lambda (frame) (search name (cdr frame))) (aquarium::debug-frames id 30))))

;;; Functions that fail. Each calls the failing function inside a LIST, so its frame is not replaced by a tail call.
(defun debug-broken (x) (let ((y (* x 2))) (list :broken (/ 100 (- y 4)))))
(defun debug-outer (x) (list :outer (debug-broken x)))
(defun debug-careful (x) (list :careful (restart-case (/ 1 x) (use-value (v) v))))
(defvar *still-broken* t)
(defun debug-flaky (x) (list :flaky (if *still-broken* (error "still broken") x)))

(defun run-debug-tests ()
  (let* ((path (namestring (asdf:system-relative-pathname :aquarium "run/test-debug.sock")))
         (server (aquarium:start-server path))
         (timeout aquarium::*held-timeout*))
    (unwind-protect
         (progn
          (check-equal "a request that succeeds is answered as before" (socket-request path "(+ 1 2)") (format nil "3~%"))
          ;; an error is held: the reply is at once, and the thread waits
          (let* ((reply (socket-request path "(progn (format t \"before~%\") (aquarium/tests::debug-outer 2))"))
                 (id (held-id reply)))
            (check "a held error answers at once, with what was printed first, then the error"
                   (eql 0 (search (format nil "before~%ERROR: arithmetic error DIVISION-BY-ZERO") reply)))
            (check "the reply names the session, the restarts and the frames"
                   (and id (search "restarts:" reply) (search "0 ABORT-REQUEST" reply) (search "frames:" reply)
                        (search "DEBUG-BROKEN" reply)))
            (when id
              (let ((frame (frame-number id "DEBUG-BROKEN")))
                (check-equal "the locals of the failing function's frame"
                             (mapcar (lambda (local) (list (symbol-name (first local)) (second local)))
                                     (aquarium::debug-locals id frame))
                             '(("X" 2) ("Y" 4)))
                (check-equal "a form evaluated in that frame sees its variables"
                             (multiple-value-list (aquarium::debug-eval id frame '(list x (* x 100))))
                             '((2 200)))
                ;; fix the definition in the image, then run the frame again
                (setf (fdefinition 'debug-broken) (lambda (x) (let ((y (* x 2))) (list :broken (/ 100 (- y 5))))))
                (check-equal "after the fix, restarting the frame finishes the original request with the new answer"
                             (printed (aquarium::debug-restart-frame id frame))
                             (format nil "before~%(:OUTER (:BROKEN -100))~%"))
                (check "and the session is gone once its result was read" (null (aquarium::find-session id))))))
          ;; a restart the code establishes, taken with an argument
          (let* ((reply (socket-request path "(aquarium/tests::debug-careful 0)"))
                 (id (held-id reply)))
            (check "the code's own restart is listed" (search "1 USE-VALUE" reply))
            (when id
              (check-equal "taking it with a value finishes the request with that value"
                           (printed (aquarium::debug-invoke id 1 42)) (format nil "(:CAREFUL 42)~%"))))
          ;; an error that comes back after the restart is held again, under the same id
          (let* ((reply (socket-request path "(aquarium/tests::debug-flaky 7)"))
                 (id (held-id reply)))
            (when id
              (let ((frame (frame-number id "DEBUG-FLAKY")))
                (check "restarting without a fix holds the new error under the same id"
                       (eql id (held-id (printed (aquarium::debug-restart-frame id frame)))))
                (setf *still-broken* nil)
                (check-equal "and once fixed the request finishes"
                             (printed (aquarium::debug-restart-frame id frame)) (format nil "(:FLAKY 7)~%")))))
          ;; abandoning unwinds as before
          (let* ((reply (socket-request path "(error \"boom\")"))
                 (id (held-id reply)))
            (when id
              (check-equal "abandoning ends the request with the ERROR: line" (printed (aquarium::debug-abandon id))
                           (format nil "ERROR: boom~%"))))
          ;; the limit: the fifth error is not held
          (let* ((replies (loop repeat (1+ aquarium::*held-limit*) collect (socket-request path "(error \"x\")")))
                 (ids (remove nil (mapcar #'held-id replies))))
            (check-equal "up to the limit errors are held" (length ids) aquarium::*held-limit*)
            (check-equal "one more is an ordinary ERROR: reply" (car (last replies)) (format nil "ERROR: x~%"))
            (dolist (id ids) (printed (aquarium::debug-abandon id)))
            (check-equal "all sessions end" (hash-table-count aquarium::*sessions*) 0))
          ;; a thread nobody answers is abandoned after the timeout
          (setf aquarium::*held-timeout* 1)
          (let* ((reply (socket-request path "(error \"slow\")"))
                 (id (held-id reply)))
            (sleep 2)
            (when id
              (let ((text (printed (aquarium::debug-result id 3))))
                (check "an unanswered thread is abandoned, and says so" (search "abandoned after 1 s" text))
                (check "and its reply ends with the error" (search "ERROR: slow" text)))))
          (check-equal "a session that does not exist is said so" (printed (aquarium::debug-frames 99999))
                       (format nil ";; no session 99999~%")))
      (setf aquarium::*held-timeout* timeout)
      (aquarium:stop-server server)
      (when (probe-file path) (delete-file path)))))
