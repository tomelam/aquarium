;;;; Let Sly connect to this image. Where it listens is data (rules/slynk.sexp); there is no secret, by Tom's decision
;;;; for the tree (code-as-data/docs/brief-image.md). Slynk has only TCP, so the interface in the rules is the whole of
;;;; the access control. It checks a secret only if ~/.sly-secret exists, and nothing here creates that file.

(in-package :aquarium)

(defun read-rules (name)
  "The list in rules/NAME.sexp."
  (let ((*read-eval* nil))
    (with-open-file (in (asdf:system-relative-pathname :aquarium (format nil "rules/~a.sexp" name)))
      (read in))))

(defun start-slynk (&key interface port)
  "Open a Slynk server where rules/slynk.sexp says, INTERFACE and PORT overriding it (PORT 0 takes any free port).
   Several REPLs may connect. Returns the port. Whatever address is named is reachable from that network."
  (let* ((rules (read-rules "slynk"))
         (interface (or interface (getf rules :interface)))
         (port (or port (getf rules :port))))
    (unless (and (stringp interface) (integerp port))
      (error "rules/slynk.sexp must give :interface (a string) and :port (an integer); got ~s" rules))
    (slynk:create-server :interface interface :port port :dont-close t :style :spawn)))

(defun stop-slynk (port)
  "Close the Slynk server listening on PORT."
  (slynk:stop-server port))
