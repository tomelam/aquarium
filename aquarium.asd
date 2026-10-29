;;; Every build of this project keeps the debugging information SBCL can keep (docs/debug-in-place.md): a function whose last
;;; act is the failing call keeps its frame, and let variables can be read in the debugger. RESTRICT-COMPILER-POLICY is
;;; global, for all threads, and survives LOAD, so a request or a Sly session compiles the same way. ASDF does not see a
;;; policy change: after adding this line, delete the project's compiled files once.
(sb-ext:restrict-compiler-policy 'debug 3)

;;; The tools every project shares (the systems lisp-ai-tools, lisp-ai-tools/debug, ...) are a git repo that the qlfile names:
;;; Qlot installs it, and the libraries it needs, where ASDF finds them. Nothing here says where a directory is.
(defsystem "aquarium"
  :description "A tank of fish drawn as text, to be changed while it runs."
  :depends-on ("sb-posix" "sb-bsd-sockets" "slynk" "uiop" "lisp-ai-tools" "lisp-ai-tools/debug" "lisp-ai-tools/bench"
               "lisp-ai-tools/guard" "lisp-ai-tools/kit")
  :serial t
  :components ((:module "src" :components ((:file "package") (:file "aquarium") (:file "demo") (:file "server") (:file "slynk-server")))))

(defsystem "aquarium/tests"
  :depends-on ("aquarium" "lisp-ai-tools/tests" "uiop")
  :serial t
  :components ((:module "tests" :components ((:file "harness") (:file "aquarium-test") (:file "reset-test") (:file "server-test") (:file "shared-test"))))
  :perform (test-op (o c) (symbol-call :aquarium/tests :run)))
