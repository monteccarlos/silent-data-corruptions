#lang rosette

;; --------------------------------------------
;; Parameters
;; --------------------------------------------

(define NUM-REGS 4)
(define NUM-OPS 4)
(define NUM-INSTR 4)

;; --------------------------------------------
;; History Program (Concrete Previous Test)
;; Each instruction = (dst op src1 src2)
;; --------------------------------------------

(define H
  (list
   (list 0 0 0 1)
   (list 1 1 0 2)
   (list 2 2 1 3)
   (list 3 3 2 0)))

;; --------------------------------------------
;; Symbolic Instruction Fields
;; --------------------------------------------

(define-symbolic
  dst1 dst2 dst3 dst4
  op1  op2  op3  op4
  s11 s12
  s21 s22
  s31 s32
  s41 s42
  integer?)

;; --------------------------------------------
;; Helper Predicates
;; --------------------------------------------

(define (valid-reg r)
  (and (>= r 0) (< r NUM-REGS)))

(define (valid-op o)
  (and (>= o 0) (< o NUM-OPS)))

(define (inst-equal? dst op s1 s2 hist-inst)
  (and (= dst (list-ref hist-inst 0))
       (= op  (list-ref hist-inst 1))
       (= s1  (list-ref hist-inst 2))
       (= s2  (list-ref hist-inst 3))))

(define (bool->int b)
  (if b 1 0))

;; --------------------------------------------
;; Solve
;; --------------------------------------------

(define sol
  (solve
   (begin

     ;; -------------------------
     ;; Validity constraints
     ;; -------------------------

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

     ;; -------------------------
     ;; Example structural constraint
     ;; At least one multiply
     ;; -------------------------

     (assert
      (or (= op1 3)
          (= op2 3)
          (= op3 3)
          (= op4 3)))

     ;; -------------------------
     ;; Diversity constraint
     ;; Hamming distance ≥ 2 instruction positions
     ;; -------------------------

     (define same1
       (inst-equal? dst1 op1 s11 s12 (list-ref H 0)))

     (define same2
       (inst-equal? dst2 op2 s21 s22 (list-ref H 1)))

     (define same3
       (inst-equal? dst3 op3 s31 s32 (list-ref H 2)))

     (define same4
       (inst-equal? dst4 op4 s41 s42 (list-ref H 3)))

     (define num-same
       (+ (bool->int same1)
          (bool->int same2)
          (bool->int same3)
          (bool->int same4)))

     (define num-different
       (- 4 num-same))

     (assert (>= num-different 2))

     )))

;; --------------------------------------------
;; Pretty Printing
;; --------------------------------------------

(define (op->string o)
  (cond [(= o 0) "add"]
        [(= o 1) "sub"]
        [(= o 2) "xor"]
        [(= o 3) "mul"]))

(define (print-inst dst op s1 s2)
  (printf "R~a = ~a R~a R~a\n"
          dst (op->string op) s1 s2))

;; --------------------------------------------
;; Display Result
;; --------------------------------------------

(if (sat? sol)
    (begin
      (displayln "Synthesized Program:\n")
      (print-inst (evaluate dst1 sol)
                  (evaluate op1 sol)
                  (evaluate s11 sol)
                  (evaluate s12 sol))
      (print-inst (evaluate dst2 sol)
                  (evaluate op2 sol)
                  (evaluate s21 sol)
                  (evaluate s22 sol))
      (print-inst (evaluate dst3 sol)
                  (evaluate op3 sol)
                  (evaluate s31 sol)
                  (evaluate s32 sol))
      (print-inst (evaluate dst4 sol)
                  (evaluate op4 sol)
                  (evaluate s41 sol)
                  (evaluate s42 sol)))
    (displayln "UNSAT: No program satisfies constraints."))
