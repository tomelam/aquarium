;;; -*- lexical-binding: t -*-
;; A check of demo.el, run by hand with the image up:  /opt/homebrew/bin/Emacs --batch -Q -l tests/demo-test.el
;; Prints one line per check. Needs the image running (bin/lisp start): it connects to it for real. It tests the demo.el
;; beside it and that project's image, so a clone tests itself. Playing the demo rewrites src/aquarium.lisp and forgets
;; the image's ledger, so that part runs only in a clone (any directory but ~/lisp-ai/aquarium/), and says SKIP there.
;; paredit-mode in REPLs, added to the hook before demo.el is loaded, as ~/.emacs.d/init.el has it
(add-to-list 'load-path (expand-file-name "~/.emacs.d/elpa/paredit-26"))
(require 'paredit)
(add-hook 'sly-mrepl-mode-hook #'paredit-mode)
(defconst demo-test-root (file-name-directory (directory-file-name (file-name-directory load-file-name))))
(load-file (expand-file-name "demo.el" demo-test-root))
(defun report (label ok) (princ (format "%s: %s\n" (if ok "PASS" "FAIL") label)))
(defun wait-until (test &optional seconds)
  "Run TEST every tenth of a second, up to SECONDS (15 if nil); its last value."
  (let ((tries 0) (limit (* 10 (or seconds 15))))
    (while (and (< tries limit) (not (funcall test))) (accept-process-output nil 0.1) (setq tries (1+ tries))))
  (funcall test))

(report "the Sly in use is the checkout's, not ELPA's"
        (string-prefix-p (aquarium-demo--sly-directory) (symbol-file 'sly-connect 'defun)))
(report "the demo.el loaded is the one beside this test" (string= aquarium-demo-root demo-test-root))
(report "the port comes from rules/slynk.sexp"
        (with-temp-buffer
          (insert-file-contents (expand-file-name "rules/slynk.sexp" demo-test-root))
          (and (re-search-forward ":port \\([0-9]+\\)" nil t)
               (eql (aquarium-demo-port) (string-to-number (match-string 1))))))
(report "no change, no region" (null (aquarium-demo--changed-region "abc" "abc")))
(report "a middle change is found" (equal (aquarium-demo--changed-region "hello world" "hello brave world") '(7 . 13)))
(report "a deletion is one character" (equal (aquarium-demo--changed-region "abcdef" "abdef") '(3 . 4)))
(report "an addition at the end" (equal (aquarium-demo--changed-region "abc" "abcdef") '(4 . 7)))

;; the real hooks: visit a file, change it behind Emacs's back, revert, see what was flashed
(let* ((file (make-temp-file "aquarium-demo" nil ".lisp" "(defun f ()\n  1)\n(defun g ()\n  2)\n"))
       (buffer (aquarium-demo--watch file t))
       (flashed nil))
  (unwind-protect
      (progn
        (write-region "(defun f ()\n  1)\n(defun g ()\n  99)\n" nil file nil 'silent)
        (cl-letf (((symbol-function 'pulse-momentary-highlight-region)
                   (lambda (start end &rest _) (setq flashed (cons start end)))))
          (with-current-buffer buffer (revert-buffer t t t)))
        (with-current-buffer buffer
          (report "the buffer shows the new text" (string= (buffer-string) "(defun f ()\n  1)\n(defun g ()\n  99)\n"))
          (report "and the flash covers exactly what changed"
                  (and flashed (string= (buffer-substring (car flashed) (cdr flashed)) "99"))))
        (report "auto-revert-mode is on in the watched buffer" (buffer-local-value 'auto-revert-mode buffer))
        (report "and it polls" (null (buffer-local-value 'auto-revert-use-notify buffer))))
    (kill-buffer buffer)
    (delete-file file)))

;; the screen: set it up twice, as a user who runs the command again would
(set-frame-size (selected-frame) 100 40)
(setq aquarium-demo-tank-lines 8
      aquarium-demo-caption-lines 8
      aquarium-demo-start-on-setup nil)
(aquarium-demo)
(report "Sly connects to the image" (wait-until #'sly-current-connection))
(report "and the REPL buffer exists" (wait-until (lambda () (get-buffer "*sly-mrepl for sbcl*"))))
(wait-until (lambda () nil) 3)
(aquarium-demo)
(wait-until (lambda () (get-buffer "*sly-mrepl for sbcl*")))
(wait-until (lambda () nil) 3)
(let* ((windows (window-list nil 'never))
       (names (mapcar (lambda (w) (buffer-name (window-buffer w))) windows)))
  (princ (format "windows: %S\n" names))
  (report "four windows" (= (length windows) 4))
  (report "the source is shown once" (= 1 (cl-count "aquarium.lisp" names :test #'string=)))
  (report "the captions are shown once" (= 1 (cl-count "*aquarium demo*" names :test #'string=)))
  (report "and they have the keyboard, so SPACE goes on"
          (wait-until (lambda () (equal (buffer-name (window-buffer (selected-window))) "*aquarium demo*")) 5))
  (report "the tank is shown once, not twice" (= 1 (cl-count "tank.txt" names :test #'string=)))
  (report "the REPL is shown once" (= 1 (cl-count "*sly-mrepl for sbcl*" names :test #'string=)))
  (report "and it is the window the demo made for it"
          (and (window-live-p aquarium-demo--repl-window)
               (equal (buffer-name (window-buffer aquarium-demo--repl-window)) "*sly-mrepl for sbcl*"))))
(report "the tank buffer is not flashed" (not (memq 'aquarium-demo--flash (buffer-local-value 'after-revert-hook (get-buffer "tank.txt")))))
(report "the source buffer is" (memq 'aquarium-demo--flash (buffer-local-value 'after-revert-hook (get-buffer "aquarium.lisp"))))
(report "running the command twice leaves one connection" (= 1 (length sly-net-processes)))
(with-current-buffer "*sly-mrepl for sbcl*"
  (let ((text (buffer-substring-no-properties (point-min) (point-max))))
    (princ (format "REPL buffer:\n%s\n" text))
    (report "the REPL does not claim a debugger" (not (string-match-p "Debugger entered" text)))
    (report "and its prompt is AQUARIUM>" (string-match-p "AQUARIUM> *\\'" text))))
;; typing at the prompt and pressing the RET key, with paredit-mode on: paredit-RET used to swallow it
(with-current-buffer "*sly-mrepl for sbcl*"
  (report "paredit-mode is on in the REPL, as in init.el" (bound-and-true-p paredit-mode))
  (report "and RET still belongs to Sly" (eq (key-binding (kbd "RET")) 'sly-mrepl-return))
  (goto-char (point-max))
  (insert "(+ 40 2)")
  (call-interactively (key-binding (kbd "RET")))
  (report "an expression typed at the prompt is evaluated"
          (wait-until (lambda () (string-match-p "^42 " (buffer-substring-no-properties (point-min) (point-max)))) 8)))
(report "the image answers: its package is AQUARIUM" (equal (sly-eval '(cl:package-name cl:*package*)) "AQUARIUM"))
(report "and it sees the tank: four or more fish" (>= (sly-eval '(cl:length (aquarium:tank-fish aquarium:*tank*))) 4))

;; Playing the demo, as SPACE does, against this project's image: only in a clone, since it rewrites src/aquarium.lisp
(defun demo-test-idle () (wait-until (lambda () (not aquarium-demo--busy)) 90))
(defun demo-test-text (file) (with-temp-buffer (insert-file-contents (expand-file-name file demo-test-root)) (buffer-string)))
(defun demo-test-lisp (request) (string-trim (cdr (aquarium-demo--lisp-now request))))
(defun demo-test-committed-p ()
  (let ((default-directory demo-test-root))
    (string= "" (shell-command-to-string "git status --porcelain -- src/aquarium.lisp"))))
(defun demo-test-caption () (with-current-buffer "*aquarium demo*" (buffer-string)))
(defun demo-test-step () (aquarium-demo-next) (demo-test-idle))

(if (string= (file-truename demo-test-root) (file-truename "~/lisp-ai/aquarium/"))
    (princ "SKIP: playing the demo, which rewrites src/aquarium.lisp: run this test in a clone\n")
  (aquarium-demo-start)
  (demo-test-idle)
  (report "the demo starts from the starting source"
          (string= (demo-test-text "src/aquarium.lisp") (demo-test-text "demo/aquarium.lisp")))
  (report "and shows its introduction, then step 1" (and (string-match-p "running right now" (demo-test-caption))
                                                         (string-match-p "step 1 of 8" (demo-test-caption))))
  (demo-test-step)
  (report "step 1: a fifth fish" (string= (demo-test-lisp "(length (tank-fish *tank*))") "5"))
  (report "and the echo shows the request in the REPL, after claude>"
          (wait-until (lambda () (with-current-buffer "*sly-mrepl for sbcl*"
                                   (string-match-p "claude>.*add-fish" (buffer-string)))) 5))
  (demo-test-step)
  (report "step 2: the image draws big fish" (string= (demo-test-lisp "(fish-glyph (make-fish :dx 1))") "\"><(((*>\""))
  (report "and the file still has the small ones" (string-match-p "\"><>\"" (demo-test-text "src/aquarium.lisp")))
  (demo-test-step)
  (report "step 3: the file has the big fish" (string-match-p "><(((\\*>" (demo-test-text "src/aquarium.lisp")))
  (demo-test-step)
  (demo-test-step)
  (report "step 5: the file is again exactly as committed" (demo-test-committed-p))
  (demo-test-step)
  (report "step 6: the tank shows the failed frame"
          (wait-until (lambda () (string-match-p "FRAME FAILED" (demo-test-text "run/tank.txt"))) 5))
  (demo-test-step)
  (report "step 7: the fish are back"
          (wait-until (lambda () (not (string-match-p "FRAME FAILED" (demo-test-text "run/tank.txt")))) 5))
  (report "and nothing is left unsaved" (string= (demo-test-lisp "(pending)") "NIL"))
  (demo-test-step)
  (report "step 8 ends the demo" (and (null aquarium-demo--next) (string-match-p "whole demo" (demo-test-caption))))
  (report "the file is as committed after a whole run" (demo-test-committed-p))
  (report "the image holds nothing loose" (string= (demo-test-lisp "(loose-definitions)") "NIL"))
  ;; stopped half way
  (aquarium-demo-next)                  ; after the end, SPACE starts again
  (demo-test-idle)
  (demo-test-step)
  (demo-test-step)
  (report "half way: the image is ahead of a starting file" (not (demo-test-committed-p)))
  (aquarium-demo-quit)
  (demo-test-idle)
  (report "q puts the file back as committed" (demo-test-committed-p))
  (report "and the image too: big fish, as the committed file draws them"
          (string= (demo-test-lisp "(fish-glyph (make-fish :dx 1))") "\"><(((*>\""))
  (report "with nothing unsaved and the first four fish"
          (and (string= (demo-test-lisp "(pending)") "NIL") (string= (demo-test-lisp "(length (tank-fish *tank*))") "4")))
  ;; a file with changes not committed is not written over
  (let ((path (expand-file-name "src/aquarium.lisp" demo-test-root)))
    (write-region "\n;; a change not committed\n" nil path t 'silent)
    (aquarium-demo-start)
    (demo-test-idle)
    (report "the demo refuses to start over changes not committed"
            (and (string-match-p "cannot start" (demo-test-caption))
                 (string-match-p "a change not committed" (demo-test-text "src/aquarium.lisp"))))
    (let ((default-directory demo-test-root)) (call-process "git" nil nil nil "restore" "--" "src/aquarium.lisp"))))
