;;; The tools every project shares are the system lisp-ai-tools, in ../tools/: ASDF is told where, so any load of this file finds it.
(pushnew
 (uiop/pathname:subpathname
  (uiop/pathname:pathname-parent-directory-pathname (uiop/pathname:pathname-directory-pathname *load-truename*))
  "tools/")
 asdf/system-registry:*central-registry* :test #'equal)

(defsystem "aquarium"
  :description "A tank of fish drawn as text, to be changed while it runs."
  :depends-on ("sb-posix" "sb-bsd-sockets" "slynk")
  :serial t
  :components ((:module "src" :components ((:file "package") (:file "aquarium") (:file "server") (:file "slynk-server")))))

(defsystem "aquarium/form-edit" :description
 "What the editor needs: Qlot installs Eclector because a system of this project names it, and lisp-ai-tools is the editor."
 :depends-on ("eclector" "lisp-ai-tools"))

(defsystem "aquarium/tests"
  :depends-on ("aquarium" "aquarium/form-edit" "uiop")
  :serial t
  :components ((:module "tests" :components ((:file "harness") (:file "aquarium-test") (:file "shared-test"))))
  :perform (test-op (o c) (symbol-call :aquarium/tests :run)))
