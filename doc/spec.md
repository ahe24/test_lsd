# Massive Scale Verilog Design Specification

## 1. Objective
Design and verify a massive, large-scale RTL design to deliberately stress the simulation environment. The system must exhibit:
- Huge simulator overhead and overload.
- Very long simulation times (e.g., heavily loading the simulator even for 1 µs of simulation time).
- Long compilation times (taking several minutes) due to a massive number of unique files.

## 2. Directory Structure
- `doc/`: Documentation and specifications (this directory).
- `rtl/`: RTL design source files.
- `tb/`: UVM-based testbench files.
- `sim/`: Simulation scripts (Makefile, file lists) and run directory.

## 3. RTL Architecture (`rtl/`)
To achieve the requirement of "many modules without duplicated functions" and massive logic scale, the design will integrate several highly complex subsystems interacting with each other:
1. **Deep CNN Accelerator**: Massive arrays of diverse MAC (Multiply-Accumulate) architectures, non-linear activation modules, and pooling units.
2. **Multi-core Cryptographic Engine**: Independent, non-reused modules for AES-256, RSA-4096, SHA-3, and Elliptic Curve Cryptography (ECC).
3. **Advanced Graphics Pipeline Engine**: Submodules for vertex transformations, rasterization math, and pixel shading calculations.
4. **Complex Number Arithmetic Logic Unit (ALU)**: 32-bit (and higher) precision floating-point complex number operations (FFT butterflies, matrix inversions).
5. **High-Speed Error Correction Codecs**: Fully unrolled, parallel LDPC and Turbo decoding pipelines.

**Characteristics:**
- No duplicated modules: E.g., instead of instantiating one generic module 10,000 times, the design will contain thousands of uniquely named/structured sub-blocks to bloat the compilation tree and memory footprint.
- Deeply nested hierarchy and massive cross-module wiring.
- High toggle-rate logic to saturate simulator event queues.

## 4. Verification Methodology (`tb/`)
- **Framework**: Universal Verification Methodology (UVM).
- **Components**:
  - Complex UVM sequences generating massive amounts of concurrent traffic.
  - Multiple active agents pushing data to different interfaces (CNN, Crypto, Graphics, ALU).
  - Heavy Scoreboards with complex reference models and deep transaction queues.
  - Intensive coverage collection (code and functional) to further degrade simulator performance.

## 5. Simulation Environment (`sim/`)
- **Tool**: Questasim.
- **Scripts**: 
  - `Makefile`: Master script for `vlib`, `vmap`, `vlog`, `vopt`, and `vsim`.
  - `compile.f` / `filelist.f`: An exhaustive list of all RTL and TB files.
- **Command Line Usage**: The simulation execution must be fully abstracted by simple Makefile targets. **Crucially, the Makefile must support an easy toggle between legacy (`vopt`/`vsim`) and next-gen (`qopt`/`qsim`) engines to allow for direct performance comparison.** Examples include:
  - `make sim`: Runs the full, massive simulation workload (defaults to `vsim`).
  - `make sim ENGINE=qsim`: Runs the exact same workload using the new Questa One `qopt`/`qsim` engine.
  - `make smokesim`: Runs a short sanity check to verify the environment.
  - `make bmtsim`: Runs the bare-metal / base block test suite.
- **2025 Questa Tool Reference (For Makefile Construction)**:
  - **Questa One Sim (`qopt` / `qsim`)**: For the newly released next-generation Questa One Sim platform, the Makefile should support the `qopt` (Advanced Optimization) and `qsim` (Advanced Simulation) engines. These commands are specifically designed to accelerate massive, parallel workloads and AI-driven regressions.
  - **`qrun` (Modern 1-Step Flow)**: Siemens EDA's recommendation for simplifying flows. `qrun` acts as a wrapper that automatically manages compilation/optimization/simulation dependencies and applies intelligent defaults. E.g., `qrun -sv -f compile.f -uvm -coverage`.
  - **`vlog` (Compilation)**: Use `-sv` (SystemVerilog), `-mfcu` (Multi-file compilation unit, essential for UVM), `-timescale=1ns/1ps`, and `-suppress <msg_num>` to manage massive compile logs.
  - **Optimization (`vopt` / `qopt`)**: Use `-O5` (Aggressive optimization for maximum performance). For visibility, use selective `-access=rw` or `+acc` (avoid blanket `+acc` as it degrades performance). Use `+cover=bcesft` for full coverage instrumentation.
  - **Execution (`vsim` / `qsim`)**: Use `-qwavedb` (the modern wave database format replacing `.wlf`), `-uvmcontrol=all` for full UVM debug visibility, and typical batch mode flags `-c -do "run -all; quit"`.
- **Expected Behavior**:
  - Compilation (`vlog` + `vopt`/`qopt`, or `qrun`) will take multiple minutes due to the massive number of unrolled, unique modules.
  - Execution (`vsim` or `qsim`) will run extremely slowly due to the massive event density per picosecond.

## 6. Implementation Plan (Pending)
- **Phase 1**: Script-based generation of thousands of unique RTL modules to fulfill the "no duplicated functions" requirement.
- **Phase 2**: Top-level integration and wiring.
- **Phase 3**: UVM testbench development (Agents, Env, Scoreboard, Sequences).
- **Phase 4**: Questasim Makefile and run script creation.
