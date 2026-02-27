#lang rosette

(define NUM-REGS 4)
(define NUM-OPS 4)

;; symbolic fields
(define-symbolic
  dst1 dst2 dst3 dst4
  op1  op2  op3  op4
  s11 s12
  s21 s22
  s31 s32
  s41 s42
  integer?)

;; helper predicates
(define (valid-reg r)
  (and (>= r 0) (< r NUM-REGS)))

(define (valid-op o)
  (and (>= o 0) (< o NUM-OPS)))

;; Solve WITH constraints inside
(define sol
  (solve
   (begin
     (assert
      (and
       (valid-reg dst1) (valid-reg dst2)
       (valid-reg dst3) (valid-reg dst4)

       (valid-reg s11) (valid-reg s12)
       (valid-reg s21) (valid-reg s22)
       (valid-reg s31) (valid-reg s32)
       (valid-reg s41) (valid-reg s42)

       (valid-op op1) (valid-op op2)
       (valid-op op3) (valid-op op4)))

     ;; example constraint: at least one multiply
     (assert
      (or (= op1 3)
          (= op2 3)
          (= op3 3)
          (= op4 3))))))

(displayln sol)
