## SDC Test Suite Generator

Solver-guided diverse instruction sequence synthesis for detecting silent data corruptions in silicon chips. Built with [Rosette](https://docs.racket-lang.org/rosette-guide/index.html), a solver-aided programming language on top of Racket.

### Prerequisites

- **Racket** with Rosette: `brew install minimal-racket && raco pkg install rosette`
- **Graphviz** (for dependency graph PNGs): `brew install graphviz`
- **LLVM** (for benchmarking vs llvm-stress): `brew install llvm`
- **Python 3** (for the benchmark script, no extra packages needed)

### Quick Start

```bash
cd silent-data-corruptions
racket synth-history.rkt
```

On startup you'll see the current n-gram constraints and be asked if you want to customize them. Press `n` to accept defaults or `y` to change them.

**Typical session -- build a test suite:**

```
> l                    # load the seed program
> g                    # synthesize a new diverse program
  (review the output)
> y                    # add it to the suite
> g                    # repeat as many times as you want
> y
> d                    # view diversity statistics
> p                    # plot dependency graphs
> all                  # export all graphs to one DOT file
> e                    # export suite to JSON for benchmarking
> q                    # quit
```

### Instruction Set Architecture (ISA) Model

| Property | Value |
|----------|-------|
| Registers | 8 (R0-R7) |
| Opcodes | 8: add, sub, xor, mul, shl, and, or, div |
| Instructions per program | 8 |
| Instruction format | `dst = op src1 src2 [imm]` |
| Immediate range | 0-15 (4-bit constant per instruction) |
| Control flow | None |

### Synthesis Constraints

Every synthesized program must satisfy all of:

1. **Valid ranges** -- registers 0-7, opcodes 0-7, immediates 0-15
2. **Structural** -- at least one multiply instruction
3. **Data-dependency depth** -- longest register read-after-write chain >= `MIN-DEPTH` (default 2, max 7)
4. **Hamming diversity** -- differs from every existing test by >= `MIN-HAMMING` instructions (default 2)
5. **N-gram diversity** -- opcode n-gram overlap with each existing test stays within configurable caps (default: n=2 max 2, n=4 max 1, n=8 max 0)

### REPL Commands

| Command | What it does |
|---------|-------------|
| `g` | **Generate** a new diverse test program. Shows depth, Hamming distances, and n-gram overlap. Asks whether to add to suite. |
| `s` | **Show** all programs currently in the test suite. |
| `d` | **Diversity** statistics: pairwise Hamming distances, opcode coverage, per-test dependency depth, and n-gram overlap summary at n=2,4,8. |
| `p` | **Plot** dependency graphs. Enter a test number for one graph, or `all` for every test on a single page. Exports `.dot` files. |
| `n` | **N-gram** configuration. View and change the n-gram overlap caps at any time. |
| `e` | **Export** the test suite to `suite-export.json` for use with the benchmark script. |
| `l` | **Load** the default 8-instruction seed program into the suite. |
| `q` | **Quit**. |

### Dependency Graph Visualization

The `p` command produces both ASCII output in the terminal and Graphviz DOT files.

**Single test:**
```bash
# In the REPL
> p
Which test? (1-3, or 'all'): 1
# Creates test-1-deps.dot

# Render to PNG
dot -Tpng test-1-deps.dot -o test-1-deps.png
```

**All tests on one page:**
```bash
# In the REPL
> p
Which test? (1-3, or 'all'): all
# Creates all-tests-deps.dot

dot -Tpng all-tests-deps.dot -o all-tests-deps.png
```

### Benchmarking vs llvm-stress

The `benchmark.py` script compares the diversity of your Rosette-synthesized suite against randomly generated llvm-stress programs using identical metrics.

**Step 1: Export your Rosette suite**

```bash
# In the REPL after building a suite
> e
# Creates suite-export.json
```

**Step 2: Run the benchmark**

```bash
python3 benchmark.py --rosette suite-export.json --num-stress 20 --num-instr 8
```

This will:
1. Generate 20 llvm-stress programs with different random seeds
2. Parse the LLVM IR to extract arithmetic instruction sequences
3. Compute diversity metrics on both suites
4. Print a side-by-side comparison table

**Benchmark options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--rosette` | (required) | Path to `suite-export.json` |
| `--num-stress` | 20 | Number of llvm-stress programs to generate |
| `--num-instr` | 8 | Instructions per program (should match your Rosette config) |
| `--stress-size` | 300 | llvm-stress size flag; increase if not enough arithmetic ops |
| `--keep-ll` | off | Keep generated `.ll` files in `./stress_ll/` for inspection |

### Files

| File | Description |
|------|-------------|
| `synth-history.rkt` | Main synthesizer with REPL, diversity constraints, graph visualization, and JSON export |
| `benchmark.py` | Diversity benchmark comparing Rosette suite vs llvm-stress random baseline |
| `toy-synth.rkt` | Minimal one-shot synthesizer (no history, no REPL) |

### Configuration

All parameters are at the top of `synth-history.rkt`. Edit these before running to change the ISA dimensions or constraint strictness.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM-REGS` | 8 | Number of registers |
| `NUM-OPS` | 8 | Number of opcodes |
| `NUM-INSTR` | 8 | Instructions per program |
| `IMM-RANGE` | 16 | Immediate value range (0 to N-1) |
| `MIN-HAMMING` | 2 | Minimum Hamming distance from all existing tests |
| `MIN-DEPTH` | 2 | Minimum data-dependency chain length |
| `NGRAM-CONSTRAINTS` | (2,2) (4,1) (8,0) | Max n-gram overlap per window size (also configurable at runtime via `n` command) |
