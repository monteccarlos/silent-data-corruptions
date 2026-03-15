#lang rosette

(require racket/string json racket/cmdline)

;; --------------------------------------------
;; Parameters
;; --------------------------------------------

(define NUM-REGS    8)
(define NUM-OPS     9)
(define NUM-INSTR   8)
(define IMM-RANGE  16)
(define MIN-HAMMING 2)
(define MIN-DEPTH   2)

;; N-gram overlap limits: (n . max-shared) per n-gram size.
;; With 8 instructions: n=2 yields 7 bigrams, n=4 yields 5, n=8 yields 1.
;; Stored in a box so users can reconfigure at startup or via the REPL.
(define NGRAM-CONSTRAINTS
  (box (list (cons 2 2)
             (cons 4 1)
             (cons 8 0))))

;; --------------------------------------------
;; Default Seed Program
;; Each instruction = (dst op src1 src2 imm)
;; ops: 0=add  1=sub  2=xor  3=mul
;;      4=shl  5=and  6=or   7=div  8=shr
;; imm: constant folded into the result
;; --------------------------------------------

(define SEED-PROGRAM
  (list
   (list 0 0 1 2  0)
   (list 1 1 0 3  1)
   (list 2 2 1 4  0)
   (list 3 3 2 5  3)
   (list 4 4 3 1  2)
   (list 5 5 4 2  0)
   (list 6 6 5 3  1)
   (list 7 7 6 0  0)))

;; --------------------------------------------
;; Mutable Test Suite (History)
;; --------------------------------------------

(define test-suite (box '()))

(define (add-to-suite! prog)
  (set-box! test-suite (append (unbox test-suite) (list prog))))

(define (suite-size)
  (length (unbox test-suite)))

;; --------------------------------------------
;; Helpers
;; --------------------------------------------

(define (valid-reg r) (and (>= r 0) (< r NUM-REGS)))
(define (valid-op  o) (and (>= o 0) (< o NUM-OPS)))
(define (valid-imm i) (and (>= i 0) (< i IMM-RANGE)))
(define (bool->int b) (if b 1 0))

(define (op->string o)
  (cond [(= o 0) "add"]
        [(= o 1) "sub"]
        [(= o 2) "xor"]
        [(= o 3) "mul"]
        [(= o 4) "shl"]
        [(= o 5) "and"]
        [(= o 6) "or"]
        [(= o 7) "div"]
        [(= o 8) "shr"]
        [else     "???"]))

(define (print-inst inst)
  (printf "  R~a = ~a R~a R~a [imm=~a]\n"
          (list-ref inst 0)
          (op->string (list-ref inst 1))
          (list-ref inst 2)
          (list-ref inst 3)
          (list-ref inst 4)))

(define (print-program prog)
  (for-each print-inst prog))

;; Instruction-level equality (works for both symbolic and concrete values)
(define (inst-equal? i1 i2)
  (for/fold ([acc #t]) ([a i1] [b i2])
    (and acc (= a b))))

;; Hamming distance = number of instruction positions that differ
(define (hamming-distance prog1 prog2)
  (apply + (map (lambda (i1 i2)
                  (bool->int (not (inst-equal? i1 i2))))
                prog1 prog2)))

;; Symbolic-safe max (produces ITE node for the solver)
(define (sym-max a b) (if (>= a b) a b))

;; Symbolic index into an N-element depth list (ITE chain over NUM-REGS)
(define (lookup-depth depths r)
  (for/fold ([result (list-ref depths (- NUM-REGS 1))])
            ([i (in-range (- NUM-REGS 1))])
    (if (= r i) (list-ref depths i) result)))

;; Functional update at symbolic index, returns a new list
(define (update-depths depths dst new-val)
  (for/list ([i (in-range NUM-REGS)])
    (if (= dst i) new-val (list-ref depths i))))

;; Longest chain of register read-after-write dependencies
(define (compute-program-depth prog)
  (define-values (_depths max-d)
    (for/fold ([depths (make-list NUM-REGS 0)]
               [max-d  0])
              ([inst prog])
      (define dst  (list-ref inst 0))
      (define src1 (list-ref inst 2))
      (define src2 (list-ref inst 3))
      (define d1   (lookup-depth depths src1))
      (define d2   (lookup-depth depths src2))
      (define new-d (+ 1 (sym-max d1 d2)))
      (values (update-depths depths dst new-d)
              (sym-max max-d new-d))))
  max-d)

;; --------------------------------------------
;; Dependency Graph
;; --------------------------------------------

;; Most recent instruction before `before-idx` that writes to `reg`
(define (find-last-writer prog reg before-idx)
  (for/fold ([found #f])
            ([i (in-range (- before-idx 1) -1 -1)])
    (if (and (not found) (= (list-ref (list-ref prog i) 0) reg))
        i
        found)))

;; List of (from-idx to-idx register) edges
(define (compute-dep-edges prog)
  (define edges '())
  (for ([j (in-range (length prog))])
    (define inst-j (list-ref prog j))
    (for ([src (list (list-ref inst-j 2) (list-ref inst-j 3))])
      (define writer (find-last-writer prog src j))
      (when writer
        (set! edges (cons (list writer j src) edges)))))
  (remove-duplicates (reverse edges)))

(define (inst->string idx inst)
  (format "[~a] R~a = ~a R~a R~a [imm=~a]"
          idx
          (list-ref inst 0)
          (op->string (list-ref inst 1))
          (list-ref inst 2)
          (list-ref inst 3)
          (list-ref inst 4)))

(define (print-dep-graph prog label)
  (define edges (compute-dep-edges prog))
  (printf "\nData-Dependency Graph (~a):\n\n" label)
  (for ([inst prog]
        [j (in-naturals)])
    (define incoming
      (filter (lambda (e) (= (list-ref e 1) j)) edges))
    (define base (inst->string j inst))
    (if (null? incoming)
        (printf "    ~a\n" base)
        (printf "    ~a    <-- ~a\n"
                base
                (string-join
                 (map (lambda (e)
                        (format "[~a] via R~a" (list-ref e 0) (list-ref e 2)))
                      incoming)
                 ", "))))
  (printf "\n  Depth: ~a/~a    Edges: ~a\n"
          (compute-program-depth prog)
          (- NUM-INSTR 1)
          (length edges)))

(define (export-dep-graph-dot prog test-num dir)
  (define edges (compute-dep-edges prog))
  (define path (build-path dir (format "test-~a-deps.dot" test-num)))
  (with-output-to-file path #:exists 'replace
    (lambda ()
      (displayln "digraph deps {")
      (displayln "  rankdir=TB;")
      (displayln "  node [shape=box, fontname=\"monospace\"];")
      (for ([inst prog]
            [i (in-naturals)])
        (printf "  i~a [label=\"~a\"];\n" i (inst->string i inst)))
      (for ([e edges])
        (printf "  i~a -> i~a [label=\"R~a\"];\n"
                (list-ref e 0) (list-ref e 1) (list-ref e 2)))
      (displayln "}")))
  (printf "  Exported: ~a\n" (path->string path)))

(define (export-all-dep-graphs-dot suite dir)
  (define path (build-path dir "all-tests-deps.dot"))
  (with-output-to-file path #:exists 'replace
    (lambda ()
      (displayln "digraph all_deps {")
      (displayln "  rankdir=TB;")
      (displayln "  node [shape=box, fontname=\"monospace\"];")
      (for ([prog suite]
            [t (in-naturals 1)])
        (define edges (compute-dep-edges prog))
        (printf "\n  subgraph cluster_~a {\n" t)
        (printf "    label=\"Test ~a  (depth ~a/~a)\";\n"
                t (compute-program-depth prog) (- NUM-INSTR 1))
        (for ([inst prog]
              [i (in-naturals)])
          (printf "    t~a_i~a [label=\"~a\"];\n" t i (inst->string i inst)))
        (for ([e edges])
          (printf "    t~a_i~a -> t~a_i~a [label=\"R~a\"];\n"
                  t (list-ref e 0) t (list-ref e 1) (list-ref e 2)))
        (displayln "  }"))
      (displayln "}")))
  (printf "  Exported all tests: ~a\n" (path->string path)))

;; --------------------------------------------
;; Opcode N-gram Similarity
;; --------------------------------------------

(define (extract-opcodes prog)
  (map (lambda (inst) (list-ref inst 1)) prog))

;; Contiguous subsequences of length n from a list
(define (ngrams-of-list lst n)
  (if (> n (length lst))
      '()
      (for/list ([i (in-range (- (length lst) (- n 1)))])
        (for/list ([j (in-range n)])
          (list-ref lst (+ i j))))))

(define (extract-opcode-ngrams prog n)
  (ngrams-of-list (extract-opcodes prog) n))

;; Element-wise equality of two n-grams (symbolic-safe)
(define (ngram-equal? ng1 ng2)
  (for/fold ([acc #t]) ([a ng1] [b ng2])
    (and acc (= a b))))

;; Count of n-grams from prog-a that appear anywhere in prog-b's n-gram set.
;; Works when prog-a is symbolic and prog-b is concrete (synthesis) or both
;; concrete (statistics).
(define (ngram-overlap-count prog-a prog-b n)
  (define ngrams-a (extract-opcode-ngrams prog-a n))
  (define ngrams-b (extract-opcode-ngrams prog-b n))
  (apply +
    (map (lambda (ng-a)
           (bool->int
            (for/fold ([acc #f]) ([ng-b ngrams-b])
              (or acc (ngram-equal? ng-a ng-b)))))
         ngrams-a)))

;; --------------------------------------------
;; Test Generation
;;
;; Creates fresh symbolic variables, asserts:
;;   1. Valid register/opcode/immediate ranges
;;   2. At least one multiply
;;   3. Data-dependency depth >= MIN-DEPTH
;;   4. Hamming distance >= MIN-HAMMING from
;;      EVERY program already in the suite
;;   5. Opcode n-gram overlap <= max for each
;;      n in NGRAM-CONSTRAINTS
;; --------------------------------------------

(define (generate-test)
  (clear-vc!)

  (define new-prog
    (for/list ([_ (in-range NUM-INSTR)])
      (define-symbolic* dst op src1 src2 imm integer?)
      (list dst op src1 src2 imm)))

  (define sol
    (solve
     (begin
       ;; Validity
       (for ([inst new-prog])
         (assert (and (valid-reg (list-ref inst 0))
                      (valid-op  (list-ref inst 1))
                      (valid-reg (list-ref inst 2))
                      (valid-reg (list-ref inst 3))
                      (valid-imm (list-ref inst 4)))))

       ;; Structural: at least one multiply
       (assert
        (for/fold ([acc #f]) ([inst new-prog])
          (or acc (= (list-ref inst 1) 3))))

       ;; Structural: require minimum data-dependency depth
       (assert (>= (compute-program-depth new-prog) MIN-DEPTH))

       ;; Diversity: must differ from every existing test
       (for ([h-prog (unbox test-suite)])
         (assert (>= (hamming-distance new-prog h-prog)
                     MIN-HAMMING)))

       ;; Diversity: limit opcode n-gram overlap at each window size
       (for ([constraint (unbox NGRAM-CONSTRAINTS)])
         (define ng-size (car constraint))
         (define max-overlap (cdr constraint))
         (when (<= ng-size NUM-INSTR)
           (for ([h-prog (unbox test-suite)])
             (assert (<= (ngram-overlap-count new-prog h-prog ng-size)
                         max-overlap))))))))

  (if (sat? sol)
      (let ([concrete
             (map (lambda (inst)
                    (map (lambda (v) (evaluate v sol)) inst))
                  new-prog)])
        (values #t concrete))
      (values #f '())))

;; --------------------------------------------
;; Diversity Statistics
;; --------------------------------------------

(define (show-diversity-stats)
  (define suite (unbox test-suite))
  (define n (length suite))
  (cond
    [(< n 2)
     (displayln "\nNeed at least 2 tests for diversity statistics.")]
    [else
     (displayln "\nPairwise Hamming distances:")
     (define all-dists '())
     (for ([i (in-range n)])
       (for ([j (in-range (+ i 1) n)])
         (define d (hamming-distance (list-ref suite i)
                                     (list-ref suite j)))
         (set! all-dists (cons d all-dists))
         (printf "  Test ~a vs Test ~a: ~a/~a instructions differ\n"
                 (+ i 1) (+ j 1) d NUM-INSTR)))
     (printf "\n  Min: ~a  Max: ~a  Avg: ~a\n"
             (apply min all-dists)
             (apply max all-dists)
             (exact->inexact (/ (apply + all-dists)
                                (length all-dists))))

     (define ops-used
       (remove-duplicates
        (apply append
               (map (lambda (prog)
                      (map (lambda (inst) (list-ref inst 1)) prog))
                    suite))))
     (printf "  Opcode coverage: ~a/~a (~a)\n"
             (length ops-used) NUM-OPS
             (string-join (map op->string (sort ops-used <)) ", "))

     (displayln "\nData-dependency depths:")
     (define all-depths
       (for/list ([prog suite]
                  [i (in-naturals 1)])
         (define d (compute-program-depth prog))
         (printf "  Test ~a: depth ~a/~a\n" i d (- NUM-INSTR 1))
         d))
     (printf "\n  Min depth: ~a  Max depth: ~a  Avg: ~a\n"
             (apply min all-depths)
             (apply max all-depths)
             (exact->inexact (/ (apply + all-depths)
                                (length all-depths))))

     (displayln "\nOpcode N-gram overlap:")
     (for ([constraint (unbox NGRAM-CONSTRAINTS)])
       (define ng-size (car constraint))
       (define max-ov (cdr constraint))
       (define num-per-prog (max 0 (- NUM-INSTR (- ng-size 1))))
       (when (> num-per-prog 0)
         (define all-overlaps '())
         (for ([i (in-range n)])
           (for ([j (in-range (+ i 1) n)])
             (define ov
               (ngram-overlap-count (list-ref suite i)
                                    (list-ref suite j)
                                    ng-size))
             (set! all-overlaps (cons ov all-overlaps))))
         (define unique-ngrams
           (remove-duplicates
            (apply append
                   (map (lambda (prog)
                          (extract-opcode-ngrams prog ng-size))
                        suite))))
         (printf "  n=~a (~a per program, max allowed ~a):\n"
                 ng-size num-per-prog max-ov)
         (printf "    Pairwise overlap -- Avg: ~a  Max: ~a\n"
                 (if (null? all-overlaps) 0
                     (exact->inexact
                      (/ (apply + all-overlaps)
                         (length all-overlaps))))
                 (if (null? all-overlaps) 0
                     (apply max all-overlaps)))
         (printf "    Unique ~a-grams across suite: ~a\n"
                 ng-size (length unique-ngrams))))]))

;; --------------------------------------------
;; Read a line safely (returns #f on EOF)
;; --------------------------------------------

(define (read-input prompt)
  (display prompt)
  (flush-output)
  (define raw (read-line))
  (if (eof-object? raw) #f (string-trim raw)))

;; --------------------------------------------
;; N-gram Configuration
;; --------------------------------------------

(define (show-ngram-config)
  (displayln "\nCurrent N-gram constraints:")
  (for ([c (unbox NGRAM-CONSTRAINTS)])
    (printf "  n=~a: max overlap ~a  (~a n-grams per program)\n"
            (car c) (cdr c)
            (max 0 (- NUM-INSTR (- (car c) 1))))))

(define (configure-ngrams!)
  (show-ngram-config)
  (displayln "\nEnter new caps for each n-gram size (or press Enter to keep current):")
  (define new-constraints
    (for/list ([c (unbox NGRAM-CONSTRAINTS)])
      (define ng-size (car c))
      (define current-max (cdr c))
      (define ans
        (read-input (format "  n=~a max overlap [~a]: " ng-size current-max)))
      (if (and ans (not (string=? ans "")) (string->number ans))
          (cons ng-size (string->number ans))
          c)))
  (set-box! NGRAM-CONSTRAINTS new-constraints)
  (displayln "\nUpdated constraints:")
  (show-ngram-config))

;; --------------------------------------------
;; JSON Export
;; --------------------------------------------

(define (export-suite-json dir)
  (define suite (unbox test-suite))
  (define path (build-path dir "suite-export-general.json"))
  (define json-data
    (for/list ([prog suite])
      (hasheq 'instructions
        (for/list ([inst prog])
          (hasheq 'dst (format "R~a" (list-ref inst 0))
                  'op (op->string (list-ref inst 1))
                  'src1 (format "R~a" (list-ref inst 2))
                  'src2 (format "R~a" (list-ref inst 3))
                  'imm (list-ref inst 4))))))
  (with-output-to-file path #:exists 'replace
    (lambda ()
      (write-json json-data)))
  (printf "Exported ~a test(s) to ~a\n" (length suite) (path->string path)))

;; --------------------------------------------
;; Interactive REPL
;; --------------------------------------------

(define (show-help)
  (displayln "\nCommands:")
  (displayln "  [g]enerate   - Synthesize a new diverse test")
  (displayln "  [s]how       - Display the current test suite")
  (displayln "  [d]iversity  - Show pairwise diversity statistics")
  (displayln "  [p]lot       - Show/export dependency graph for a test")
  (displayln "  [n]gram      - View/change n-gram overlap limits")
  (displayln "  [e]xport     - Export test suite to suite-export-general.json")
  (displayln "  [l]oad-seed  - Add the default seed program to the suite")
  (displayln "  [q]uit       - Exit"))

(define (repl)
  (define input (read-input (format "\n[~a test(s)] > " (suite-size))))

  (cond
    ;; EOF or quit
    [(or (not input) (member input '("q" "quit" "exit")))
     (printf "\nSuite has ~a test(s). Goodbye.\n" (suite-size))]

    ;; Generate
    [(member input '("g" "generate"))
     (printf "\nSynthesizing test diverse from ~a existing test(s)...\n"
             (suite-size))
     (define-values (ok? prog) (generate-test))
     (cond
       [ok?
        (displayln "\nSynthesized Program:")
        (print-program prog)
        (printf "\n  Data-dependency depth: ~a/~a\n"
                (compute-program-depth prog) (- NUM-INSTR 1))

        (when (> (suite-size) 0)
          (define dists
            (map (lambda (h) (hamming-distance prog h))
                 (unbox test-suite)))
          (printf "\n  Hamming distances to existing tests: ~a\n" dists)
          (printf "  Min distance: ~a/~a\n"
                  (apply min dists) NUM-INSTR)

          (displayln "\n  N-gram overlap with existing tests:")
          (for ([constraint (unbox NGRAM-CONSTRAINTS)])
            (define ng-size (car constraint))
            (define max-ov (cdr constraint))
            (define num-per-prog (- NUM-INSTR (- ng-size 1)))
            (when (> num-per-prog 0)
              (define overlaps
                (map (lambda (h)
                       (ngram-overlap-count prog h ng-size))
                     (unbox test-suite)))
              (printf "    n=~a: ~a (max allowed ~a)\n"
                      ng-size overlaps max-ov))))

        (define ans (read-input "\nAdd to test suite? [y/n] "))
        (when (and ans (member ans '("y" "yes")))
          (add-to-suite! prog)
          (printf "Added. Suite now has ~a test(s).\n" (suite-size)))]
       [else
        (displayln "UNSAT: Cannot find a program satisfying the constraints.")
        (displayln "Try lowering MIN-HAMMING, MIN-DEPTH, or NGRAM-CONSTRAINTS limits.")])
     (repl)]

    ;; Show suite
    [(member input '("s" "show"))
     (define suite (unbox test-suite))
     (if (null? suite)
         (displayln "\nSuite is empty. Use [l]oad-seed or [g]enerate to start.")
         (begin
           (printf "\nTest Suite (~a tests):\n" (length suite))
           (for ([prog suite]
                 [i (in-naturals 1)])
             (printf "\n--- Test ~a ---\n" i)
             (print-program prog))))
     (repl)]

    ;; Diversity statistics
    [(member input '("d" "diversity"))
     (show-diversity-stats)
     (repl)]

    ;; N-gram configuration
    [(member input '("n" "ngram"))
     (configure-ngrams!)
     (repl)]

    ;; Plot dependency graph
    [(member input '("p" "plot"))
     (define suite (unbox test-suite))
     (if (null? suite)
         (displayln "\nSuite is empty. Load or generate tests first.")
         (begin
           (define ans
             (read-input
              (format "Which test? (1-~a, or 'all'): " (length suite))))
           (cond
             [(and ans (string=? ans "all"))
              (for ([prog suite]
                    [i (in-naturals 1)])
                (print-dep-graph prog (format "Test ~a" i)))
              (export-all-dep-graphs-dot suite (current-directory))]
             [(and ans (string->number ans))
              (define idx (- (string->number ans) 1))
              (if (and (>= idx 0) (< idx (length suite)))
                  (let ([prog (list-ref suite idx)])
                    (print-dep-graph prog (format "Test ~a" (+ idx 1)))
                    (export-dep-graph-dot prog (+ idx 1) (current-directory)))
                  (printf "Invalid test number: ~a\n" ans))]
             [else
              (displayln "Cancelled.")])))
     (repl)]

    ;; Export suite to JSON
    [(member input '("e" "export"))
     (if (= (suite-size) 0)
         (displayln "\nSuite is empty. Nothing to export.")
         (export-suite-json (current-directory)))
     (repl)]

    ;; Load seed
    [(member input '("l" "load-seed" "load"))
     (add-to-suite! SEED-PROGRAM)
     (printf "Loaded seed program. Suite now has ~a test(s).\n" (suite-size))
     (repl)]

    ;; Help
    [(member input '("?" "h" "help"))
     (show-help)
     (repl)]

    ;; Blank line — just re-prompt
    [(string=? input "")
     (repl)]

    [else
     (printf "Unknown command '~a'. Type ? for help.\n" input)
     (repl)]))

;; --------------------------------------------
;; Batch Generation (non-interactive)
;; --------------------------------------------

(define (batch-generate! count output-dir seed?)
  (when seed?
    (add-to-suite! SEED-PROGRAM)
    (displayln "  Loaded seed program as test 1."))
  (define target count)
  (define failures 0)
  (define max-consecutive-failures 10)
  (let loop ()
    (when (and (< (suite-size) (+ target (if seed? 1 0)))
               (< failures max-consecutive-failures))
      (define-values (ok? prog) (generate-test))
      (cond
        [ok?
         (add-to-suite! prog)
         (set! failures 0)
         (printf "  [~a/~a] synthesized (depth ~a)\n"
                 (- (suite-size) (if seed? 1 0)) target
                 (compute-program-depth prog))
         (loop)]
        [else
         (set! failures (+ failures 1))
         (printf "  UNSAT (~a consecutive). Retrying...\n" failures)
         (loop)])))
  (define generated (- (suite-size) (if seed? 1 0)))
  (printf "\nGenerated ~a / ~a requested tests (suite total: ~a).\n"
          generated target (suite-size))
  (when (< generated target)
    (printf "WARNING: Constraint space exhausted after ~a tests.\n" generated))
  (export-suite-json output-dir)
  (printf "Done.\n"))

;; --------------------------------------------
;; Entry Point
;; --------------------------------------------

(define batch-count (box #f))
(define batch-output-dir (box "."))
(define batch-no-seed (box #f))

(command-line
 #:once-each
 ["--batch" n
  "Generate N diverse tests non-interactively and export JSON"
  (set-box! batch-count (string->number n))]
 ["--output-dir" dir
  "Directory for JSON export (default: current directory)"
  (set-box! batch-output-dir dir)]
 ["--no-seed"
  "Skip loading the seed program in batch mode"
  (set-box! batch-no-seed #t)]
 #:args ()
 (void))

(cond
  [(unbox batch-count)
   (printf "=== SDC Batch Generator ===\n")
   (printf "Generating ~a tests...\n" (unbox batch-count))
   (batch-generate! (unbox batch-count)
                    (unbox batch-output-dir)
                    (not (unbox batch-no-seed)))]
  [else
   (displayln "=== SDC Test Suite Generator ===")
   (displayln "Solver-aided diverse instruction sequence synthesis")
   (show-ngram-config)
   (define setup-ans (read-input "\nCustomize n-gram caps? [y/n] "))
   (when (and setup-ans (member setup-ans '("y" "yes")))
     (configure-ngrams!))
   (show-help)
   (repl)])
