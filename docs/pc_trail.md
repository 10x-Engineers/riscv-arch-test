# PC trail: locating a hang on a board (debug only)

A test that hangs on hardware prints nothing, so the runner only reports a timeout. The PC trail makes the
board build print where the hart is, every few microseconds, until it stops.

## What it does

With `RVTEST_PC_TRAIL_TICKS` defined, the board build (never the Sail signature build) does this:

1. At the end of `RVTEST_BOOT_TO_MMODE` (after the trap prologs and the mtimecmp init, which park mtimecmp
   at all ones) it sets `mtimecmp = mtime + RVTEST_PC_TRAIL_TICKS` and sets `mie.MTIE` and `mstatus.MIE`.
2. The M-mode trap handler, on an M-timer interrupt, prints `W<mepc> <mstatus>` (16 hex digits each) on the
   DUT UART, re-arms the timer, waits for `mip.MTIP` to clear (otherwise `mret` re-traps at the same PC),
   restores the registers the trampoline saved and returns with `mret`. The test continues.

The interrupted mode is in `mstatus`: MPP (bits 12:11) and MPV (bit 39).

## Turning it on

In the DUT `rvmodel_macros.h`:

```c
#define RVMODEL_DEBUG_UART_THR <transmit holding register address>
#define RVMODEL_DEBUG_UART_LSR <line status register address>
// #define RVMODEL_DEBUG_UART_LSR_THRE 0x20   // ready bit in LSR; 0x20 (16550) by default
#define RVTEST_PC_TRAIL_TICKS 24              // 1 us at 24 MHz
```

It needs RV64 and `RVMODEL_MTIME_ADDRESS` / `RVMODEL_MTIMECMP_ADDRESS`; the build stops with `#error`
otherwise. Cherry-pick this commit onto the branch being debugged and define the ticks there only.

## Reading it

- Run the hanging test together with a test that passes without the trail (a control): the control must
  still pass and print a moving PC; if it does not, the trail itself is disturbing the run.
- Lines that keep coming with the same PC: a loop (or an instruction that never retires but stays
  interruptible). Lines that stop: a hard stall, the hart takes no more interrupts.
- Map the last PCs to the disassembly of the board ELF (`elfs/...elf`); count the case labels or the
  per-case `hfence`/setup sequences before the PC to find the case. Then write a probe for that access.
- Each line costs about 3 ms of UART time at 115200 baud, during which the test does not run, so a run
  with many samples takes long; the runner console keeps the head and tail of long output.

## Never for a real run

It enables interrupts in M-mode, interrupts the test every few microseconds and adds UART output.
Results from a build with `RVTEST_PC_TRAIL_TICKS` defined are not valid test results.

First use: SpacemiT K3, `Sv_H_sv39_vs_perm_vs/vu` hang, located to a load with `vsstatus.MXR = 1`
from an execute-only VS-stage page.
