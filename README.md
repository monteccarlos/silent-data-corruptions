## SDC Test Suite Generator

Solver-guided diverse instruction sequence synthesis for detecting silent data corruptions in silicon chips. Built with [Rosette](https://docs.racket-lang.org/rosette-guide/index.html), a solver-aided programming language on top of Racket.

### Prerequisites

- **Racket** with Rosette: `brew install minimal-racket && raco pkg install rosette`
- **Graphviz** (for dependency graph PNGs): `brew install graphviz`
- **LLVM** (for benchmarking vs llvm-stress): `brew install llvm`
- **Python 3** (for the benchmark script; no extra packages needed)

---

### Reproducing our results (copy-paste)

From the repo root:

```bash
# 1. General synthesizer: 100 tests with depth + Hamming + n-gram constraints
#    Output: suite-export-general.json
racket synth-history-general.rkt --batch 100 --output-dir .

# 2. Bigram focused synthesizer: 100 tests, optimize 2-gram diversity only
#    Output: bigram-suite-export.json
racket synth-history-bigram.rkt --batch 100 --output-dir .

# 3. Benchmark a suite vs 100 llvm-stress programs (default)
#    Use the JSON file you want to compare:
python3 benchmark.py --rosette suite-export-general.json
# or
python3 benchmark.py --rosette bigram-suite-export.json
```

**Output files:**

| Synthesizer | Batch output file |
|-------------|--------------------|
| `synth-history-general.rkt` | `suite-export-general.json` |
| `synth-history-bigram.rkt`  | `bigram-suite-export.json`   |

The benchmark prints a side-by-side table (Rosette suite vs llvm-stress) and, by default, exports the stress baseline to `stress-baseline.json`.

---

### Quick Start (interactive REPL)

**General synthesizer** (constraints: depth, Hamming, n-gram caps):

```bash
racket synth-history-general.rkt
```

**Bigram synthesizer** (optimization: minimize 2-gram overlap only):

```bash
racket synth-history-bigram.rkt
```

On startup, the general synthesizer shows n-gram constraints and can customize them. Press `n` to accept defaults or `y` to change.

**Typical session — build a test suite:**

```
> l                    # load the seed program
> g                    # synthesize a new diverse program
  (review the output)
> y                    # add it to the suite
> g                    # repeat as needed
> y
> d                    # view diversity statistics
> p                    # plot dependency graphs
> all                  # export all graphs to one DOT file
> e                    # export suite to JSON for benchmarking
> q                    # quit
```

---

### Synthesizers

| File | Mode | What it does |
|------|------|--------------|
| `synth-history-general.rkt` | Satisfaction | Enforces depth, Hamming, and n-gram overlap *caps* (2-, 4-, 8-gram). Exports `suite-export-general.json`. |
| `synth-history-bigram.rkt`  | Optimization | Minimizes *total 2-gram overlap* with the existing suite; no depth constraint. Exports `bigram-suite-export.json`. |

### Instruction Set Architecture (ISA) Model

| Property | Value |
|----------|-------|
| Registers | 8 (R0–R7) |
| Opcodes | 9: add, sub, xor, mul, shl, and, or, div, shr |
| Instructions per program | 8 |
| Instruction format | `dst = op src1 src2 [imm]` |
| Immediate range | 0–15 (4-bit constant per instruction) |
| Control flow | None |

### Synthesis constraints (general synthesizer)

Every synthesized program must satisfy:

1. **Valid ranges** — registers 0–7, opcodes 0–8, immediates 0–15  
2. **Structural** — at least one multiply instruction  
3. **Data-dependency depth** — longest register read-after-write chain ≥ `MIN-DEPTH` (default 2, max 7)  
4. **Hamming diversity** — differs from every existing test by ≥ `MIN-HAMMING` instructions (default 2)  
5. **N-gram diversity** — opcode n-gram overlap with each existing test within caps (e.g. n=2 max 2, n=4 max 1, n=8 max 0)

### REPL commands (both synthesizers)

| Command | What it does |
|---------|--------------|
| `g` | **Generate** a new diverse test. Shows depth, Hamming, n-gram overlap. Asks whether to add to suite. |
| `s` | **Show** all programs in the test suite. |
| `d` | **Diversity** statistics: pairwise Hamming, opcode coverage, dependency depth, n-gram summary. |
| `p` | **Plot** dependency graphs (single test or `all`). Writes `.dot` files. |
| `n` | **N-gram** config (general only). View or change n-gram overlap caps. |
| `e` | **Export** suite to the JSON file used by the benchmark. |
| `l` | **Load** the default 8-instruction seed into the suite. |
| `q` | **Quit**. |

### Dependency graph visualization

From the REPL, use `p` then a test number or `all`. Then render DOT to PNG:

```bash
dot -Tpng test-1-deps.dot -o test-1-deps.png
# or
dot -Tpng all-tests-deps.dot -o all-tests-deps.png
```

### Benchmarking vs llvm-stress

`benchmark.py` compares your Rosette suite to randomly generated llvm-stress programs using the same metrics.

**Run the benchmark:**

```bash
python3 benchmark.py --rosette suite-export-general.json
# or
python3 benchmark.py --rosette bigram-suite-export.json
```

Defaults: 100 llvm-stress programs, 8 instructions per program, stress size 600. The script prints a comparison table and can export the stress baseline to JSON.

**Benchmark options:**

| Flag | Default | Description |
|------|--------|-------------|
| `--rosette` | (required) | Path to your Rosette JSON (e.g. `suite-export-general.json` or `bigram-suite-export.json`) |
| `--num-stress` | 100 | Number of llvm-stress programs to generate |
| `--num-instr` | 8 | Instructions per program (match your synthesizer) |
| `--stress-size` | 600 | llvm-stress `-size`; increase if too few arithmetic ops |
| `--keep-ll` | off | Keep generated `.ll` files in `./stress_ll/` for inspection |

### Files

| File | Description |
|------|-------------|
| `synth-history-general.rkt` | General synthesizer: depth + Hamming + n-gram constraints; exports `suite-export-general.json` |
| `synth-history-bigram.rkt`  | Bigram optimizer: minimize 2-gram overlap; exports `bigram-suite-export.json` |
| `benchmark.py` | Compares a Rosette JSON suite vs llvm-stress baseline |

### Configuration

Parameters live at the top of each `.rkt` file. In `synth-history-general.rkt`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM-REGS` | 8 | Number of registers |
| `NUM-OPS` | 9 | Number of opcodes |
| `NUM-INSTR` | 8 | Instructions per program |
| `IMM-RANGE` | 16 | Immediate value range (0 to N−1) |
| `MIN-HAMMING` | 2 | Minimum Hamming distance from all existing tests |
| `MIN-DEPTH` | 2 | Minimum data-dependency chain length |
| `NGRAM-CONSTRAINTS` | (2,2) (4,1) (8,0) | Max n-gram overlap per size (also via `n` in REPL) |
