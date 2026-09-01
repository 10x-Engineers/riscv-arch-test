# RISC-V Hypervisor Domain

## 31 Sheets
| Sheet | Focus |
|-------|-------|
| ExceptionsH-SN | Delegation, ecall/ebreak, virt-instr, HLV/HSV, xtinst |
| ExceptionsHF/HV-SN | FP (FS) and Vector (VS) state |
| InterruptsH-NC | mideleg, hideleg, hip/hie aliases, VSI priority |
| SstcH | vstimecmp, htimedelta, STCE |
| EndianH-JG | VSBE, UBE |
| ZicntrH-JG | counteren, htimedelta by mode |
| SvinvalH-JG | SFENCE/SINVAL in VM |
| H - US | CSR access all modes, TVM, fences, mret/sret |
| SvH-US | Two-stage VM, vsatp/hgatp, MXR/SUM/MPRV |
| PMPH-US | PMP + hypervisor loads/stores |
| SvnapotH-US, SvHCBO-US, SvaduH-US | Extension VM tests |
| Sh* sheets | WARL/mode rules (vsatp, hgatp, vstvec, vstval, htval) |
| ZkrH, SsstateenH, etc. | Placeholder extension sheets |

## CSR groups (H - US)
- **M**: mtval2, mtinst
- **HS**: hstatus, hedeleg, hideleg, hie, hcounteren, hgeie, henvcfg, htval, hip, hvip, htinst, hgatp, hgeip (+htimedelta; RV32 high halves)
- **VS**: vsstatus, vsie, vstval, vsip, vstvec, vsscratch, vsepc, vscause, vsatp (+vstimecmp)
- **S replicas**: sstatus, sie, stvec, sscratch, sepc, scause, stval, sip, satp

## Norm scope (gap analysis)
- Primary: norm-rules ch-12 (H), ch-27–32 (Sh*)
- Secondary: ch-6,8,17,26,41,43,47,48 with hypervisor keywords

## Norm ID formats
- **Canonical**: `norm:hstatus_sz_acc_op` (from norm-rules.html)
- **Legacy xlsx**: `norm:csr:hstatus:reg` → alias in `fill_norm_rules_xlsx.py`

## Trap logging
- **M**: mcause, mepc, mtval, mstatus (GVA,MPP,MPV,MPIE,MIE), mtinst, mtval2
- **HS**: scause, sepc, stval, sstatus, hstatus (GVA,SPV,SPVP), htinst, htval
- **VS**: VS CSRs + vsstatus.SPP/SPIE

## Teaching reference
`ACT4/diagram.md` — hotel analogy for M/HS/VS/U

## Related
- [[01-Project-Overview]] · [[02-Architecture]]
