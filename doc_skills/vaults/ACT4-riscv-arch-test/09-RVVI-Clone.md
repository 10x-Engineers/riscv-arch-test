# RVVI — agent understanding (clone)

> Local clone of https://github.com/riscv-verification/RVVI under repo `RVVI/`.
> Skill: `.cursor/skills/rvvi/` · ACT4 gap: `act4-riscv-arch-test` skill `RVVI-for-ACT4.md`.

## Status
- [x] Cloned into workspace (`RVVI/`, HEAD `bd1c6b2`)
- [x] Agent skill + reference graph authored (2026-08-13)
- [x] First ACT4 wiring (2026-08-17): `fcov` uses official `rvvi_mem_access_t`; coverpoints sample `ins.current.mem_{i,d}.pte` / `.gpte`. Short doc: `riscv-arch-test/docs/RVVI-PTE-Wiring.md`. Full TEXT dialect still open.

## Hard facts
1. Four pieces: TRACE (SV IF 1.7), TEXT (file 0.5), API (lockstep 1.37), VVP (empty).
2. Official paging = `rvvi_mem_access_t` / TEXT `MEM` with `PTE`/`GPTE` — **not** TRACE wires `vs_pte_*`.
3. ACT4 flat `*.rvvi` + forked `fcov/rvviTrace.sv` remain a dialect, but H leaves now live in `mem_i`/`mem_d` (pte/gpte).
4. Prefer reading files under `RVVI/` over inventing from GitHub snippets.
