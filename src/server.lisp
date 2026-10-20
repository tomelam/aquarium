;;;; The always-on image's door for Claude: a request is Lisp text, the reply is what it printed and its values, over a
;;;; Unix socket private to the user. Tom's door is Slynk (src/slynk-server.lisp).
(in-package :aquarium)

(defun read-all (stream)
  (with-output-to-string (text)
    (loop for char = (read-char stream nil) while char do (write-char char text))))

(defun condition-text (condition)
  "CONDITION as text, even if printing it fails."
  (handler-case (princ-to-string condition)
    (serious-condition () (format nil "~s (its message could not be printed)" (type-of condition)))))

(defun eval-request (request)
  "Evaluate the forms in REQUEST in package AQUARIUM; the reply is what they print followed by one printed line per
   value. An error from the socket is held (src/debug.lisp) and answers at once; any other serious condition, an
   exhausted stack included, becomes a line starting ERROR: instead of a dead server. Returns the reply and, when an
   error was held, its session (the reply was then kept for DEBUG-RESULT)."
  (let ((reply (make-string-output-stream)) (*session* nil))
    (handler-case
     (restart-case (handler-bind ((error (lambda (condition) (hold-error condition reply))))
                     (let ((*package* (find-package :aquarium)) (*standard-output* reply) (*error-output* reply))
                       (with-input-from-string (forms request)
                         (loop for form = (read forms nil forms)
                               until (eq form forms)
                               do (dolist (value (multiple-value-list (eval form))) (format reply "~s~%" value))))))
       (abort-request (&optional condition) :report
        "Unwind the request and reply with the error, as without debugging."
        (format reply "ERROR: ~a~%" (condition-text (or condition (session-condition *session*))))))
     (serious-condition (condition) (format reply "ERROR: ~a~%" (condition-text condition))))
    (let ((text
           (concatenate 'string
                        (if *session*
                            (session-output *session*)
                            "")
                        (get-output-stream-string reply))))
      (when *session* (finish-session *session* text))
      (values text *session*))))

(defun serve-connection (connection)
  (let ((stream (sb-bsd-sockets:socket-make-stream connection :input t :output t :element-type 'character
                                                               :external-format :utf-8 :buffering :full)))
    (unwind-protect
         ;; An error here would end the whole process (--disable-debugger), so none may escape: a client that hung up
         ;; before its reply, a request that is not UTF-8. The reply is lost; the server says so in its log.
         (handler-case
             (let ((request (read-all stream))
                   (*reply-now*
                    (lambda (text)
                      (write-string text stream)
                      (finish-output stream)
                      (ignore-errors (close stream))
                      (ignore-errors (sb-bsd-sockets:socket-close connection)))))
               (multiple-value-bind (text held)
                   (eval-request request)
                 (unless held (write-string text stream) (finish-output stream))))
           (serious-condition (condition)
             (format *error-output* "connection dropped: ~a~%" (condition-text condition))))
      (ignore-errors (close stream))
      (ignore-errors (sb-bsd-sockets:socket-close connection)))))

(defstruct server path listener thread)

(defun start-server (path)
  "Listen on the Unix socket at PATH (mode 600), serving each connection in its own thread. Returns the server."
  (when (probe-file path) (delete-file path))
  (let ((listener (make-instance 'sb-bsd-sockets:local-socket :type :stream)))
    (sb-bsd-sockets:socket-bind listener path)
    (sb-posix:chmod path #o600)
    (sb-bsd-sockets:socket-listen listener 16)
    (make-server
     :path path :listener listener
     :thread (sb-thread:make-thread
              (lambda ()
                (handler-case
                    (loop (let ((connection (sb-bsd-sockets:socket-accept listener)))
                            (sb-thread:make-thread (lambda () (serve-connection connection))
                                                   :name "aquarium connection")))
                  (error () nil)))
              :name "aquarium server"))))

(defun stop-server (server)
  (ignore-errors (sb-bsd-sockets:socket-close (server-listener server)))
  (ignore-errors (sb-thread:terminate-thread (server-thread server)))
  (when (probe-file (server-path server)) (delete-file (server-path server))))
