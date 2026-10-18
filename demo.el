;;; demo.el --- watch the aquarium change  -*- lexical-binding: t; -*-

;; In a freshly started Emacs:  M-x load-file RET ~/lisp-ai/aquarium/demo.el RET   and then   M-x aquarium-demo
;; It sets up the screen: the source on the left; on the right the tank above a Sly REPL connected to the running image.
;; When the source file changes on disk, Emacs redraws it within half a second and flashes the part that changed.
;; Nothing here touches ~/.emacs.d/init.el, and none of it outlasts the Emacs session.
;;
;; The Sly used here is the Emacs half of the very checkout the image's Slynk comes from (the Qlot cache), not the ELPA
;; one: the two differ in the prompt message, and with ELPA's Sly every prompt says "Debugger entered on <n>".

(require 'cl-lib)
(require 'pulse)

(defconst aquarium-demo-root (file-name-directory (or load-file-name buffer-file-name))
  "The aquarium project directory.")

(defvar aquarium-demo-tank-lines 14 "How many lines high the tank window is.")

(defun aquarium-demo--sly-directory ()
  "The Sly checkout that Qlot's pinned dist holds: the one the image's Slynk is loaded from."
  (or (car (last (sort (file-expand-wildcards
                        (expand-file-name "~/.cache/qlot/releases/beta.quicklisp.org/quicklisp/*/distinfo/sly/*/sly-*"))
                       #'string<)))
      (error "No Sly checkout under ~/.cache/qlot: run bin/qlot install in the aquarium project first")))

(let ((directory (aquarium-demo--sly-directory)))
  (when (and (featurep 'sly)
             (not (string-prefix-p directory (or (symbol-file 'sly-connect 'defun) ""))))
    (error "Another Sly (%s) is already loaded in this Emacs. Restart Emacs, then load demo.el first"
           (file-name-directory (or (symbol-file 'sly-connect 'defun) "?"))))
  (add-to-list 'load-path directory)
  (add-to-list 'load-path (expand-file-name "contrib" directory))
  (require 'sly))

(defun aquarium-demo-port ()
  "The port rules/slynk.sexp gives: that file is the one place the port is written."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "rules/slynk.sexp" aquarium-demo-root))
    (plist-get (read (current-buffer)) :port)))

(defun aquarium-demo--changed-region (old new)
  "The part of the string NEW that differs from the string OLD, as (START . END) buffer positions; nil if none.
Characters the two have in common at the start and at the end do not count. A pure deletion gives one character."
  (unless (string= old new)
    (let* ((limit (min (length old) (length new)))
           (prefix (let ((i 0))
                     (while (and (< i limit) (eq (aref old i) (aref new i))) (setq i (1+ i)))
                     i))
           (suffix (let ((i 0) (room (- limit prefix)))
                     (while (and (< i room) (eq (aref old (- (length old) 1 i)) (aref new (- (length new) 1 i))))
                       (setq i (1+ i)))
                     i))
           (start (1+ prefix))
           (end (1+ (- (length new) suffix))))
      (cons start (max end (min (1+ start) (1+ (length new))))))))

(defvar-local aquarium-demo--before nil
  "The text this buffer held just before Emacs reverted it.")

(defun aquarium-demo--remember ()
  (setq aquarium-demo--before (buffer-string)))

(defun aquarium-demo--flash ()
  "After a revert: bring the changed part into view and flash it."
  (when aquarium-demo--before
    (let ((region (aquarium-demo--changed-region aquarium-demo--before (buffer-string)))
          (window (get-buffer-window (current-buffer))))
      (setq aquarium-demo--before nil)
      (when region
        (when window
          (set-window-point window (car region))
          (with-selected-window window (recenter)))
        (let ((pulse-iterations 40) (pulse-delay 0.06))
          (pulse-momentary-highlight-region (car region) (cdr region) 'highlight))))))

(defun aquarium-demo--watch (file &optional flash)
  "Visit FILE (relative to the project) and redraw it as soon as it changes on disk. With FLASH, flash what changed.
Returns the buffer."
  (let* ((path (expand-file-name file aquarium-demo-root))
         ;; a buffer already visiting the file is reused: visiting it again would ask "changed on disk, reread?" every
         ;; time the file has changed since the last poll, which for the tank is every second
         (buffer (or (find-buffer-visiting path) (find-file-noselect path))))
    (with-current-buffer buffer
      (unless (verify-visited-file-modtime buffer) (revert-buffer t t t))
      ;; polling, not file notification: the tank is replaced by a rename, which a notification watch loses
      (setq-local auto-revert-use-notify nil)
      (auto-revert-mode 1)
      (if flash
          (progn (add-hook 'before-revert-hook #'aquarium-demo--remember nil t)
                 (add-hook 'after-revert-hook #'aquarium-demo--flash nil t))
        ;; the tank changes every second: keep it at the top, and do not flash it
        (add-hook 'after-revert-hook #'aquarium-demo--to-top nil t)))
    buffer))

(defun aquarium-demo--to-top ()
  (goto-char (point-min)))

(defun aquarium-demo--give-return-back-to-sly ()
  "In the Sly REPL, make RET send the input to the image even when paredit-mode is on.
init.el turns paredit-mode on in REPLs, and paredit binds RET to `paredit-RET', which only inserts a newline: the
expression is typed and nothing is ever evaluated. This changes the key in the REPL buffer only."
  (when (boundp 'paredit-mode-map)
    (let ((map (make-sparse-keymap)))
      (set-keymap-parent map paredit-mode-map)
      (define-key map (kbd "RET") #'sly-mrepl-return)
      (setq-local minor-mode-overriding-map-alist
                  (cons (cons 'paredit-mode map)
                        (assq-delete-all 'paredit-mode minor-mode-overriding-map-alist))))))

;; last in the hook, so it runs after the hook that turns paredit-mode on
(add-hook 'sly-mrepl-mode-hook #'aquarium-demo--give-return-back-to-sly t)

(defvar aquarium-demo--repl-window nil "The window the Sly REPL is shown in.")

(defun aquarium-demo--display-repl (buffer _alist)
  "A `display-buffer' action: show BUFFER, the Sly REPL, in the demo's REPL window."
  (when (window-live-p aquarium-demo--repl-window)
    (set-window-buffer aquarium-demo--repl-window buffer)
    aquarium-demo--repl-window))

(defun aquarium-demo ()
  "Set up the screen: the source on the left; on the right the tank above a Sly REPL connected to the image."
  (interactive)
  (setq auto-revert-interval 0.5
        auto-revert-verbose nil)
  (add-to-list 'display-buffer-alist '("\\*sly-mrepl" (aquarium-demo--display-repl)))
  (let ((source (aquarium-demo--watch "src/aquarium.lisp" t))
        (tank (aquarium-demo--watch "run/tank.txt")))
    (delete-other-windows)
    (switch-to-buffer source)
    (let* ((tank-window (split-window-right))
           (repl-window (progn (select-window tank-window)
                               (split-window-below aquarium-demo-tank-lines))))
      (set-window-buffer tank-window tank)
      (setq aquarium-demo--repl-window repl-window)
      (when (sly-connected-p) (sly-disconnect-all))
      (select-window repl-window)
      (sly-connect "127.0.0.1" (aquarium-demo-port)))
    (message "Aquarium demo: source on the left, tank top right, Sly REPL below it.")))

(provide 'aquarium-demo)
;;; demo.el ends here
