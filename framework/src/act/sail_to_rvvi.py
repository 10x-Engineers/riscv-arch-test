##################################
# sail_to_rvvi.py
#
# jcarlin@hmc.edu 9 May 2025
# SPDX-License-Identifier: Apache-2.0
#
# Job of this file:
#   Sail prints a long log (*.trace). The coverage TB reads a short file
#   (*.rvvi). This code converts one into the other.
#
# Pipeline:
#   Sail --trace  -->  *.trace  -->  sailLog2Trace()  -->  *.rvvi  -->  TB
#
# One retired instruction = one .rvvi line of KEY VALUE pairs, e.g.:
#   ORDER 12 PC 80000100 INSN 0007a703 MODE 1 MODE_VIRT 1
#     X 14 257a0141 READ_ACCESS 1 WRITE_ACCESS 0 EXECUTE_ACCESS 1
#     VS_PTE_D 200024c7 G_PTE_D 20003001
#
# Extra keys beyond ORDER/PC/INSN/MODE (MODE_VIRT, READ/WRITE_ACCESS,
# VS_PTE_*/G_PTE_*, TRAP) are required for SvH covergroups to hit.
# TB maps VS_PTE_* → rvvi_mem_access_t.pte and G_PTE_* → .gpte
# (fetch=1 for *_I, fetch=0 for *_D); coverpoints still sample
##################################

import re                                                       # regular expressions to parse Sail log lines
from pathlib import Path                                        # Path type for input/output file names


def sailLog2Trace(inputLogFile: Path, outputTraceFile: Path) -> None:
    """Read one Sail *.trace and write the matching short *.rvvi file."""

    # Match a Sail instruction line like:
    #   [568] [VS]: 0x900002A4 (0x00460613) addi x12, x12, 0x4
    # Groups: order, privilege tag, PC, encoding, rest of text
    # MODE uses [A-Z]+ so VS/VU/HS match (older code only allowed [MSU]).
    insn_pattern = re.compile(
        r"\[(\d+)\] \[([A-Z]+)\]: 0x([0-9a-fA-F]+) \(0x([0-9a-fA-F]+)\) (.*)"
    )

    # Match a memory read value: mem[R,0x...] -> 0xVALUE
    # Used for page-table walks and for the word a load returns.
    # Example: mem[R,0x08000C100] -> 0x20001801
    mem_r_pattern = re.compile(r"mem\[R,0x[0-9a-fA-F]+\] -> 0x([0-9a-fA-F]+)")

    # Match a CSR *write* only (arrow left <-). Reads (->) must not flip flags. CSR write only
    # Example: CSR vsatp (0x280) <- 0x80000000
    csr_wr_pattern = re.compile(r"CSR .* \(0x([0-9a-fA-F]+)\) <- 0x([0-9a-fA-F]+)")

    # Sail trap sideband (between retired insn and handler). TB key TRAP is binary.
    # Example: trapping from VS to HS to handle load-page-fault
    trap_pattern = re.compile(r"trapping from [A-Z]+ to [A-Z]+ to handle (.+)")
    # Fetch faults never retire the target insn — PTEs appear *after* the redirect
    # (jalr/branch). Promote those walks to *_PTE_I so invalid_pte_x can score.
    fetch_fault_names = (
        "fetch-page-fault",
        "fetch-guest-page-fault",
        "instruction-page-fault",
        "instruction-guest-page-fault",
    )

    # Patterns for side effects we append onto the .rvvi line
    reg_patterns = {
        "CSR": re.compile(r"CSR .* \(0x([0-9a-fA-F]+)\) (?:<-|->) 0x([0-9a-fA-F]+)"),  # CSR write or read
        "X": re.compile(r"x(\d+) <- 0x([0-9a-fA-F]+)"),                               # integer reg write
        "F": re.compile(r"f(\d+) <- 0x([0-9a-fA-F]+)"),                               # float reg write
        "V": re.compile(r"v(\d+) <- 0x([0-9a-fA-F]+)"),                               # vector reg write
    }

    # Sail privilege tag -> (MODE, MODE_VIRT) numbers the testbench expects.
    # Coverpoints use {mode_virt, mode}; e.g. VS = MODE=1 + MODE_VIRT=1.
    # Sail already chose HS vs S in the log; we map the printed tag only.
    mode_map = {
        "M": ("3", "0"),                                        # machine, not virtual
        "S": ("1", "0"),                                        # supervisor without H
        "HS": ("1", "0"),                                       # HS: same MODE bits as S
        "U": ("0", "0"),                                        # user / guest user
        "VS": ("1", "1"),                                       # virtual supervisor
        "VU": ("0", "1"),                                       # virtual user
    }

    # Live "is paging on?" flags (updated from CSR writes as we scan forward).
    # MODE != Bare means "on": RV32 -> bit 31; RV64 -> bits [63:60].
    # Addresses: satp=0x180, vsatp=0x280, hgatp=0x680.
    # Same mem[R] leaf is labeled VS / G / both depending on these flags.
    satp_on = False                                             # ordinary satp MODE != Bare?
    vsatp_on = False                                            # guest vsatp MODE != Bare?
    hgatp_on = False                                            # hypervisor hgatp MODE != Bare?

    with inputLogFile.open() as f, outputTraceFile.open("w") as outfile:  # Sail log in, rvvi out
        lines = f.readlines()                                   # load whole Sail log into memory

        # We build one rvvi line per insn but flush it when the *next* insn
        # arrives, so we can choose MODE for the insn we just finished.
        output_line = ""                                        # pending previous insn's rvvi text
        pending_mode: str | None = None                         # start privilege of that pending insn
        pending_mode_virt = "0"                                 # start MODE_VIRT of that pending insn
        pending_is_mem = False                                  # was pending insn a load/store/HLV/HSV?
        last_mode: str | None = None                            # most recent insn start MODE (last-flush)
        last_mode_virt = "0"                                    # most recent insn start MODE_VIRT

        for i in range(len(lines)):                             # walk every line of the Sail log
            line = lines[i]                                     # current log line text

            # --- Always: update satp/vsatp/hgatp MODE from CSR writes ---
            # Must run even on non-insn lines so flags stay current between insns.
            # RV32: MODE = bit 31.  RV64: MODE = bits [63:60] (Bare = 0).
            csr_wr = csr_wr_pattern.search(line)                # is this line a CSR write?
            if csr_wr:                                          # yes: update paging flags
                addr = int(csr_wr.group(1), 16)                 # CSR address (e.g. 0x280 = vsatp)
                val = int(csr_wr.group(2), 16)                  # value written into that CSR
                # MODE != Bare: RV64 uses bits [63:60], RV32 uses bit 31
                mode_on = ((val >> 60) & 0xF) != 0 or (val & (1 << 31)) != 0
                if addr == 0x180:                               # satp  (classic S-stage)
                    satp_on = mode_on
                elif addr == 0x280:                             # vsatp (guest VS-stage)
                    vsatp_on = mode_on
                elif addr == 0x680:                             # hgatp (hypervisor G-stage)
                    hgatp_on = mode_on

            insn_match = insn_pattern.search(line)              # is this line a retired instruction?
            if not insn_match:                                  # no: skip (mtime, blank lines, etc.)
                continue

            order, mode_tag, pc, insn, _ = insn_match.groups()  # pull fields out of the Sail insn line
            mode, mode_virt = mode_map.get(mode_tag, ("3", "0"))  # map "VS"/"M"/... to MODE numbers
            insn_val = int(insn, 16)                            # instruction encoding as an integer
            last_mode = mode                                    # remember for last-insn flush
            last_mode_virt = mode_virt                          # remember for last-insn flush

            # Build this insn's rvvi text. MODE/MODE_VIRT use {placeholders}
            # filled later when we flush (see MODE policy at bottom of loop).
            next_output = (
                f"ORDER {order} PC {pc} INSN {insn} "           # order, PC, encoding
                f"MODE {{mode}} MODE_VIRT {{mode_virt}}"        # filled when this line is flushed
            )

            # ============================================================
            # I-FETCH page walk: look at log lines ABOVE this instruction
            # ============================================================
            # Sail usually prints:
            #   mem[R] PTE
            #   mem[R] PTE
            #   mem[X] fetched instruction bytes
            #   [n] [VS]: ...          <-- we are here
            # Walk backward until previous insn (or mem[W]). Do not reuse the
            # previous store's data PTEs — that inflated I-side cover bins.
            ifetch_ptes: list[int] = []                         # PTEs from the instruction-fetch walk
            k = i - 1                                           # start one line above the insn
            seen_x = False                                      # have we hit mem[X] yet while scanning up?
            while k >= 0 and not insn_pattern.search(lines[k]):  # stop at previous insn or start of file
                if "mem[W," in lines[k]:                        # store data: not part of ifetch walk
                    break
                if "mem[X," in lines[k]:                        # instruction-byte fetch
                    seen_x = True                               # from here upward, mem[R]s are ifetch PTEs
                elif seen_x:                                    # above mem[X]: collect walk reads
                    mr = mem_r_pattern.search(lines[k])         # mem[R] -> value?
                    if mr:
                        val = int(mr.group(1), 16)              # the PTE (or similar) value
                        # Keep V=1 walks, and V=0 invalid leaves (A/D + R/W/X)
                        # so invalid-PTE cover bins can still see them.
                        if (val & 1) or ((val & 0xE) and (val & 0xC0)):
                            ifetch_ptes.append(val)             # save this walk entry
                k -= 1                                          # move one line further up
            ifetch_ptes.reverse()                               # put root first, leaf last

            # ============================================================
            # DATA page walk + reg/CSR updates: look at lines AFTER insn
            # ============================================================
            # Store example:
            #   sw
            #   mem[R] PTE(s)
            #   mem[W] store data      <-- stop PTE collection
            #
            # Load / HLV:
            #   Keep ALL walk PTEs (two-stage HLV can have >2 leaves because G
            #   also maps VS page-table pages). Drop any mem[R] that equals an
            #   xN <- value — that is the load payload, not a PTE.
            #
            # Old "stop after need leaves" dropped the real G A=0 leaf on HLV
            # (adbit read_acc ZERO) and mistagged V=1 payloads as VS_PTE_D
            # (poisoned RSW read bins).
            data_ptes: list[int] = []                           # PTEs from the data-access walk
            post_ifetch_ptes: list[int] = []                    # PTEs after insn before a fetch trap
            load_x_vals: set[int] = set()                       # xN <- values (load/HLV result)
            stop_ptes = False                                   # True = do not collect more PTEs
            saw_store = False                                   # True = we saw mem[W] after this insn
            trapped = False                                     # Sail logged a trap after this insn?
            fetch_trap = False                                  # trap was an instruction-fetch fault?
            j = i + 1                                           # start one line below the insn
            while j < len(lines):                               # scan forward until next insn / end
                if insn_pattern.search(lines[j]):               # next retired instruction starts
                    break

                trap_m = trap_pattern.search(lines[j])          # trapping from … to handle …?
                if trap_m:
                    trapped = True                              # TB TRAP key on this retired line
                    cause = trap_m.group(1).strip().lower()
                    if any(name in cause for name in fetch_fault_names):
                        fetch_trap = True                       # promote post-insn PTEs → *_PTE_I
                    stop_ptes = True                            # stop walk collection at trap
                    j += 1
                    continue

                if "mem[W," in lines[j]:                        # store payload written to memory
                    saw_store = True                            # this insn was (or did) a store
                    stop_ptes = True                            # store data is never a PTE
                elif "mem[X," in lines[j]:                      # next insn's ifetch beginning
                    stop_ptes = True                            # leave data-walk collection

                if not stop_ptes:                               # still inside the data walk
                    mr = mem_r_pattern.search(lines[j])         # mem[R] -> value?
                    if mr:
                        val = int(mr.group(1), 16)              # walk PTE or load result
                        # Value "looks like" a PTE candidate?
                        if (val & 1) or ((val & 0xE) and (val & 0xC0)):
                            data_ptes.append(val)               # keep; filter load payload below
                            post_ifetch_ptes.append(val)        # candidate ifetch if fetch-trap

                # Also grab X/F/V/CSR updates printed after the instruction
                for reg, pattern in reg_patterns.items():       # try CSR, then X, then F, then V
                    reg_match = pattern.search(lines[j])        # does this line match?
                    if reg_match:
                        reg_num, reg_val = reg_match.groups()   # register id and new value
                        next_output += f" {reg} {reg_num} {reg_val}"  # append onto rvvi line
                        if reg == "X":                          # load/HLV result lives in xN
                            load_x_vals.add(int(reg_val, 16))
                        break                                   # one match per log line is enough
                j += 1                                          # next log line

            # Fetch fault: target never retires; walk after redirect is the ifetch.
            if fetch_trap and post_ifetch_ptes:
                ifetch_ptes = post_ifetch_ptes                  # score VS_PTE_I / G_PTE_I
                data_ptes = []                                  # do not also emit as data PTEs

            # Drop load/HLV payload mistaken for a PTE (V=1 data words, TLB-hit lw).
            f7_ld = (insn_val >> 25) & 0x7F
            f3_ld = (insn_val >> 12) & 0x7
            is_data_load = (insn_val & 0x7F) == 0x03 or (
                (insn_val & 0x7F) == 0x73
                and f3_ld == 0b100
                and f7_ld in (0x34, 0x36)
            )
            if is_data_load and load_x_vals:
                # HLV.W / LW sign-extend: Sail prints xN <- 0xFFFFFFFFDEADBEEF while
                # the mem[R] walk/payload line is the raw 32-bit word 0xDEADBEEF.
                payloads = set(load_x_vals)
                for v in list(load_x_vals):
                    payloads.add(v & 0xFFFFFFFF)
                    if v <= 0xFFFFFFFF and (v & 0x80000000):
                        payloads.add(v | 0xFFFFFFFF00000000)
                # Truncate at first payload mem[R]: later mem[R] are next-insn ifetch
                # PTEs (would poison VS/G_PTE_D leaf). Do not stop on xN<- alone —
                # that broke some MPRV/HSV paths.
                cut = len(data_ptes)
                for i, p in enumerate(data_ptes):
                    if p in payloads:
                        cut = i
                        break
                data_ptes = [p for p in data_ptes[:cut] if p not in payloads]

            # ============================================================
            # Access flags: was this a read, a write, or both?
            # The reason for the extra HLV/HSV checks is that they are encoded as SYSTEM instructions (opcode = 0x73)
            # rather than normal LOAD (0x03) or STORE (0x23) instructions. Without checking funct3 and funct7,
            # the parser would incorrectly mark them as neither read nor write operations.
            # ============================================================
            # LOAD opcode 0x03 → READ; STORE 0x23 or any mem[W] → WRITE.
            # HLV/HSV are SYSTEM (0x73) with funct3=100; include them so
            # covergroup read/write crosses fire on hypervisor loads/stores.
            # EXECUTE_ACCESS is always 1 on a retired-insn line.
            is_load = (insn_val & 0x7F) == 0x03                 # LOAD opcode
            is_store = (insn_val & 0x7F) == 0x23 or saw_store    # STORE opcode, or we saw mem[W]
            is_hlv = False                                      # hypervisor load virtual?
            is_hsv = False                                      # hypervisor store virtual?
            if (insn_val & 0x7F) == 0x73:                       # SYSTEM opcode family
                f7 = (insn_val >> 25) & 0x7F                    # funct7
                f3 = (insn_val >> 12) & 0x7                     # funct3
                if f3 == 0b100 and f7 in (0x34, 0x36):          # HLV encodings
                    is_hlv = True
                if f3 == 0b100 and f7 == 0x35:                   # HSV encoding
                    is_hsv = True
            read_a = "1" if is_load or is_hlv else "0"          # mark READ_ACCESS for load/HLV
            write_a = "1" if is_store or is_hsv else "0"        # mark WRITE_ACCESS for store/HSV
            # Keep start MODE on flush for mem ops *and* traps (handler would poison VS/VU).
            is_mem = read_a == "1" or write_a == "1" or trapped
            # Fetch trap: keep EXECUTE on redirect so invalid_pte_x / exception_x score.
            # Data trap on load/store: still EXECUTE=1 (retired redirect/mem insn).
            next_output += (
                f" READ_ACCESS {read_a} WRITE_ACCESS {write_a} EXECUTE_ACCESS 1"
            )
            # TB parses TRAP; default 0 via reset — emit 1 when Sail logged a trap.
            if trapped:
                next_output += " TRAP 1"

            # ============================================================
            # Decide which leaf is VS-stage and which is G-stage
            # ============================================================
            # A "leaf" has R/W/X bits [3:1] non-zero.
            # A "non_leaf" entry has V=1 and R/W/X=000 (non-leaf, e.g. L0 pointer).
            # non_leaf matters for invalid/nonleaf fault bins when no leaf exists.
            #
            #   vsatp only  -> last leaf (or non_leaf) is VS
            #   hgatp only  -> last leaf (or non_leaf) is G
            #   both on     -> normally 2nd-to-last = VS, last = G
            #
            # Fault quirk: sometimes Sail never walks a G data leaf. Then the
            # last leaf may be the VS data page (e.g. X-only) and the one before
            # it is G's map of that VS PTE (R+W). Swap so labels stay correct.
            def stage(ptes: list[int], *, trapped_load: bool = False) -> tuple[int, int]:
                leaves = [p for p in ptes if (p & 0xE) != 0]    # leaf: any of R/W/X set
                non_leaf = [p for p in ptes if (p & 1) and (p & 0xE) == 0]  # V=1, no R/W/X

                if vsatp_on and hgatp_on and len(leaves) >= 2:  # two-stage walk with both leaves
                    vs_leaf = leaves[-2]                        # assume VS then G
                    g_leaf = leaves[-1]
                    # Non-trap: [VS R+W PT, G X-only] leaf order is swapped.
                    if (
                        not trapped_load
                        and (g_leaf & 0xE) == 0x8
                        and (vs_leaf & 0xE) == 0x6
                    ):
                        vs_leaf, g_leaf = g_leaf, vs_leaf        # fix swapped order
                    # Trap: [G R+W PT-map, VS X-only] — VS fault before G data leaf is read.
                    elif (vs_leaf & 0xE) == 0x6 and (g_leaf & 0xE) == 0x8:
                        xonly_vs = g_leaf                           # VS data leaf is last
                        vs_leaf = xonly_vs
                        g_leaf = xonly_vs                           # mirror VS X-only perm for G
                        for p in reversed(leaves[:-1]):
                            if (p & 0xE) == 0x8:
                                g_leaf = p                            # prefer earlier G xonly if present
                                break
                    # VS A/D (Svade) fault: walk ends [..., G U=1 R+W PT-map, VS U=0 leaf].
                    elif (vs_leaf & 0x10) and not (g_leaf & 0x10) and (vs_leaf & 0xE) == 0x6:
                        vs_leaf, g_leaf = g_leaf, vs_leaf
                    return vs_leaf, g_leaf

                if vsatp_on and not hgatp_on:                   # VS-stage only
                    if leaves:
                        return leaves[-1], 0                    # (VS leaf, no G)
                    if non_leaf:
                        return non_leaf[-1], 0                     # nonleaf/invalid VS for fault bins
                    return 0, 0
                if hgatp_on:                                    # G-stage (alone or with no VS leaf)
                    if leaves:
                        return 0, leaves[-1]                    # (no VS, G leaf)
                    if non_leaf:
                        return 0, non_leaf[-1]                     # nonleaf/invalid G for fault bins
                    return 0, 0
                return 0, 0                                     # no paging stage on

            vs_i, g_i = stage(ifetch_ptes)                      # ifetch: VS leaf, G leaf
            vs_d, g_d = stage(data_ptes, trapped_load=trapped and is_load)  # data walk

            # ============================================================
            # Emit PTE keys only if that translation is actually on
            # ============================================================
            #   • satp MODE on, H off → legacy PTE_I / PTE_D
            #   • vsatp / hgatp MODE on → VS_PTE_* / G_PTE_* (SvH)
            #   • all MODE off → no PTE keys (avoids mistaking lw data for PTEs)
            hypervisor = vsatp_on or hgatp_on                   # any H-stage / VS paging?
            if satp_on and not hypervisor:                      # classic satp only
                leaf_i = vs_i or g_i                            # ifetch leaf (either slot)
                leaf_d = vs_d or g_d                            # data leaf (either slot)
                if leaf_i:
                    next_output += f" PTE_I {leaf_i:x}"         # ifetch PTE for satp
                if leaf_d:
                    next_output += f" PTE_D {leaf_d:x}"         # data PTE for satp
            elif hypervisor:                                    # vsatp and/or hgatp
                if vs_i:
                    next_output += f" VS_PTE_I {vs_i:x}"        # VS ifetch leaf
                if vs_d:
                    next_output += f" VS_PTE_D {vs_d:x}"        # VS data leaf
                if g_i:
                    next_output += f" G_PTE_I {g_i:x}"          # G ifetch leaf
                if g_d:
                    next_output += f" G_PTE_D {g_d:x}"          # G data leaf

            next_output += "\n"                                 # end of this insn's rvvi line

            # ============================================================
            # Flush previous instruction's rvvi line (MODE choice matters)
            # ============================================================
            # Default (non-mem): MODE on insn N = privilege at start of insn N+1
            #   (= end of N). Sail logs start-of-insn mode; RVVI wants end mode.
            #
            # Exception (load/store/HLV/HSV): use insn N's *start* tag ([VS]).
            # Without that, a faulting guest lw in VS gets MODE from the trap
            # handler (M/HS) and priv_mode_vs crosses never fire.
            if output_line:                                     # there is a pending previous line
                if pending_is_mem:                              # mem op: keep its start privilege
                    m_out, mv_out = pending_mode, pending_mode_virt
                else:                                           # non-mem: use this insn's start (= prev end)
                    m_out, mv_out = mode, mode_virt
                outfile.write(
                    output_line.format(mode=m_out, mode_virt=mv_out)
                )
            output_line = next_output                           # current insn becomes the new pending
            pending_mode = mode                                 # remember its start MODE
            pending_mode_virt = mode_virt                       # remember its start MODE_VIRT
            pending_is_mem = is_mem                             # remember if it was a memory op

        # Last instruction in the log — no following insn to defer MODE from.
        # Fall back to its own start mode (mem: same; non-mem: closest approx).
        if output_line and last_mode is not None:
            if pending_is_mem:                                  # mem op: keep start privilege
                m_out, mv_out = pending_mode, pending_mode_virt
            else:                                               # non-mem: use last known start mode
                m_out, mv_out = last_mode, last_mode_virt
            outfile.write(
                output_line.format(mode=m_out, mode_virt=mv_out)
            )
