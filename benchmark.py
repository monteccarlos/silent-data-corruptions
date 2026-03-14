#!/usr/bin/env python3
"""
Benchmark: compare diversity of Rosette-synthesized test suites vs llvm-stress
random baselines using identical metrics.

Usage:
    python3 benchmark.py --rosette suite-export.json --num-stress 100 --num-instr 8
    python3 benchmark.py --rosette suite-export.json --keep-ll

Use -ll (or --keep-ll) to keep generated .ll files in stress_ll/ for data quality review.
Inspect stress_0.ll, stress_1.ll, etc. to audit the LLVM IR used as the baseline.
"""

import argparse
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from itertools import combinations
from collections import Counter

# ── LLVM IR opcode mapping ─────────────────────────────────────────────────

LLVM_ARITH_OPS = {
    "add": "add", "sub": "sub", "mul": "mul",
    "udiv": "div", "sdiv": "div",
    "xor": "xor", "and": "and", "or": "or",
    "shl": "shl", "lshr": "shr", "ashr": "shr",
}

ARITH_PATTERN = re.compile(
    r"%(\w+)\s*=\s*(add|sub|mul|udiv|sdiv|xor|and|or|shl|lshr|ashr)\s+"
    r"\w+\s+(%\w+|-?\d+),\s*(%\w+|-?\d+)"
)

# ── llvm-stress generation ─────────────────────────────────────────────────

def find_llvm_stress():
    path = shutil.which("llvm-stress")
    if path:
        return path
    for candidate in ["/opt/homebrew/opt/llvm/bin/llvm-stress",
                      "/usr/local/opt/llvm/bin/llvm-stress",
                      "/usr/bin/llvm-stress"]:
        if os.path.isfile(candidate):
            return candidate
    return None


def generate_stress_programs(num_tests, size, num_instr, tmpdir):
    llvm_stress = find_llvm_stress()
    if not llvm_stress:
        print("ERROR: llvm-stress not found. Install LLVM:")
        print("  brew install llvm")
        sys.exit(1)

    programs = []
    for seed in range(num_tests):
        ll_path = os.path.join(tmpdir, f"stress_{seed}.ll")
        subprocess.run(
            [llvm_stress, f"-seed={seed}", f"-size={size}", "-o", ll_path],
            check=True, capture_output=True
        )
        prog = parse_ll_file(ll_path, num_instr, seed=seed)
        if prog:
            programs.append(prog)
    return programs


def parse_ll_file(path, num_instr, seed=None):
    """Extract num_instr arithmetic instructions. Collects all matches, then randomly
    samples num_instr (ordered by document position) to avoid clustering in similar
    positions across programs."""
    with open(path) as f:
        text = f.read()

    instructions = []
    for m in ARITH_PATTERN.finditer(text):
        dst = m.group(1)
        op = LLVM_ARITH_OPS[m.group(2)]
        src1 = m.group(3).lstrip("%")
        src2 = m.group(4).lstrip("%")
        instructions.append({
            "dst": dst, "op": op, "src1": src1, "src2": src2
        })

    if len(instructions) < num_instr:
        return None
    rng = random.Random(seed)
    sampled = sorted(rng.sample(range(len(instructions)), num_instr))
    return [instructions[i] for i in sampled]

# ── Rosette batch generation ───────────────────────────────────────────────

def find_racket():
    path = shutil.which("racket")
    if path:
        return path
    for candidate in ["/opt/homebrew/bin/racket",
                      "/usr/local/bin/racket",
                      "/usr/bin/racket"]:
        if os.path.isfile(candidate):
            return candidate
    return None


def auto_generate_rosette(num_tests, output_dir, synth_script=None):
    racket = find_racket()
    if not racket:
        print("ERROR: racket not found. Install Racket:")
        print("  brew install minimal-racket && raco pkg install rosette")
        sys.exit(1)

    if synth_script is None:
        synth_script = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                    "synth-history.rkt")
    if not os.path.isfile(synth_script):
        print(f"ERROR: Synthesizer not found: {synth_script}")
        sys.exit(1)

    json_path = os.path.join(output_dir, "suite-export.json")

    print(f"Running Rosette batch synthesis ({num_tests} tests)...")
    print(f"  Script: {synth_script}")
    print(f"  Output: {json_path}")
    print()

    result = subprocess.run(
        [racket, synth_script, "--batch", str(num_tests),
         "--output-dir", output_dir],
        cwd=output_dir,
        capture_output=False,
    )

    if result.returncode != 0:
        print(f"ERROR: Rosette synthesis exited with code {result.returncode}")
        sys.exit(1)

    if not os.path.isfile(json_path):
        print(f"ERROR: Expected output not found: {json_path}")
        sys.exit(1)

    return json_path


# ── Rosette JSON loader ────────────────────────────────────────────────────

def export_stress_baseline_json(suite, path):
    """Export stress suite to JSON in same format as Rosette suite-export.json."""
    data = []
    for prog in suite:
        data.append({
            "instructions": [
                {"dst": i["dst"], "op": i["op"], "src1": i["src1"], "src2": i["src2"], "imm": 0}
                for i in prog
            ]
        })
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    return path


def load_rosette_suite(path, num_instr):
    with open(path) as f:
        data = json.load(f)

    programs = []
    for entry in data:
        insts = entry["instructions"][:num_instr]
        if len(insts) == num_instr:
            programs.append([
                {"dst": i["dst"], "op": i["op"],
                 "src1": i["src1"], "src2": i["src2"]}
                for i in insts
            ])
    return programs

# ── Diversity metrics ──────────────────────────────────────────────────────

def extract_opcodes(prog):
    return [inst["op"] for inst in prog]


def hamming_distance(prog_a, prog_b):
    return sum(1 for a, b in zip(extract_opcodes(prog_a),
                                  extract_opcodes(prog_b)) if a != b)


def ngrams(seq, n):
    if n > len(seq):
        return []
    return [tuple(seq[i:i+n]) for i in range(len(seq) - n + 1)]


def ngram_overlap(prog_a, prog_b, n):
    ngs_a = ngrams(extract_opcodes(prog_a), n)
    ngs_b = set(ngrams(extract_opcodes(prog_b), n))
    return sum(1 for ng in ngs_a if ng in ngs_b)


def compute_dep_depth(prog):
    reg_depth = {}
    max_depth = 0
    for inst in prog:
        d1 = reg_depth.get(inst["src1"], 0)
        d2 = reg_depth.get(inst["src2"], 0)
        new_d = 1 + max(d1, d2)
        reg_depth[inst["dst"]] = new_d
        max_depth = max(max_depth, new_d)
    return max_depth


def compute_suite_metrics(suite, num_instr, label):
    n = len(suite)
    if n == 0:
        return None

    all_opcodes = set()
    depths = []
    for prog in suite:
        all_opcodes.update(extract_opcodes(prog))
        depths.append(compute_dep_depth(prog))

    hamming_dists = []
    ngram_overlaps = {2: [], 4: [], 8: []}
    for a, b in combinations(range(n), 2):
        hamming_dists.append(hamming_distance(suite[a], suite[b]))
        for ng_n in [2, 4, 8]:
            if ng_n <= num_instr:
                ngram_overlaps[ng_n].append(
                    ngram_overlap(suite[a], suite[b], ng_n))

    unique_ngrams = {}
    for ng_n in [2, 4, 8]:
        if ng_n <= num_instr:
            all_ngs = set()
            for prog in suite:
                all_ngs.update(ngrams(extract_opcodes(prog), ng_n))
            unique_ngrams[ng_n] = len(all_ngs)

    metrics = {
        "label": label,
        "count": n,
        "opcode_coverage": len(all_opcodes),
        "depth_min": min(depths),
        "depth_max": max(depths),
        "depth_avg": sum(depths) / len(depths),
    }

    if hamming_dists:
        metrics["hamming_avg"] = sum(hamming_dists) / len(hamming_dists)
        metrics["hamming_min"] = min(hamming_dists)
        metrics["hamming_max"] = max(hamming_dists)
    else:
        metrics["hamming_avg"] = 0
        metrics["hamming_min"] = 0
        metrics["hamming_max"] = 0

    for ng_n in [2, 4, 8]:
        ovs = ngram_overlaps.get(ng_n, [])
        if ovs:
            metrics[f"ngram_{ng_n}_avg"] = sum(ovs) / len(ovs)
            metrics[f"ngram_{ng_n}_max"] = max(ovs)
        else:
            metrics[f"ngram_{ng_n}_avg"] = 0.0
            metrics[f"ngram_{ng_n}_max"] = 0
        metrics[f"ngram_{ng_n}_unique"] = unique_ngrams.get(ng_n, 0)

    return metrics

# ── Comparison report ──────────────────────────────────────────────────────

def print_report(stress_m, rosette_m, num_instr):
    max_depth = num_instr - 1
    w_metric = 30
    w_col = 24

    def row(metric, val_s, val_r):
        print(f"  {metric:<{w_metric}}{val_s:<{w_col}}{val_r}")

    print()
    print("=" * (w_metric + w_col * 2 + 2))
    header_s = f"llvm-stress (N={stress_m['count']})"
    header_r = f"Rosette (N={rosette_m['count']})"
    print(f"  {'Metric':<{w_metric}}{header_s:<{w_col}}{header_r}")
    print("─" * (w_metric + w_col * 2 + 2))

    row("Avg pairwise Hamming",
        f"{stress_m['hamming_avg']:.1f} / {num_instr}",
        f"{rosette_m['hamming_avg']:.1f} / {num_instr}")
    row("Min / Max Hamming",
        f"{stress_m['hamming_min']} / {stress_m['hamming_max']}",
        f"{rosette_m['hamming_min']} / {rosette_m['hamming_max']}")
    row("Opcode coverage",
        f"{stress_m['opcode_coverage']}",
        f"{rosette_m['opcode_coverage']}")
    row("Dep depth (min/avg/max)",
        f"{stress_m['depth_min']} / {stress_m['depth_avg']:.1f} / {stress_m['depth_max']}",
        f"{rosette_m['depth_min']} / {rosette_m['depth_avg']:.1f} / {rosette_m['depth_max']}")

    for ng_n in [2, 4, 8]:
        if ng_n <= num_instr:
            nper = num_instr - ng_n + 1
            row(f"{ng_n}-gram overlap (avg/max)",
                f"{stress_m[f'ngram_{ng_n}_avg']:.1f} / {stress_m[f'ngram_{ng_n}_max']}  (of {nper})",
                f"{rosette_m[f'ngram_{ng_n}_avg']:.1f} / {rosette_m[f'ngram_{ng_n}_max']}  (of {nper})")
            row(f"  Unique {ng_n}-grams",
                f"{stress_m[f'ngram_{ng_n}_unique']}",
                f"{rosette_m[f'ngram_{ng_n}_unique']}")

    print("=" * (w_metric + w_col * 2 + 2))
    print()

# ── CSV export ────────────────────────────────────────────────────────────

def write_metrics_csv(stress_m, rosette_m, num_instr, path):
    import csv
    rows = []
    for m in [stress_m, rosette_m]:
        row = {"suite": m["label"], "count": m["count"],
               "opcode_coverage": m["opcode_coverage"],
               "depth_min": m["depth_min"], "depth_avg": round(m["depth_avg"], 2),
               "depth_max": m["depth_max"],
               "hamming_avg": round(m["hamming_avg"], 2),
               "hamming_min": m["hamming_min"], "hamming_max": m["hamming_max"]}
        for ng_n in [2, 4, 8]:
            if ng_n <= num_instr:
                row[f"ngram_{ng_n}_avg_overlap"] = round(m[f"ngram_{ng_n}_avg"], 2)
                row[f"ngram_{ng_n}_max_overlap"] = m[f"ngram_{ng_n}_max"]
                row[f"ngram_{ng_n}_unique"] = m[f"ngram_{ng_n}_unique"]
        rows.append(row)

    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print(f"\nMetrics written to {path}")


# ── CLI ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Benchmark Rosette test suite diversity vs llvm-stress random baseline")

    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--rosette",
                        help="Path to suite-export.json from the Rosette REPL")
    source.add_argument("--auto-generate", type=int, metavar="N",
                        help="Auto-generate N Rosette tests (batch mode, no manual REPL)")

    parser.add_argument("--num-stress", type=int, default=100,
                        help="Number of llvm-stress programs to generate (default: 100)")
    parser.add_argument("--num-instr", type=int, default=8,
                        help="Instructions per program to compare (default: 8)")
    parser.add_argument("--stress-size", type=int, default=600,
                        help="llvm-stress -size flag, controls IR length (default: 600)")
    parser.add_argument("-ll", "--keep-ll", action="store_true",
                        help="Keep generated .ll files in ./stress_ll/ for data quality review")
    parser.add_argument("--output-csv", metavar="PATH",
                        help="Write metrics to a CSV file for easy import into papers/plots")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))

    if args.auto_generate:
        rosette_json = auto_generate_rosette(args.auto_generate, script_dir)
    else:
        rosette_json = args.rosette
        if not os.path.isfile(rosette_json):
            print(f"ERROR: Rosette export not found: {rosette_json}")
            sys.exit(1)

    print(f"Loading Rosette suite from {rosette_json}...")
    rosette_suite = load_rosette_suite(rosette_json, args.num_instr)
    print(f"  Loaded {len(rosette_suite)} programs ({args.num_instr} instructions each)")

    if len(rosette_suite) == 0:
        print("ERROR: No valid programs in Rosette export.")
        sys.exit(1)

    if args.keep_ll:
        tmpdir = os.path.join(os.path.dirname(rosette_json), "stress_ll")
        os.makedirs(tmpdir, exist_ok=True)
    else:
        tmpdir_obj = tempfile.mkdtemp()
        tmpdir = tmpdir_obj

    print(f"\nGenerating {args.num_stress} llvm-stress programs "
          f"(size={args.stress_size}, truncated to {args.num_instr} arith instructions)...")
    stress_suite = generate_stress_programs(
        args.num_stress, args.stress_size, args.num_instr, tmpdir)
    print(f"  Got {len(stress_suite)} valid programs "
          f"(some seeds may not yield enough arithmetic instructions)")

    if len(stress_suite) < 2:
        print("ERROR: Not enough valid llvm-stress programs. "
              "Try increasing --stress-size.")
        sys.exit(1)

    print("\nComputing metrics...")
    stress_metrics = compute_suite_metrics(
        stress_suite, args.num_instr, "llvm-stress")
    rosette_metrics = compute_suite_metrics(
        rosette_suite, args.num_instr, "Rosette")

    print_report(stress_metrics, rosette_metrics, args.num_instr)

    stress_json_path = os.path.join(
        os.path.dirname(os.path.abspath(rosette_json)),
        "stress-baseline.json"
    )
    export_stress_baseline_json(stress_suite, stress_json_path)
    print(f"\nStress baseline exported to: {stress_json_path}")

    if args.output_csv:
        write_metrics_csv(stress_metrics, rosette_metrics, args.num_instr,
                          args.output_csv)

    if args.keep_ll:
        print(f"Generated .ll files kept in: {tmpdir}")


if __name__ == "__main__":
    main()
