;;; demo.el --- watch the aquarium change  -*- lexical-binding: t; -*-

;; In a freshly started Emacs:  M-x load-file RET ~/lisp-ai/aquarium/demo.el RET   and then   M-x lisp-ai-demo
;; (bin/demo does both). It sets up the screen: the source on the left above the captions; on the right the tank above a
;; Sly REPL connected to the running image. SPACE in the caption window goes through the steps of demo/steps.sexp; q ends
;; the demo. When the source file changes on disk, Emacs redraws it within half a second and flashes the part that
;; changed. After the image is restarted, M-x lisp-ai-reconnect connects the REPL again.
;; Nothing here touches ~/.emacs.d/init.el, and none of it outlasts the Emacs session.
;;
;; The code is the Emacs half of lisp-ai-tools (lisp-ai.el, lisp-ai-demo.el), taken from the commit this project's
;; qlfile.lock pins; this file finds it and gives the layout. The Sly is the one the project's Qlot install pins.

(let* ((root (file-name-directory (or load-file-name buffer-file-name)))
       (dist (expand-file-name ".qlot/dists/lisp-ai-tools/" root))
       ;; a Qlot update leaves the old releases in software/: distinfo.txt names the current one
       (commit (with-temp-buffer
                 (insert-file-contents (expand-file-name "distinfo.txt" dist))
                 (if (re-search-forward "^version: git-\\([0-9a-f]+\\)$" nil t)
                     (match-string 1)
                   (error "%sdistinfo.txt names no commit: run qlot install in the project" dist))))
       (tools (expand-file-name (format "software/lisp-ai-tools-ref-%s/" commit) dist)))
  (load (expand-file-name "lisp-ai.el" tools) nil t)
  (load (expand-file-name "lisp-ai-demo.el" tools) nil t)
  (lisp-ai-load-sly root)
  (lisp-ai-demo-configure root :source "src/aquarium.lisp" :above-repl "run/tank.txt" :above-repl-lines 14
                          :caption-lines 13))

;;; demo.el ends here
