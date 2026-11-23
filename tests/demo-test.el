;;; -*- lexical-binding: t -*-
;; A check of demo.el, run by hand with the image up:  /opt/homebrew/bin/Emacs --batch -Q -l tests/demo-test.el
;; Prints one line per check, then how many failed, and exits 1 when any did (0 when none did). Needs the image running
;; (bin/lisp start): it connects to it for real. It tests the demo.el beside it, the tools commit that project pins
;; (lisp-ai.el, lisp-ai-demo.el, and the shared checks of lisp-ai-emacs-test.el) and that project's image, so a clone
;; tests itself. Playing the demo rewrites src/aquarium.lisp and forgets the image's ledger, and the reconnect restarts the
;; image, so those parts run only in a clone (any directory but ~/lisp-ai/aquarium/), and say SKIP there.
;; paredit-mode in REPLs, added to the hook before demo.el is loaded, as ~/.emacs.d/init.el has it
(add-to-list 'load-path (expand-file-name "~/.emacs.d/elpa/paredit-26"))
(require 'paredit)
(add-hook 'sly-mrepl-mode-hook #'paredit-mode)
(defconst demo-test-root (file-name-directory (directory-file-name (file-name-directory load-file-name))))
(load-file (expand-file-name "demo.el" demo-test-root))
(load (expand-file-name "lisp-ai-emacs-test.el" lisp-ai-directory) nil t)

(lisp-ai-test-report "the demo is configured for the project beside this test"
                     (string= (plist-get lisp-ai-demo--layout :root) demo-test-root))
(lisp-ai-test-project demo-test-root)
(lisp-ai-test-watch)

;; the screen: set it up twice, as a user who runs the command again would
(set-frame-size (selected-frame) 100 40)
(lisp-ai-demo-configure demo-test-root :source "src/aquarium.lisp" :above-repl "run/tank.txt" :above-repl-lines 8
                        :caption-lines 8)
(setq lisp-ai-demo-start-on-setup nil)
(lisp-ai-demo)
(lisp-ai-test-report "Sly connects to the image" (lisp-ai-test-wait-until #'sly-current-connection))
(lisp-ai-test-report "and the REPL buffer exists" (lisp-ai-test-wait-until (lambda () (get-buffer "*sly-mrepl for sbcl*"))))
(lisp-ai-test-wait-until (lambda () nil) 3)
(lisp-ai-demo)
(lisp-ai-test-wait-until (lambda () (get-buffer "*sly-mrepl for sbcl*")))
(lisp-ai-test-wait-until (lambda () nil) 3)
(let* ((windows (window-list nil 'never))
       (names (mapcar (lambda (w) (buffer-name (window-buffer w))) windows)))
  (princ (format "windows: %S\n" names))
  (lisp-ai-test-report "four windows" (= (length windows) 4))
  (lisp-ai-test-report "the source is shown once" (= 1 (cl-count "aquarium.lisp" names :test #'string=)))
  (lisp-ai-test-report "the captions are shown once" (= 1 (cl-count lisp-ai-demo-caption-buffer names :test #'string=)))
  (lisp-ai-test-report "and they have the keyboard, so SPACE goes on"
                       (lisp-ai-test-wait-until
                        (lambda () (equal (buffer-name (window-buffer (selected-window))) lisp-ai-demo-caption-buffer)) 5))
  (lisp-ai-test-report "the tank is shown once, not twice" (= 1 (cl-count "tank.txt" names :test #'string=)))
  (lisp-ai-test-report "the REPL is shown once" (= 1 (cl-count "*sly-mrepl for sbcl*" names :test #'string=)))
  (lisp-ai-test-report "and it is the window the demo made for it"
                       (and (window-live-p lisp-ai--repl-window)
                            (equal (buffer-name (window-buffer lisp-ai--repl-window)) "*sly-mrepl for sbcl*"))))
(lisp-ai-test-report "the tank buffer is not flashed"
                     (not (memq 'lisp-ai--flash (buffer-local-value 'after-revert-hook (get-buffer "tank.txt")))))
(lisp-ai-test-report "the source buffer is"
                     (memq 'lisp-ai--flash (buffer-local-value 'after-revert-hook (get-buffer "aquarium.lisp"))))
(lisp-ai-test-repl "AQUARIUM")
(lisp-ai-test-report "and it sees the tank: four or more fish"
                     (>= (sly-eval '(cl:length (aquarium:tank-fish aquarium:*tank*))) 4))
(lisp-ai-test-eval demo-test-root)

;; Playing the demo, as SPACE does, against this project's image: only in a clone, since it rewrites src/aquarium.lisp
(defun demo-test-idle () (lisp-ai-test-wait-until (lambda () (not lisp-ai-demo--busy)) 90))
(defun demo-test-text (file) (lisp-ai-test-text demo-test-root file))
(defun demo-test-lisp (request) (lisp-ai-test-lisp demo-test-root request))
(defun demo-test-committed-p ()
  (let ((default-directory demo-test-root))
    (string= "" (shell-command-to-string "git status --porcelain -- src/aquarium.lisp"))))
(defun demo-test-caption () (with-current-buffer lisp-ai-demo-caption-buffer (buffer-string)))
(defun demo-test-step () (lisp-ai-demo-next) (demo-test-idle))

(if (not (lisp-ai-test-in-clone-p demo-test-root "~/lisp-ai/aquarium/"))
    (princ "SKIP: playing the demo, which rewrites src/aquarium.lisp: run this test in a clone\n")
  (lisp-ai-demo-start)
  (demo-test-idle)
  (lisp-ai-test-report "the demo starts from the starting source"
                       (string= (demo-test-text "src/aquarium.lisp") (demo-test-text "demo/aquarium.lisp")))
  (lisp-ai-test-report "and shows its introduction, then step 1"
                       (and (string-match-p "running right now" (demo-test-caption))
                            (string-match-p "step 1 of 8" (demo-test-caption))))
  (demo-test-step)
  (lisp-ai-test-report "step 1: a fifth fish" (string= (demo-test-lisp "(length (tank-fish *tank*))") "5"))
  (unless (lisp-ai-test-report "and the echo shows the request in the REPL, after claude>"
                               (lisp-ai-test-wait-until (lambda () (with-current-buffer "*sly-mrepl for sbcl*"
                                                                     (string-match-p "claude>.*add-fish" (buffer-string))))
                                                        5))
    (princ (format "REPL buffer then:\n%s\nThe image's connections, and where the echo writes: %s\n"
                   (with-current-buffer "*sly-mrepl for sbcl*" (buffer-string))
                   (demo-test-lisp "(list (length slynk::*connections*) (mapcar (lambda (c) (list c (slynk::default-listener c) (ignore-errors (mapcar (function type-of) (slynk::connection-channels c))))) slynk::*connections*) (multiple-value-list (lisp-ai-echo::repl-target)))"))))
  (demo-test-step)
  (lisp-ai-test-report "step 2: the image draws big fish"
                       (string= (demo-test-lisp "(fish-glyph (make-fish :dx 1))") "\"><(((*>\""))
  (lisp-ai-test-report "and the file still has the small ones" (string-match-p "\"><>\"" (demo-test-text "src/aquarium.lisp")))
  (demo-test-step)
  (lisp-ai-test-report "step 3: the file has the big fish" (string-match-p "><(((\\*>" (demo-test-text "src/aquarium.lisp")))
  (demo-test-step)
  (demo-test-step)
  (lisp-ai-test-report "step 5: the file is again exactly as committed" (demo-test-committed-p))
  (demo-test-step)
  (lisp-ai-test-report "step 6: the tank shows the failed frame"
                       (lisp-ai-test-wait-until (lambda () (string-match-p "FRAME FAILED" (demo-test-text "run/tank.txt"))) 5))
  (demo-test-step)
  (lisp-ai-test-report "step 7: the fish are back"
                       (lisp-ai-test-wait-until
                        (lambda () (not (string-match-p "FRAME FAILED" (demo-test-text "run/tank.txt")))) 5))
  (lisp-ai-test-report "and nothing is left unsaved" (string= (demo-test-lisp "(pending)") "NIL"))
  (demo-test-step)
  (lisp-ai-test-report "step 8 ends the demo"
                       (and (null lisp-ai-demo--next) (string-match-p "whole demo" (demo-test-caption))))
  (lisp-ai-test-report "the file is as committed after a whole run" (demo-test-committed-p))
  (lisp-ai-test-report "the image holds nothing loose" (string= (demo-test-lisp "(loose-definitions)") "NIL"))
  ;; stopped half way
  (lisp-ai-demo-next)                   ; after the end, SPACE starts again
  (demo-test-idle)
  (demo-test-step)
  (demo-test-step)
  (lisp-ai-test-report "half way: the image is ahead of a starting file" (not (demo-test-committed-p)))
  (lisp-ai-demo-quit)
  (demo-test-idle)
  (lisp-ai-test-report "q puts the file back as committed" (demo-test-committed-p))
  (lisp-ai-test-report "and the image too: big fish, as the committed file draws them"
                       (string= (demo-test-lisp "(fish-glyph (make-fish :dx 1))") "\"><(((*>\""))
  (lisp-ai-test-report "with nothing unsaved and the first four fish"
                       (and (string= (demo-test-lisp "(pending)") "NIL")
                            (string= (demo-test-lisp "(length (tank-fish *tank*))") "4")))
  ;; a file with changes not committed is not written over
  (let ((path (expand-file-name "src/aquarium.lisp" demo-test-root)))
    (write-region "\n;; a change not committed\n" nil path t 'silent)
    (lisp-ai-demo-start)
    (demo-test-idle)
    (lisp-ai-test-report "the demo refuses to start over changes not committed"
                         (and (string-match-p "cannot start" (demo-test-caption))
                              (string-match-p "a change not committed" (demo-test-text "src/aquarium.lisp"))))
    (let ((default-directory demo-test-root)) (call-process "git" nil nil nil "restore" "--" "src/aquarium.lisp"))))

;; Restarting the image drops Sly's connection, and lisp-ai-reconnect makes it again: only in a clone
(if (not (lisp-ai-test-in-clone-p demo-test-root "~/lisp-ai/aquarium/"))
    (princ "SKIP: restarting the image and reconnecting: run this test in a clone\n")
  (lisp-ai-test-reconnect demo-test-root "AQUARIUM"))

(lisp-ai-test-finish)
