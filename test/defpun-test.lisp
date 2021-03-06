;;; Copyright (c) 2011-2012, James M. Lawrence. All rights reserved.
;;;
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:
;;;
;;;     * Redistributions of source code must retain the above copyright
;;;       notice, this list of conditions and the following disclaimer.
;;;
;;;     * Redistributions in binary form must reproduce the above
;;;       copyright notice, this list of conditions and the following
;;;       disclaimer in the documentation and/or other materials provided
;;;       with the distribution.
;;;
;;;     * Neither the name of the project nor the names of its
;;;       contributors may be used to endorse or promote products derived
;;;       from this software without specific prior written permission.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;;; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;;; A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;;; HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;;; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
;;; LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
;;; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
;;; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
;;; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(in-package #:lparallel-test)

;;;; defpun

(define-plet-test defpun-basic-test defpun-basic-test-fn defpun nil)

(defpun defpun-accept ()
  ;; use assert since this may execute in another thread
  (let ((queue (make-queue)))
    (plet ((outer (progn
                    (sleep 0.6)
                    (push-queue :outer queue))))
      ;; placate warnings
      (setf *memo* (lambda () outer))
      (sleep 0.1)
      (plet ((inner1 (sleep 0.4))
             (inner2 (sleep 0.4)))
        (setf *memo* inner1)
        (setf *memo* inner2)
        (push-queue :inner queue)))
        ;; inner plet was parallelized
        (assert (eq :inner (pop-queue queue)))))

#-lparallel.with-green-threads
(base-test defpun-accept-test
  (with-new-kernel (3)
    (sleep 0.1)
    (defpun-accept)
    (is (= 1 1))))

(defpun defpun-reject ()
  ;; use assert since this may execute in another thread
  (let ((queue (make-queue)))
    (plet ((outer1 (progn
                     (sleep 0.4)
                     (push-queue :outer queue)))
           (outer2 (progn
                     (sleep 0.4)
                     (push-queue :outer queue))))
      ;; placate warnings
      (setf *memo* (lambda () outer1))
      (setf *memo* (lambda () outer2))
      (sleep 0.1)
      (plet ((inner1 (sleep 0.2))
             (inner2 (sleep 0.2)))
        (setf *memo* inner1)
        (setf *memo* inner2)
        (push-queue :inner queue)))
    ;; inner plet was not parallelized
    (assert (eq :outer (pop-queue queue)))))

#-lparallel.with-green-threads
(base-test defpun-reject-test
  (with-new-kernel (2)
    (sleep 0.1)
    (defpun-reject)
    (is (= 1 1))))

(defun fib-let (n)
  (if (< n 2)
      n
      (let ((a (fib-let (- n 1)))
            (b (fib-let (- n 2))))
        (+ a b))))

(defpun fib-plet (n)
  (if (< n 2)
      n
      (plet ((a (fib-plet (- n 1)))
             (b (fib-plet (- n 2))))
        (+ a b))))

(defpun fib-plet-if (n)
  (if (< n 2)
      n
      (plet-if (> n 5) ((a (fib-plet-if (- n 1)))
                        (b (fib-plet-if (- n 2))))
        (+ a b))))

(full-test defpun-fib-test
  (loop
     :for n :from 1 :to 15
     :do (is (= (fib-let n) (fib-plet n) (fib-plet-if n)))))

;;; typed

(defun/type fib-let/type (n) (fixnum) fixnum
  (if (< n 2)
      n
      (let ((a (fib-let/type (- n 1)))
            (b (fib-let/type (- n 2))))
        (+ a b))))

(defpun/type fib-plet/type (n) (fixnum) fixnum
  (if (< n 2)
      n
      (plet ((a (fib-plet/type (- n 1)))
             (b (fib-plet/type (- n 2))))
        (+ a b))))

(defpun/type fib-plet-if/type (n) (fixnum) fixnum
  (if (< n 2)
      n
      (plet-if (> n 5) ((a (fib-plet-if/type (- n 1)))
                        (b (fib-plet-if/type (- n 2))))
        (+ a b))))

(full-test defpun/type-fib-test
  (loop
     :for n :from 1 :to 15
     :do (is (= (fib-let/type n) (fib-plet/type n) (fib-plet-if/type n)))))

;;; redefinitions

(base-test redefined-defpun-test
  (with-new-kernel (2)
    (setf *memo* 'foo)
    (handler-bind ((warning #'muffle-warning))
      (eval '(defpun foo (x) (* x x))))
    (is (= 9 (funcall *memo* 3)))
    (handler-bind ((warning #'muffle-warning))
      (eval '(defun foo (x) (* x x x))))
    (is (= 27 (funcall *memo* 3)))))

;;; forward ref

(declaim-defpun func1 func2)

(defpun func2 (x)
  (plet ((y (func1 x)))
    (* x y)))

(defpun func1 (x)
  (plet ((y (* x x)))
    (* x y)))

(full-test declaim-defpun-test
  (is (= 81 (func2 3))))

;;; lambda list keywords

(defpun foo-append (&key left right)
  (if (null left)
      right
      (plet ((x (first left))
             (y (foo-append :left (rest left) :right right)))
        (cons x y))))

(full-test defpun-lambda-list-keywords-test
  (is (equal '(1 2 3 4 5 6 7)
             (foo-append :left '(1 2 3) :right '(4 5 6 7))))
  (is (equal '(1 2 3)
             (foo-append :left '(1 2 3) :right nil)))
  (is (equal '(1 2 3)
             (foo-append :left '(1 2 3))))
  (is (equal '(4 5 6 7)
             (foo-append :right '(4 5 6 7))))
  (is (equal nil
             (foo-append :right nil)))
  (is (equal nil
             (foo-append))))

;;; multiple values

(defpun mv-foo-1 (x y)
  (values x y))

(defpun/type mv-foo-2 (x y) (fixnum fixnum) (values fixnum fixnum)
  (values x y))

(defpun mv-foo-3 (x y)
  (mv-foo-1 x y))

(defpun/type mv-foo-4 (x y) (fixnum fixnum) (values fixnum fixnum)
  (mv-foo-2 x y))

(defpun/type mv-foo-5 (x y) (fixnum fixnum) (values fixnum fixnum)
  (mv-foo-3 x y))

(full-test defpun-mv-test
  (is (equal '(3 4) (multiple-value-list (mv-foo-1 3 4))))
  (is (equal '(3 4) (multiple-value-list (mv-foo-2 3 4))))
  (is (equal '(3 4) (multiple-value-list (mv-foo-3 3 4))))
  (is (equal '(3 4) (multiple-value-list (mv-foo-4 3 4))))
  (is (equal '(3 4) (multiple-value-list (mv-foo-5 3 4)))))
