(defpackage :aquarium
  (:use :cl :lisp-ai-debug)
  (:export #:fish #:make-fish #:fish-name #:fish-x #:fish-y #:fish-dx
           #:tank #:make-tank #:tank-width #:tank-height #:tank-fish #:tank-tick
           #:*tank* #:fish-glyph #:step-fish #:tick #:add-fish #:draw #:write-frame
           #:start-aquarium #:stop-aquarium #:start-slynk #:stop-slynk #:start-server #:stop-server))
