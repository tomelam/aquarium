(defsystem "aquarium"
  :description "A tank of fish drawn as text, to be changed while it runs."
  :depends-on ("sb-posix" "sb-bsd-sockets" "slynk")
  :serial t
  :components ((:module "src" :components ((:file "package") (:file "aquarium") (:file "server") (:file "slynk-server")))))

(defsystem "aquarium/form-edit" :description
 "Changing a Lisp file as forms: the Eclector reader gives the span of every subform." :depends-on ("eclector"))

(defsystem "aquarium/tests"
  :depends-on ("aquarium" "aquarium/form-edit" "uiop")
  :serial t
  :components ((:module "tests" :components ((:file "harness") (:file "aquarium-test") (:file "shared-test"))))
  :perform (test-op (o c) (symbol-call :aquarium/tests :run)))
