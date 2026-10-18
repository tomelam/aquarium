(defsystem "aquarium"
  :description "A tank of fish drawn as text, to be changed while it runs."
  :depends-on ("sb-posix" "sb-bsd-sockets" "slynk")
  :serial t
  :components ((:module "src" :components ((:file "package") (:file "aquarium") (:file "server") (:file "slynk-server")))))

(defsystem "aquarium/tests"
  :depends-on ("aquarium" "uiop")
  :serial t
  :components ((:module "tests" :components ((:file "harness") (:file "aquarium-test"))))
  :perform (test-op (o c) (symbol-call :aquarium/tests :run)))
