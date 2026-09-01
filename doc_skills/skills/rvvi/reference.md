# RVVI clone — deep reference

**Root:** `/home/ahsan-10xe/Downloads/ACT4-20260706T103524Z-3-001/RVVI`  
**HEAD:** `bd1c6b2e4da27726401791507607d0c759711ecf`

## Full file inventory (non-git)

```
RVVI/
├── README.md                          # umbrella: 4 pieces + history (RVFI ⊂ RVVI)
├── diagrams/                          # waveform PNGs (retire, traps, WFI, interrupts)
├── include/host/rvvi/
│   ├── rvviApi.h                      # C API surface (lockstep RM)
│   └── rvviTraceTypes.svh             # rvvi_mem_access_t ONLY
├── source/host/rvvi/
│   ├── rvvi.f                         # filelist (expects ${IMPERAS_HOME} paths)
│   ├── rvviTrace.sv                   # TRACE interface 1.7
│   ├── rvviApiPkg.sv                  # SV DPI package wrapping API
│   ├── rvviTextParser.sv              # example TEXT → display/replay harness
│   └── rvviTextChecker.py             # TEXT lint/check helper
├── RVVI-TRACE/README.md               # port/function prose (v1.7)
├── RVVI-TEXT/
│   ├── README.md                      # element grammar (v0.5)
│   ├── railroad.png
│   └── examples/{traps,dhrystones,vectors}.rvvi
├── RVVI-API/README.md                 # lockstep phases (v1.37)
└── RVVI-VVP/README.md                 # stub v0.0
```

## TRACE signal map (producer → consumer)

```
clk ──► sample edge
valid[hart][retire] ──► event present
order[][] ──► monotonic event id (no gaps)
insn / pc_rdata / pc_wdata
trap / halt / intr / debug_mode / ixl
mode[1:0] + mode_virt
x_wdata[31:0] + x_wb bitmask
f_wdata + f_wb ; v_wdata + v_wb
csr[4095:0] + csr_wb
lrsc_cancel
state[hart][string] ──► free-form KV (not paging)

# side channels (FIFO per registered client)
net_push/pop (+ cancel) ──► pin changes (e.g. interrupts)
mem_access_push/pop ──► rvvi_mem_access_t (paging + addresses)
client_register(recv_nets, recv_memory) ──► client id
```

**Absent on upstream TRACE (critical):** `pte_i`, `pte_d`, `vs_pte_*`, `g_pte_*`, `read_access`, `write_access`, `execute_access`, interrupt *wires* as first-class ports (use NET instead).

## TEXT element graph

```
VERSION ──required first──► VENDOR? ──► PARAMS?
                                      │
HART / ISSUE (latches) ◄──────────────┤
ORDER (optional; often predicted)     │
                                      ▼
NET* / CANCEL* / MEM* ──before──► RET | TRAP ──► X* F* V* C* MODE VIRT DM META CYCLE TIME STATE
```

`RET` asserts retire (`trap=0`); `TRAP` asserts trap event. Multi-issue: multiple `RET`/`TRAP` per valid slot via `ISSUE` / auto-increment.

### MEM KV keys (official)

| Key | Value | Maps to struct field |
|-----|-------|----------------------|
| PTE | hex | `pte` |
| GPTE | hex | `gpte` |
| PT | K/M/G/T/P | `page_type` |
| GPT | K/M/G/T/P | `guest_page_type` |
| GPADDR | hex | `gaddr` |

Bus letter: `I` → `fetch=1`, `D` → `fetch=0`.

## API lifecycle graph

```
rvviRefConfigSet{Int,String}
        ▼
rvviRefInit(elf)
        ▼
mark volatile CSR / memory / privilege windows
        ▼
┌──── main loop ─────────────────────────────┐
│ DUT cycles + TRACE events                  │
│ rvviRefNetSet / NetCancel                  │
│ on retire: Gprs/Pc/InsBin/Csrs/…Compare    │
│ optional Ref*Get for custom checks         │
└────────────────────────────────────────────┘
        ▼
rvviRefShutdown
```

This path is **orthogonal** to Sail→covergroup unless you build a TRACE→API bridge.

## Example TEXT (from `examples/traps.rvvi`)

Pattern: `VERSION` → `VENDOR` → `PARAMS` → stream of `RET`/`TRAP` with optional `X`/`C`.  
No `MEM` lines in shipped examples — paging must be learned from TEXT README + types header.

## ACT4 fork delta checklist

When comparing `riscv-arch-test/framework/src/act/fcov/rvviTrace.sv` to clone:

- [ ] Version macro 1.6 vs 1.7
- [ ] Extra VM wires (`virt_adr_*`, `phys_adr_*`, `pte_*`, `vs_pte_*`, `g_pte_*`, `ppn_*`, `page_type_*`, `*_access`)
- [ ] Extra interrupt wires vs NET FIFO
- [ ] Missing `CLIENTS_MAX`, `state[]`, `mem_accesses` queues, `client_register`
- [ ] Missing `rvviTraceTypes.svh` include

ACT4 short-trace keys (`ORDER`/`PC`/`INSN`/`CSR`/`MODE_VIRT`/`VS_PTE_D`/…) are a **local dialect**; official TEXT uses `RET`/`TRAP`/`C`/`VIRT`/`MEM`.

## Diagrams worth opening

| PNG | Shows |
|-----|-------|
| `InstructionRetirement.png` | Normal retire + GPR/CSR wb |
| `LoadAddressMisalignedTrap.png` | Trap event (no retire) |
| `EnvironmentCallException.png` | ECALL as trap |
| `WFIMie{0,1}.png` | WFI + interrupt nets |
| `TestbenchForAdvancedRISC-VDesignVerification.png` | Full TB topology |

## Imperas path note

`rvvi.f` references `${IMPERAS_HOME}/ImpPublic/...`. In **this** workspace the sources live under the clone’s `source/` + `include/` — use those paths, not Imperas install, unless ImperasDV is installed.
