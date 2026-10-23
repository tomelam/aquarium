;;;; The always-on server answers a Claude Code hook payload with the hook's decision after a marker, and Lisp with its values;
;;;; tools/guard asks it first and trusts only a reply that starts with the marker.
(in-package :aquarium/tests)

(defun ask (path request)
  "Send REQUEST to the server at PATH, close our sending side, and return the whole reply."
  (let ((socket (make-instance 'sb-bsd-sockets:local-socket :type :stream)))
    (sb-bsd-sockets:socket-connect socket path)
    (let ((stream (sb-bsd-sockets:socket-make-stream socket :input t :output t :element-type 'character
                                                            :external-format :utf-8 :buffering :full)))
      (write-string request stream)
      (finish-output stream)
      (sb-bsd-sockets:socket-shutdown socket :direction :output)
      (prog1 (with-output-to-string (reply)
               (loop for line = (read-line stream nil) while line do (write-line line reply)))
        (close stream)))))

(defun hook-json (tool command)
  (format nil "{\"tool_name\":~s,\"tool_input\":{\"command\":~s}}" tool command))

(defun run-server-hook ()
  (let* ((path (format nil "/tmp/aquarium-test-~d.sock" (sb-posix:getpid)))
         (server (aquarium:start-server path)))
    (unwind-protect
         (progn
           (check-equal "a form is evaluated" (ask path "(* 6 7)") (format nil "42~%"))
           (check-equal "an allowed hook payload is answered with the marker alone" (ask path (hook-json "Bash" "git status"))
            (format nil "~a~%" (lisp-ai-hook:socket-marker)))
           (let ((reply (ask path (hook-json "Bash" "cat f"))))
             (check "a refused hook payload starts with the marker" (eql 0 (search (lisp-ai-hook:socket-marker) reply)))
             (check "and carries the deny decision" (search "\"permissionDecision\":\"deny\"" reply)))
           (check "a hook payload is answered, never read as Lisp and held"
                  (not (search "HELD " (ask path (hook-json "Bash" "cat f"))))))
      (aquarium:stop-server server))))
