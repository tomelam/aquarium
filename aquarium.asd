;;; The tools every project shares are the system lisp-ai-tools, in ../tools/: ASDF is told where, so any load of this file finds it.
(pushnew
 (uiop/pathname:subpathname
  (uiop/pathname:pathname-parent-directory-pathname (uiop/pathname:pathname-directory-pathname *load-truename*))
  "tools/")
 asdf/system-registry:*central-registry* :test #'equal)

;;; Every build of this project keeps the debugging information SBCL can keep (docs/debug-in-place.md): a function whose last
;;; act is the failing call keeps its frame, and let variables can be read in the debugger. RESTRICT-COMPILER-POLICY is
;;; global, for all threads, and survives LOAD, so a request or a Sly session compiles the same way. ASDF does not see a
;;; policy change: after adding this line, delete the project's compiled files once.
(sb-ext:restrict-compiler-policy 'debug 3)

(defsystem "aquarium"
  :description "A tank of fish drawn as text, to be changed while it runs."
  :depends-on ("sb-posix" "sb-bsd-sockets" "lisp-ai-tools/debug" "slynk" "uiop")
  :serial t
  :components ((:module "src" :components ((:file "package") (:file "aquarium") (:file "demo") (:file "server") (:file "slynk-server")))))

(defsystem "aquarium/form-edit" :description
 "What the editor needs: Qlot installs Eclector because a system of this project names it, and lisp-ai-tools is the editor."
 :depends-on ("eclector" "lisp-ai-tools"))

(defsystem "aquarium/profile" :description
 "What the profile needs: Qlot installs the JSON library because a system of this project names it, and lisp-ai-tools/profile logs the calls."
 :depends-on ("com.inuoe.jzon" "lisp-ai-tools/profile"))

(defsystem "aquarium/tests"
  :depends-on ("aquarium" "aquarium/form-edit" "aquarium/profile" "uiop")
  :serial t
  :components ((:module "tests" :components ((:file "harness") (:file "aquarium-test") (:file "reset-test") (:file "shared-test"))))
  :perform (test-op (o c) (symbol-call :aquarium/tests :run)))
