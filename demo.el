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
      (error "No Sly checkout under ~/.cache/qlot: run qlot install in the aquarium project first")))

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

;;; Stepping. demo/steps.sexp holds the steps as data; SPACE in the caption window sends the next step's requests to the
;;; image through bin/lisp eval, the door Claude uses, so the echo shows each request and reply in the REPL.

(defvar aquarium-demo-caption-lines 13 "How many lines high the caption window is.")
(defvar aquarium-demo-start-on-setup t
  "When true, `aquarium-demo' starts the demo once the screen is set up. tests/demo-test.el sets it to nil to check the
screen in the real tree, where starting would rewrite src/aquarium.lisp.")
(defvar aquarium-demo--script nil "The plist read from demo/steps.sexp: :intro, :end, :steps.")
(defvar aquarium-demo--next nil "The index of the step SPACE does next, or nil before the start and after the end.")
(defvar aquarium-demo--busy nil "True while a step's requests are on their way.")
(defvar aquarium-demo--caption-window nil "The window the captions are shown in.")

(defun aquarium-demo--read-script ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "demo/steps.sexp" aquarium-demo-root))
    (read (current-buffer))))

(defun aquarium-demo--steps () (plist-get aquarium-demo--script :steps))

(defvar aquarium-demo-caption-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "SPC") #'aquarium-demo-next)
    (define-key map (kbd "q") #'aquarium-demo-quit)
    map))

(define-derived-mode aquarium-demo-caption-mode special-mode "Demo"
  "The captions of the aquarium demo. SPACE: the next step. q: end the demo, the file put back as committed."
  (visual-line-mode 1)
  (setq-local cursor-type nil))

(defun aquarium-demo--caption (&rest paragraphs)
  "Show PARAGRAPHS (strings; nil ones are left out) in the caption window, and select it, so that SPACE reaches it."
  (let ((buffer (get-buffer-create "*aquarium demo*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'aquarium-demo-caption-mode) (aquarium-demo-caption-mode))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (mapconcat #'identity (delq nil paragraphs) "\n\n"))
        (goto-char (point-min))))
    (when (window-live-p aquarium-demo--caption-window)
      (set-window-buffer aquarium-demo--caption-window buffer)
      (select-window aquarium-demo--caption-window))
    buffer))

(defun aquarium-demo--keys ()
  (if aquarium-demo--next
      (format "[SPACE: step %d of %d]   [q: end the demo]" (1+ aquarium-demo--next) (length (aquarium-demo--steps)))
    "[SPACE: run the demo again]   [q: end the demo]"))

(defun aquarium-demo--lisp-now (request)
  "Send REQUEST to the image through bin/lisp eval and wait: (EXIT-STATUS . OUTPUT)."
  (with-temp-buffer
    (let* ((default-directory aquarium-demo-root)
           (status (call-process (expand-file-name "bin/lisp" aquarium-demo-root) nil t nil "eval" request)))
      (cons status (buffer-string)))))

(defun aquarium-demo--failed-p (status output)
  (or (not (eql status 0)) (string-match-p "^\\(ERROR:\\|HELD [0-9]+\\)" output)))

(defun aquarium-demo--send (requests done)
  "Send REQUESTS to the image one after another through bin/lisp eval, without blocking Emacs; then call DONE with nil,
or with the failing request's output if one failed (a held error is abandoned first, so the image is not left waiting)."
  (if (null requests)
      (funcall done nil)
    (let* ((default-directory aquarium-demo-root)
           (output (generate-new-buffer " *aquarium demo request*")))
      (make-process
       :name "aquarium-demo-request" :buffer output :noquery t
       :command (list (expand-file-name "bin/lisp" aquarium-demo-root) "eval" (car requests))
       :sentinel
       (lambda (process _event)
         (unless (process-live-p process)
           (let ((text (with-current-buffer output (buffer-string)))
                 (status (process-exit-status process)))
             (kill-buffer output)
             (if (aquarium-demo--failed-p status text)
                 (progn
                   (when (string-match "^HELD \\([0-9]+\\)" text)
                     (aquarium-demo--lisp-now (format "(debug-abandon %s)" (match-string 1 text))))
                   (funcall done text))
               (aquarium-demo--send (cdr requests) done)))))))))

(defun aquarium-demo--refusal ()
  "Why the demo must not start, or nil: it rewrites src/aquarium.lisp and forgets the ledger, so it starts only when the
file is as committed and the image holds nothing unsaved."
  (let ((default-directory aquarium-demo-root))
    (cond ((not (string= "" (shell-command-to-string "git status --porcelain -- src/aquarium.lisp")))
           "src/aquarium.lisp has changes that are not committed, and the demo would write over them. Commit them, or put the file back with  git restore src/aquarium.lisp , then run bin/demo again.")
          ((let ((reply (aquarium-demo--lisp-now "(pending)")))
             (unless (and (eql (car reply) 0) (string= (string-trim (cdr reply)) "NIL"))
               (format "The running program holds definitions that are in no file yet: %s\nThe demo would throw them away. Save them, or drop them, then run bin/demo again."
                       (string-trim (cdr reply)))))))))

(defun aquarium-demo-start ()
  "Start the demo over: put the starting source in the file and the image, the first four fish in the tank."
  (interactive)
  (setq aquarium-demo--script (aquarium-demo--read-script)
        aquarium-demo--next nil)
  (let ((refusal (aquarium-demo--refusal)))
    (if refusal
        (aquarium-demo--caption "The demo cannot start." refusal)
      (setq aquarium-demo--busy t)
      (aquarium-demo--caption "Starting: the source is being put back to how the program started out...")
      (aquarium-demo--send
       '("(reset-demo)")
       (lambda (failure)
         (setq aquarium-demo--busy nil)
         (if failure
             (aquarium-demo--caption "The demo could not start: the program answered" failure)
           (setq aquarium-demo--next 0)
           (aquarium-demo--caption (plist-get aquarium-demo--script :intro)
                                   (concat "Next: " (plist-get (nth 0 (aquarium-demo--steps)) :do))
                                   (aquarium-demo--keys))))))))

(defun aquarium-demo-next ()
  "Do the next step of the demo; after the last, start it over."
  (interactive)
  (cond (aquarium-demo--busy (message "One moment: the step is still on its way."))
        ((null aquarium-demo--next) (aquarium-demo-start))
        (t
         (let* ((index aquarium-demo--next)
                (step (nth index (aquarium-demo--steps))))
           (setq aquarium-demo--busy t)
           (aquarium-demo--caption (concat "Now: " (plist-get step :do)))
           (aquarium-demo--send
            (plist-get step :send)
            (lambda (failure)
              (setq aquarium-demo--busy nil)
              (if failure
                  (aquarium-demo--caption (format "Step %d did not work: the program answered" (1+ index)) failure
                                          "q ends the demo and puts the file back.")
                (let ((following (nth (1+ index) (aquarium-demo--steps))))
                  (setq aquarium-demo--next (and following (1+ index)))
                  (aquarium-demo--caption (plist-get step :look)
                                          (if following
                                              (concat "Next: " (plist-get following :do))
                                            (plist-get aquarium-demo--script :end))
                                          (aquarium-demo--keys))))))))))

(defun aquarium-demo-quit ()
  "End the demo. If it was stopped half way, put src/aquarium.lisp back as committed, load it, forget what the demo
left unsaved and give the tank its first fish again."
  (interactive)
  (if aquarium-demo--busy
      (message "One moment: the step is still on its way.")
    (let ((default-directory aquarium-demo-root)
          (half-way (or aquarium-demo--next
                        (not (string= "" (shell-command-to-string "git status --porcelain -- src/aquarium.lisp"))))))
      (setq aquarium-demo--next nil)
      (if (not half-way)
          (aquarium-demo--caption "The demo has ended. The source file is as it was committed." (aquarium-demo--keys))
        (call-process "git" nil nil nil "restore" "--" "src/aquarium.lisp")
        (setq aquarium-demo--busy t)
        (aquarium-demo--send
         '("(progn (forget-all) (load \"src/aquarium.lisp\") (setf (tank-fish *tank*) (tank-fish (seed-tank)) (tank-tick *tank*) 0) :restored)")
         (lambda (failure)
           (setq aquarium-demo--busy nil)
           (aquarium-demo--caption (if failure "The demo has ended, but the program did not take the file back:"
                                     "The demo has ended. The source file is back as it was committed, and so is the running program.")
                                   failure (aquarium-demo--keys))))))))

(defun aquarium-demo ()
  "Set up the screen: the source on the left above the captions; on the right the tank above a Sly REPL connected to
the image. Then start the demo; SPACE in the caption window goes on."
  (interactive)
  (setq auto-revert-interval 0.5
        auto-revert-verbose nil)
  (add-to-list 'display-buffer-alist '("\\*sly-mrepl" (aquarium-demo--display-repl)))
  (let ((source (aquarium-demo--watch "src/aquarium.lisp" t))
        (tank (aquarium-demo--watch "run/tank.txt")))
    (delete-other-windows)
    (switch-to-buffer source)
    (let* ((source-window (selected-window))
           (tank-window (split-window-right))
           (caption-window (split-window source-window (- aquarium-demo-caption-lines) 'below))
           (repl-window (progn (select-window tank-window)
                               (split-window-below aquarium-demo-tank-lines))))
      (set-window-buffer tank-window tank)
      (setq aquarium-demo--repl-window repl-window
            aquarium-demo--caption-window caption-window)
      (when (sly-connected-p) (sly-disconnect-all))
      (select-window repl-window)
      (sly-connect "127.0.0.1" (aquarium-demo-port)))
    (if aquarium-demo-start-on-setup
        (aquarium-demo-start)
      (aquarium-demo--caption "The screen is set up; SPACE starts the demo."))))

(defun aquarium-demo--back-to-caption ()
  "Once the REPL is up, give the keyboard back to the caption window, so that SPACE goes on with the demo."
  (when (window-live-p aquarium-demo--caption-window)
    (run-at-time 0.5 nil (lambda () (when (window-live-p aquarium-demo--caption-window)
                                      (select-window aquarium-demo--caption-window))))))

(add-hook 'sly-mrepl-mode-hook #'aquarium-demo--back-to-caption t)

(provide 'aquarium-demo)
;;; demo.el ends here
