"""Shrink a final self-checking ELF for boards that stream ELFs over a slow link.

Two optional steps, both leaving the loaded code and data unchanged:
- discard_locals: drop debug sections and local symbols (thousands of case labels). Global symbols such as
  tohost and begin_signature stay, and so do the local ones in KEEP_SYMBOLS that a runner looks up or prints
  (begin/end_failure_scratch are local but give the runner its failure record).
- signature_dump_bytes: move the end_signature symbol to begin_signature + this many bytes when the region is
  larger. The test code was linked against the real symbols; only a runner that reads end_signature from the
  symbol table to dump the region on failure sees the smaller range. Self-checking tests report their failure
  themselves, so the full dump is not needed.
"""

import shutil
import subprocess
from pathlib import Path

# Local symbols kept by discard_locals (objcopy --wildcard patterns).
KEEP_SYMBOLS = ("*_failure_scratch", "rvmodel_*", "failedtest_*", "irqdbg_*", "irqret_*")


def _symbol(nm_exe: Path, elf: Path, name: str) -> int | None:
    out = subprocess.run([str(nm_exe), str(elf)], capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] == name:
            return int(fields[0], 16)
    return None


def slim_elf(
    src: Path, dst: Path, objcopy_exe: Path, nm_exe: Path, discard_locals: bool, signature_dump_bytes: int
) -> None:
    """Write src to dst with the requested shrinking applied."""
    cmd: list[str] = []
    if discard_locals:
        cmd += ["--strip-debug", "--discard-all", "--wildcard", *(f"--keep-symbol={s}" for s in KEEP_SYMBOLS)]
    if signature_dump_bytes > 0:
        begin = _symbol(nm_exe, src, "begin_signature")
        end = _symbol(nm_exe, src, "end_signature")
        if begin is not None and end is not None and end - begin > signature_dump_bytes:
            cmd += [
                "--strip-symbol=end_signature",
                "--add-symbol",
                f"end_signature={begin + signature_dump_bytes:#x},global",
            ]
    if cmd:
        subprocess.run([str(objcopy_exe), *cmd, str(src), str(dst)], check=True)
    else:
        shutil.copyfile(src, dst)
