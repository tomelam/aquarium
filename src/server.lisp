;;;; The always-on image's door for Claude: a request is Lisp text, the reply is what it printed and its values, over a
;;;; Unix socket private to the user. Tom's door is Slynk (src/slynk-server.lisp).
(in-package :aquarium)

(defun read-all (stream)
  (with-output-to-string (text)
    (loop for char = (read-char stream nil) while char do (write-char char text))))

(defun eval-request (request)
  "Evaluate the forms in REQUEST in package AQUARIUM; the reply is what they print followed by one printed line per
   value. An error from the socket is held and answers at once (tools/debug.lisp); any other serious condition becomes a
   line starting ERROR:. Returns the reply and, when an error was held, its session."
  (eval-with-debugging request :aquarium))

(defun serve-connection (connection)
  (let ((stream (sb-bsd-sockets:socket-make-stream connection :input t :output t :element-type 'character
                                                               :external-format :utf-8 :buffering :full)))
    (unwind-protect
         ;; An error here would end the whole process (--disable-debugger), so none may escape: a client that hung up
         ;; before its reply, a request that is not UTF-8. The reply is lost; the server says so in its log.
         (handler-case
             (let ((request (read-all stream))
                   (*reply-now* (reply-now-function stream connection)))
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
