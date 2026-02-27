Last login: Thu Feb 26 14:00:45 on ttys000
vlad@Vlads-MacBook-Air silent-data-corruptions % cd ../../    
vlad@Vlads-MacBook-Air Downloads % cd ../Desktop/cs257 
vlad@Vlads-MacBook-Air cs257 % ls
toy-synth.rkt
vlad@Vlads-MacBook-Air cs257 % vim toy-synth.rkt






















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
"toy-synth.rkt" 47L, 888B

