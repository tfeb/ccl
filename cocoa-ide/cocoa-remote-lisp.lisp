;;;-*- Mode: Lisp; Package: CCL -*-
;;;
;;;   Copyright (C) 2011 Clozure Associates
;;;   This file is part of Clozure CL.  
;;;
;;;   Clozure CL is licensed under the terms of the Lisp Lesser GNU Public
;;;   License , known as the LLGPL and distributed with Clozure CL as the
;;;   file "LICENSE".  The LLGPL consists of a preamble and the LGPL,
;;;   which is distributed with Clozure CL as the file "LGPL".  Where these
;;;   conflict, the preamble takes precedence.  
;;;
;;;   Clozure CL is referenced in the preamble as the "LIBRARY."
;;;
;;;   The LLGPL is also available online at
;;;   http://opensource.franz.com/preamble.html

;;  Use the IDE to debug a remote ccl.
;;  **** THIS IS NOT COMPLETE AND NOT HOOKED UP TO ANYTHING YET *****
;;

(in-package "GUI")

#+debug ;; For testing, start a ccl running swank, then call this in the ide.
(defun cl-user::rlisp-test (port &optional host)
  (declare (special cl-user::conn))
  (when (boundp 'cl-user::conn) (close cl-user::conn))
  (setq cl-user::conn (ccl::connect-to-swank (or host "localhost") port))
  (ccl::make-rrepl-thread cl-user::conn "IDE Listener"))

(defclass remote-listener-hemlock-view (hi:hemlock-view)
  ((remote-thread :initarg :remote-thread :accessor listener-remote-thread)))

;; Kludge city
(defun create-remote-listener-view (rthread)
  (let* ((listener (new-listener :inhibit-greeting t))
         (doc (hi::buffer-document (hi:hemlock-view-buffer listener)))
         (process (or (hemlock-document-process doc)
                      (error "Not a listener: ~s" listener))))
    (setf (hemlock-document-process doc) nil) ;; so killing the process doesn't close the window
    (process-kill process)
    (change-class listener 'remote-listener-hemlock-view :remote-thread rthread)
    listener))

(defmethod activate-rlisp-listener ((view remote-listener-hemlock-view))
  (execute-in-gui
   (lambda ()
     (#/makeKeyAndOrderFront: (#/window (hi::hemlock-view-pane view)) (%null-ptr)))))


;; TODO: Do something to show that remote is not active
(defmethod deactivate-rlisp-listener ((view remote-listener-hemlock-view))
  nil)

(defun listener-view-for-remote-thread (rthread &key activate)
  (let ((view (first-window-satisfying-predicate (lambda (wptr)
                                                   (let ((view (hemlock-view wptr)))
                                                     (and (typep view 'remote-listener-hemlock-view)
                                                          (eql (listener-remote-thread view) rthread)))))))
    (when (and activate view)
      (activate-rlisp-listener view))
    view))

(defmethod ccl::create-rlisp-listener ((app cocoa-application) (rthread ccl::remote-lisp-thread))
  (let* ((view (or (listener-view-for-remote-thread rthread :activate t)
                   (create-remote-listener-view rthread)))
         (buffer (hi:hemlock-view-buffer view))
         (doc (hi::buffer-document buffer))
         (name (hi:buffer-name buffer)))
    (assert (null (hemlock-document-process doc)))
    (setf (hemlock-document-process doc)
          ;; TODO: hemlock puts the local process number on modeline, which is uninteresting.
          ;; TODO: change process name when change buffer name.
          (new-cocoa-listener-process (format nil "~a [Remote ~a(~a)]"
                                              name
                                              (ccl::rlisp-host-description rthread)
                                              (ccl::rlisp-thread-id rthread))
                                      (#/window (hi::hemlock-view-pane view))
                                      :class 'remote-cocoa-listener-process
                                      :initargs  `(:remote-thread ,rthread)
                                      :initial-function
                                      (lambda ()
                                        (setf (hemlock-document-process doc) *current-process*)
                                        (ccl::remote-listener-function rthread))))))

(defmethod ui-object-do-operation ((ui ns:ns-application) (op (eql :deactivate-rlisp-listener)) rthread)
  ;; Do something to show that the listener is not active
  (let ((view (listener-view-for-remote-thread rthread)))
    (when view
      (deactivate-rlisp-listener view))))

(defclass remote-cocoa-listener-process (cocoa-listener-process)
  ((remote-thread :initarg :remote-thread :reader process-remote-thread)))

(defmethod process-kill :before ((process remote-cocoa-listener-process))
  (let* ((wptr (cocoa-listener-process-window process))
         (view (hemlock-view wptr)))
    (when view
      ;; don't close the window just because kill process.
      (let ((doc (#/document wptr)))
        (when (and doc (not (%null-ptr-p doc)))
          (setf (hemlock-document-process doc) nil)))
      (deactivate-rlisp-listener view))))

;; Cmd-, calls this
(defmethod ccl::force-break-in-listener ((p remote-cocoa-listener-process))
  ;; Cause the other side to enter a breakloop, which it will inform us of when it happens.
  (ccl::rlisp/interrupt (process-remote-thread p)))

(defmethod ccl::output-stream-for-remote-lisp ((app cocoa-application))
  (hemlock-ext:top-listener-output-stream))

(defmethod ccl::input-stream-for-remote-lisp ((app cocoa-application))
  (hemlock-ext:top-listener-input-stream))

(defmethod ccl::toplevel-form-text ((stream cocoa-listener-input-stream))
  (with-slots (read-lock queue-lock queue queue-semaphore text-semaphore) stream
    (with-lock-grabbed (read-lock)
      (assert (with-slots (cur-sstream) stream (null cur-sstream)))
      (wait-on-semaphore queue-semaphore nil "Toplevel Read")
      (let ((val (with-lock-grabbed (queue-lock) (pop queue))))
        (cond ((stringp val) ;; listener input
               (assert (with-slots (text-semaphore) stream
                         (timed-wait-on-semaphore text-semaphore 0))
                       ()
                       "text/queue mismatch!")
               (values val nil t))
              (t
               ;; TODO: this is bogus, the package may not exist on this side, so must be a string,
               ;; but we can't bind *package* to a string.  So this assumes the caller will know
               ;; not to progv the env.
               (destructuring-bind (string package-name pathname offset) val ;; queued form
                 (declare (ignore offset))
                 (let ((env (cons '(*loading-file-source-file*)
                                  (list pathname))))
                   (when package-name
                     (push '*package* (car env))
                     (push package-name (cdr env)))
                   (values string env)))))))))
