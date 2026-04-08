# BCH Decoder — VHDL Project (Quartus + ModelSim)

A VHDL implementation of a BCH (Bose–Chaudhuri–Hocquenghem) error-correcting code decoder, targeting Intel/Altera FPGAs and developed with Quartus Prime and ModelSim.

---

## Folder Structure

```
.
├── src/        # VHDL source files (.vhd)
├── tb/         # Testbenches (*_tb.vhd)
├── sim/        # ModelSim .do simulation scripts
├── synth/      # Timing constraints (.sdc)
├── doc/        # Diagrams, datasheets, notes
├── quartus/    # Quartus project files (.qpf, .qsf)
└── README.md
```

## Getting Started

### Quartus Prime

1. Open Quartus Prime and select **File → Open Project**.
2. Navigate to `quartus/bch_decoder.qpf`.
3. Update `quartus/bch_decoder.qsf` with your target device and pin assignments.
4. Add your VHDL source files under `src/` and register them in the `.qsf`.
5. Compile the project (**Processing → Start Compilation**).

### ModelSim Simulation

1. Open ModelSim and set the working directory to the project root.
2. In the Tcl console, run:
   ```tcl
   do sim/simulate.do
   ```
3. The script compiles the design and testbench, opens the wave window, and runs the simulation.

---

## GitHub Desktop Workflow

1. Clone this repo via **File → Clone Repository** in GitHub Desktop.
2. After each work session, GitHub Desktop shows a diff of changed files.
3. Only commit source files tracked by Git — if `db/` or `output_files/` appear, fix `.gitignore`.
4. Write short, descriptive commit messages, e.g.:
   - `Add BCH decoder entity and architecture`
   - `Fix syndrome calculation off-by-one`
   - `Synthesis clean on Cyclone V`
5. Push at the end of each session.

### Files tracked by Git

| Tracked ✅ | Ignored ❌ |
|------------|-----------|
| `.vhd` source & testbench | `db/`, `incremental_db/`, `output_files/` |
| `.qpf`, `.qsf` (Quartus project) | `*.sof`, `*.pof`, `*.rbf` bitstream files |
| `.sdc` timing constraints | `work/` (ModelSim compiled library) |
| `.do` simulation scripts | `*.wlf`, `*.vcd` waveform dumps |
| `README.md`, `doc/` | `*.log`, `*.rpt`, `*.bak` |