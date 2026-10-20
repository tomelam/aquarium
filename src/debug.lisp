;;;; Debugging in place (docs/debug-in-place.md). An error in a request from the socket does not unwind the stack. The
;;;; request's thread is kept, with its stack, inside Slynk's debugging environment, and later requests work on it by id:
;;;; frames, locals, evaluation in a frame, redefine a function and restart a frame, take a restart. Frames belong to the
;;;; thread that has them, so that thread runs each command itself and sends the answer back through a mailbox.
(in-package :aquarium)

(defparameter *held-limit* 4
  "Sessions in use at once. One more error is handled as an ordinary ERROR: reply.")

(defparameter *held-timeout* 300
  "Seconds a held thread waits for a command before its request is abandoned (the same as bin/eval's own wait).")

(defparameter *finished-kept* 8
  "Finished sessions whose result has not been read are kept up to this many, oldest dropped first.")

(defparameter *frames-shown* 15
  "Frames in the report of a held error.")

(defvar *reply-now* nil
  "While a request from the socket is evaluated: a function of one string that sends it as the reply at once and ends the
   connection. NIL otherwise (a direct call of EVAL-REQUEST): then an error is never held.")

(defvar *session* nil
  "The session of the request being evaluated, once an error in it has been held.")

(defstruct (session (:constructor make-session (id)))
  id
  (state :held)            ; :held (waiting for a command), :running (resumed), :finished
  condition                ; the error that was last held
  restarts                 ; its restarts, ABORT-REQUEST first
  (report "")              ; the text of the last held report
  (output "")              ; what the request printed up to the last report
  result                   ; the whole text of the request, once :finished
  (inbox (sb-concurrency:make-mailbox))
  (outbox (sb-concurrency:make-mailbox)))

(defvar *sessions* (make-hash-table))
(defvar *sessions-lock* (sb-thread:make-mutex :name "debug sessions"))
(defvar *session-counter* 0)

(defun find-session (id)
  (sb-thread:with-mutex (*sessions-lock*) (gethash id *sessions*)))

(defun open-session ()
  "A new session, or NIL when *HELD-LIMIT* are in use. Finished sessions beyond *FINISHED-KEPT* are dropped."
  (sb-thread:with-mutex (*sessions-lock*)
    (let ((in-use 0) (finished '()))
      (maphash (lambda (id session)
                 (if (eq (session-state session) :finished) (push id finished) (incf in-use)))
               *sessions*)
      (loop for id in (nthcdr *finished-kept* (sort finished #'>)) do (remhash id *sessions*))
      (when (< in-use *held-limit*)
        (let ((session (make-session (incf *session-counter*))))
          (setf (gethash (session-id session) *sessions*) session))))))

(defun forget-session (session)
  (sb-thread:with-mutex (*sessions-lock*) (remhash (session-id session) *sessions*)))

(defun frame-lines (end)
  "The frames 0 up to END of the error being debugged, as (number . text), the text cut to 200 characters."
  (let ((*print-length* 10) (*print-level* 4) (*print-pretty* nil))
    (loop for frame in (slynk-backend:compute-backtrace 0 end)
          for number from 0
          collect (cons number
                        (let ((text (with-output-to-string (stream) (slynk-backend:print-frame frame stream))))
                          (if (> (length text) 200) (concatenate 'string (subseq text 0 200) "...") text))))))

(defun held-report (session condition new-output)
  "The text of a held error: what the request printed since the last report, the error, the restarts and the frames."
  (with-output-to-string (report)
    (write-string new-output report)
    (format report "ERROR: ~a~%" (condition-text condition))
    (format report "HELD ~d: the thread is waiting and nothing was unwound. After ~d s without a command it is abandoned.~%"
            (session-id session) *held-timeout*)
    (format report "restarts:~%")
    (loop for restart in (session-restarts session) for number from 0
          do (format report "  ~d ~a  ~a~%" number (restart-name restart) (princ-to-string restart)))
    (format report "frames:~%")
    (let ((frames (frame-lines (1+ *frames-shown*))))
      (loop for (number . text) in frames for count from 0 below *frames-shown* do (format report "  ~d ~a~%" number text))
      (when (> (length frames) *frames-shown*)
        (format report "  ... more: (debug-frames ~d ~d)~%" (session-id session) (* 4 *frames-shown*))))))

(defun hold-error (condition reply)
  "The handler of EVAL-REQUEST for an ERROR. When the error can be held it does not return until a command resumes the
   thread (the stack is then used, or left by a restart); otherwise it returns at once and the error is handled as before.
   A first error answers the socket at once; a later error in the same request only changes the report."
  (let ((session (or *session* (and *reply-now* (open-session)))))
    (when session
      (setf *session* session)
      (let* ((all (compute-restarts condition))
             (ours (find 'abort-request all :key #'restart-name))
             (first-time (null (session-condition session))))
        (setf (session-condition session) condition
              (session-restarts session) (if ours (cons ours (remove ours all)) all))
        (slynk-backend:call-with-debugging-environment
         (lambda ()
           (let* ((new-output (get-output-stream-string reply))
                  (report (held-report session condition new-output)))
             (setf (session-output session) (concatenate 'string (session-output session) new-output)
                   (session-report session) report
                   (session-state session) :held)
             (when first-time (funcall *reply-now* report)))
           (loop
             (multiple-value-bind (command found)
                 (sb-concurrency:receive-message (session-inbox session) :timeout *held-timeout*)
               (unless found
                 (format reply "(held session ~d abandoned after ~d s without a command)~%" (session-id session) *held-timeout*)
                 (invoke-restart ours condition))
               ;; A command answers (:reply value), or resumes the thread (:resume thunk): then it says so first, because
               ;; the thunk leaves this loop and never returns here.
               (destructuring-bind (kind . more)
                   (handler-case (funcall command session)
                     (error (e) (list :reply (list :command-failed (condition-text e)))))
                 (ecase kind
                   (:reply (sb-concurrency:send-message (session-outbox session) (first more)))
                   (:resume (setf (session-state session) :running)
                    (sb-concurrency:send-message (session-outbox session) :resuming)
                    (funcall (first more)))))))))))))

(defun finish-session (session text)
  "The request has ended; TEXT is its whole reply, kept for DEBUG-RESULT."
  (setf (session-result session) text
        (session-state session) :finished))

;;; The commands: ordinary functions, called from another request by id.

(defun ask-session (session command &optional (timeout 10))
  (sb-concurrency:send-message (session-inbox session) command)
  (multiple-value-bind (reply found) (sb-concurrency:receive-message (session-outbox session) :timeout timeout)
    (if found reply (list :command-failed (format nil "no answer from held session ~d within ~d s" (session-id session) timeout)))))

(defmacro with-held-session ((session id) &body body)
  "Run BODY with SESSION bound to the session ID if it is waiting for a command; otherwise say so and return no value."
  `(let ((,session (find-session ,id)))
     (cond ((null ,session) (format t ";; no session ~d~%" ,id) (values))
           ((not (eq (session-state ,session) :held))
            (format t ";; session ~d is ~(~a~), not waiting; (debug-result ~d) waits for it~%" ,id (session-state ,session) ,id)
            (values))
           (t ,@body))))

(defun reply-or-complain (reply)
  "The payload of an (:ok ...) reply, or say why not and return no value."
  (if (eq (first reply) :ok)
      (values-list (rest reply))
      (progn (format t ";; ~a~%" (second reply)) (values))))

(defun debug-frames (id &optional (end 30))
  "The frames 0 up to END of held session ID, as (number . text)."
  (with-held-session (session id)
    (reply-or-complain (ask-session session (lambda (session) (declare (ignore session)) (list :reply (list :ok (frame-lines end))))))))

(defun debug-locals (id frame)
  "The local variables of FRAME in held session ID, as (name value). What the compiler kept: see debug 3 in bin/serve.lisp."
  (with-held-session (session id)
    (reply-or-complain
     (ask-session session
                  (lambda (session) (declare (ignore session))
                    (list :reply (list :ok (loop for local in (slynk-backend:frame-locals frame)
                                                 collect (list (getf local :name) (getf local :value))))))))))

(defun debug-eval (id frame form)
  "Evaluate FORM in FRAME of held session ID, so it can use the frame's variables. Returns the values."
  (with-held-session (session id)
    (reply-or-complain
     (ask-session session
                  (lambda (session) (declare (ignore session))
                    (list :reply (cons :ok (multiple-value-list (slynk-backend:eval-in-frame form frame)))))))))

(defun debug-result (id &optional (wait 20))
  "Wait up to WAIT seconds for session ID to stop running; then print its report (held again) or the whole reply of the
   request (finished). The reply of a finished request is read once."
  (let ((session (find-session id)))
    (if (null session)
        (format t ";; no session ~d~%" id)
        (progn
          (loop repeat (ceiling (* wait 20)) while (eq (session-state session) :running) do (sleep 0.05))
          (ecase (session-state session)
            (:running (format t ";; session ~d is still running after ~d s; ask again with (debug-result ~d)~%" id wait id))
            (:held (write-string (session-report session)))
            (:finished (write-string (session-result session)) (forget-session session)))))
    (values)))

(defun resume (id thunk-maker)
  "Tell held session ID to leave the debugger by the function THUNK-MAKER makes (given the session), then wait for what comes."
  (with-held-session (session id)
    (let ((answer (ask-session session (lambda (session) (list :resume (funcall thunk-maker session))))))
      (if (eq answer :resuming)
          (debug-result id)
          (progn (format t ";; ~a~%" (second answer)) (values))))))

(defun debug-restart-frame (id frame)
  "Run FRAME of held session ID again with its original arguments: after the function was redefined, the new one runs."
  (resume id (lambda (session) (declare (ignore session)) (lambda () (slynk-backend:restart-frame frame)))))

(defun debug-invoke (id number &rest arguments)
  "Take restart NUMBER (as numbered in the report) of held session ID, with ARGUMENTS if it takes any."
  (resume id (lambda (session)
               (let ((restart (nth number (session-restarts session)))
                     (condition (session-condition session)))
                 (unless restart (error "session ~d has no restart ~d" (session-id session) number))
                 (lambda ()
                   (if (eq (restart-name restart) 'abort-request)
                       (invoke-restart restart condition)
                       (apply #'invoke-restart restart arguments)))))))

(defun debug-abandon (id)
  "Unwind the request of held session ID, as if it had not been held: its reply ends with the ERROR: line."
  (debug-invoke id 0))
