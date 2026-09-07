# RV32IM Out-of-Order Processor

An out-of-order RISC-V processor designed and implemented in SystemVerilog
by a three-person team over eight weeks for UIUC ECE 411. The processor uses
explicit register renaming and supports the RV32IM instruction set. We built
the design incrementally from a fetch frontend into a complete speculative
processor, then profiled and optimized it across six benchmark workloads.

## Highlights

- Explicit register renaming with RAT, RRAT, physical register file, and freelist
- Reorder buffer and parameterized reservation stations
- Split load/store queue and post-commit store buffer
- Pipelined instruction and data caches
- Next-line instruction prefetcher
- GShare, branch target buffer, and return address stack
- Dual-instruction commit

The final design was checked against an RVFI/Spike reference model across six
benchmarks. Relative to the course baseline, it achieved 4–31% higher IPC and
24–69% lower PD⁴, depending on the workload.

For the complete architecture, design decisions, waveforms, and benchmark
analysis, see the [final project report](mp_ooo_report_MV.pdf).

## Repository Contents

- `rtl/` — processor and cache SystemVerilog implementation
- `tools/generate_random_test.py` — randomized RV32IM assembly generator used
  during RVFI/Spike verification
- `tools/run_benchmarks.sh` — Tmux workflow used to run the six benchmark
  simulations in parallel
- `mp_ooo_report_MV.pdf` — complete architecture, verification, and performance
  report

This repository is a curated portfolio snapshot. Course-provided build,
simulation, synthesis, benchmark, and autograding infrastructure has been
intentionally omitted, so the project is not distributed as a standalone
reproducible build.

## Team and Contributions

This was a collaborative project by Ansley Tsai, Minsoo Kim, and Reuben De
Souza. All three team members worked on the initial frontend and out-of-order
execution engine during Checkpoints 1 and 2. For Checkpoint 3, I focused on
control-flow and branch handling while my teammates focused on the memory
system; we debugged and integrated the complete processor together.

My primary advanced-feature contributions were:

- Designing and integrating the branch-prediction suite: a GShare conditional
  branch predictor, Branch Target Buffer, and Return Address Stack
- Creating the pipelined cache implementation
- Adding data-cache clock gating to reduce modeled SRAM power
- Profiling the benchmark suite to identify structural bottlenecks and guide
  architecture and resource-sizing decisions
- Developing verification and benchmarking utilities, including randomized
  assembly generation and parallel benchmark execution with Tmux

Architecture decisions, integration, verification, and final optimization were
collaborative efforts across the team.
