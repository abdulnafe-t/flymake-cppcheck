;;; flymake-cppcheck.el --- A flymake backend for cppcheck -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Abdulnafé Toulaïmat

;; Author: Abdulnafé Toulaïmat <abdulnafe.toulaimat@gmail.com>
;; Keywords: c,processes,tools

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(defgroup flymake-cppcheck nil
  "Customization group for flymake-cppcheck.el."
  :group 'c
  :group 'tools
  :group 'processes)

(defconst flymake-cppcheck-version "0.1.0"
  "The version of flymake-cppcheck.el.")

(defvar-local flymake-cppcheck--proc nil)

(defcustom flymake-cppcheck-project-marker "compile_commands.json"
  "Value passed to the --project= option."
  :type 'string)

(defcustom flymake-cppcheck-executable "cppcheck"
  "Name of the cppcheck executable."
  :type 'string)

(defcustom flymake-cppcheck-build-dir ".cppcheck"
  "Name of the project-wide cppcheck build dir."
  :type 'string)

(defcustom flymake-cppcheck-check-level "exhaustive"
  "Level of cppcheck diagnostics."
  :type 'string)

(defcustom flymake-cppcheck-enabled-checks "all"
  "Either a string, or a list of strings, of the desired cppcheck diagnostics."
  :type '(choice (string)
                 (repeat (string))))

;;;###autoload
(defun flymake-cppcheck (report-fn &rest args)
  "Flymake backend for cppcheck.

See ‘(Flymake)Backend Functions’ for the meaning of REPORT-FN and ARGS."

  (unless (executable-find flymake-cppcheck-executable)
    (error "Cannot find cppcheck executable"))

  (when (process-live-p flymake-cppcheck--proc)
    (kill-process flymake-cppcheck--proc))

  (let* ((source (current-buffer))
         (output-buffer (get-buffer-create (concat " *flymake-cppcheck<"
                                                   (buffer-name source)
                                                   ">*")))
         (default-directory (project-root (project-current))))
    (save-restriction
      (widen)

      (setq
       flymake-cppcheck--proc
       (make-process
        :name "flymake-cppcheck"
        :noquery t
        :stderr output-buffer
        :buffer output-buffer
        :command `(,flymake-cppcheck-executable
                   ,(concat "--project=" flymake-cppcheck-project-marker)
                   ,(concat "--cppcheck-build-dir=" flymake-cppcheck-build-dir)
                   ,(concat "--check-level=" flymake-cppcheck-check-level)
                   ,(concat "--enable=" (if (stringp flymake-cppcheck-enabled-checks)
                                            flymake-cppcheck-enabled-checks
                                          (mapconcat #'identity flymake-cppcheck-enabled-checks ",")))
                   "--quiet"
                   "--suppress=missingIncludeSystem")
        :sentinel
        (lambda (proc _event)
          (when (memq (process-status proc)
                      '(exit signal))
            (unwind-protect
                (if (with-current-buffer source (eq proc flymake-cppcheck--proc))
                    (with-current-buffer (process-buffer proc)
                      (goto-char (point-min))
                      (cl-loop
                       while (and (search-forward-regexp
                                   (rx
                                    (seq bol
                                         (group-n 1 (one-or-more nonl))
                                         ":"
                                         (group-n 2 (one-or-more (any "0-9")))
                                         ":"
                                         (group-n 3 (one-or-more (any "0-9")))
                                         ": "
                                         (group-n 4 (or
                                                     (literal "error")
                                                     (literal "warning")
                                                     (literal "performance")
                                                     (literal "portability")
                                                     (literal "note")
                                                     (literal "information")
                                                     (literal "style")))
                                         ": "
                                         (group-n 5 (one-or-more (not (any "][" ?\n))))
                                         (opt
                                          "["
                                          (group-n 6 (one-or-more (not (any "]"))))
                                          "]")))
                                   nil t))

                       for file = (match-string 1)
                       for msg = (match-string 5)
                       for (beg . end) = (flymake-diag-region
                                          source
                                          (string-to-number (match-string 2))
                                          (string-to-number (match-string 3)))
                       for code = (match-string 6)
                       for type = (if (string-match "^\\(warning\\|performance\\|portability\\)" (match-string 4))
                                      :warning
                                    (if (string-match "^\\(note\\|style\\|information\\)" (match-string 4))
                                        :note
                                      :error))
                       when (and beg end (string= (expand-file-name file (project-root (project-current)))
                                                  (buffer-file-name source)))
                       collect (flymake-make-diagnostic source
                                                        beg
                                                        end
                                                        type
                                                        (list flymake-cppcheck-executable
                                                              code
                                                              msg))
                       into diags
                       finally (funcall report-fn diags)))
                  (flymake-log :warning "Canceling obsolete check %s" proc))

              (kill-buffer (process-buffer proc)))))))

      (process-send-eof flymake-cppcheck--proc))))

;;;###autoload
(defun flymake-cppcheck-setup ()
  "Set up ‘flymake-cppcheck’."
  (add-hook 'flymake-diagnostic-functions 'flymake-cppcheck nil t))

(add-hook 'eglot-managed-mode-hook #'flymake-cppcheck-setup)


(provide 'flymake-cppcheck)
;;; flymake-cppcheck.el ends here
