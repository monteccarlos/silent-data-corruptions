## Toy ISA Synthesizer with Rosette
generates a program consisting of:

4 instructions

4 registers (R0–R3)

4 operations (add, sub, xor, mul)

No control flow

The solver produces a concrete program that satisfies structural constraints.

This is a minimal prototype for a solver-guided test generator.

### Spec
We model 4 registers: R0,R1,R2,R3 which are represented as integers
Each instruction has the form: dst = op src1 src2

### What This Toy Program Does (toy-synth)
The synthesizer:

Creates symbolic variables representing 4 instructions.

Constrains them to:

-Use only valid registers (0–3)
-Use only valid operations (0–3)
-Adds an example structural constraint:
-At least one instruction must be a mul
-Calls the SMT solver through Rosette.

### Adding History (toy-synth-history)
Added 'previous run' as a constraint, forcing at least a Hamming distance of 2

Prints a concrete program satisfying the constraints.

## Running
racket toy-synth.rkt
