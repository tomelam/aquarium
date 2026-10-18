;;; -*- lexical-binding: t -*-
;; A check of demo.el, run by hand with the image up:  /opt/homebrew/bin/Emacs --batch -Q -l tests/demo-test.el
;; Prints one line per check. Needs bin/lisp-server running: it connects to the image for real.
;; paredit-mode in REPLs, added to the hook before demo.el is loaded, as ~/.emacs.d/init.el has it
(add-to-list 'load-path (expand-file-name "~/.emacs.d/elpa/paredit-26"))
(require 'paredit)
(add-hook 'sly-mrepl-mode-hook #'paredit-mode)
(load-file (expand-file-name "~/lisp-ai/aquarium/demo.el"))
(defun report (label ok) (princ (format "%s: %s\n" (if ok "PASS" "FAIL") label)))
(defun wait-until (test &optional seconds)
  "Run TEST every tenth of a second, up to SECONDS (15 if nil); its last value."
  (let ((tries 0) (limit (* 10 (or seconds 15))))
    (while (and (< tries limit) (not (funcall test))) (accept-process-output nil 0.1) (setq tries (1+ tries))))
  (funcall test))

(report "the Sly in use is the checkout's, not ELPA's"
        (string-prefix-p (aquarium-demo--sly-directory) (symbol-file 'sly-connect 'defun)))
(report "the port comes from rules/slynk.sexp" (eq (aquarium-demo-port) 4007))
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
(setq aquarium-demo-tank-lines 8)
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
  (report "three windows" (= (length windows) 3))
  (report "the source is shown once" (= 1 (cl-count "aquarium.lisp" names :test #'string=)))
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
