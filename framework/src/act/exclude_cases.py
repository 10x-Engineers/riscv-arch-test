"""Per-DUT test-case exclusion: drop named cases from a test source before it is built.

A DUT config can name an exclude_cases_file: tab-separated lines of test name, case-label regex and
reason (# comments and blank lines ignored). Each matching case is removed from that test's source, so
the reference model and the DUT both run the test without it. Used for cases that stop at a known
hardware deviation, so the rest of the test still runs on the board.

A case runs from its "<group>_cg_cp_<bin>:" label to the last line before the next case label that
names it (the instruction and its signature checks). Setup before the label and restores after the
checks stay. Some tests group several cases and check them together afterwards (Sv exceptions: store,
load and fetch labels, then their RVTEST_SIGUPDs, sometimes after a mode switch): when no line after the
label names it, or its span names another case or a mode switch, the case is its label up to the first blank or
preprocessor line, plus every later line that names it (its checks), each with the "# Check ..." comment
just above it. A case with no check at all is its label and instruction block.
"""

import re
from functools import lru_cache
from pathlib import Path

_LABEL = re.compile(r"^(\w+_cg_cp_\w+):\s*$")
_REF = re.compile(r"\w+_cg_cp_\w+")
# A privilege change between the instruction and its checks (U-mode cases return to S through T-SBI first)
_MODE_SWITCH = re.compile(r"\bRVTEST_(TSBI_)?GOTO_\w+")
# Preprocessor lines only: "# comment" lines in assembly are not directives.
_DIRECTIVE = re.compile(r"^\s*#\s*(if|ifdef|ifndef|elif|else|endif|define|undef|include)\b")


def _depth(lines) -> int:
    """#if nesting depth left open at the end of the lines (negative: an #endif closes an outer block)."""
    depth = 0
    for line in lines:
        m = _DIRECTIVE.match(line)
        if m and m.group(1) in ("if", "ifdef", "ifndef"):
            depth += 1
        elif m and m.group(1) == "endif":
            depth -= 1
    return depth


def _balanced(lines) -> bool:
    """True if the lines hold no preprocessor directive, or only whole #if ... #endif blocks."""
    depth = 0
    for line in lines:
        m = _DIRECTIVE.match(line)
        if not m:
            continue
        kind = m.group(1)
        if kind in ("if", "ifdef", "ifndef"):
            depth += 1
        elif kind == "endif":
            depth -= 1
        elif depth == 0:  # elif/else/define/undef/include outside a block of its own
            return False
        if depth < 0:
            return False
    return depth == 0


@lru_cache(maxsize=8)
def _load(path: Path, mtime_ns: int) -> dict[str, tuple[re.Pattern[str], ...]]:
    table: dict[str, list[re.Pattern[str]]] = {}
    for number, raw in enumerate(path.read_text().splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 2:
            raise ValueError(f"{path}:{number}: expected <test>\\t<case-label regex>[\\t<reason>]")
        table.setdefault(fields[0], []).append(re.compile(fields[1]))
    return {test: tuple(patterns) for test, patterns in table.items()}


def load_exclude_cases(path: Path) -> dict[str, tuple[re.Pattern[str], ...]]:
    """Return test name -> case-label patterns from an exclude_cases_file."""
    return _load(path, path.stat().st_mtime_ns)


def drop_cases(source: str, patterns: tuple[re.Pattern[str], ...], test_name: str) -> tuple[str, list[str]]:
    """Remove the cases whose labels fully match a pattern; return the new source and the dropped labels."""
    lines = source.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if _LABEL.match(line)]
    drop = [False] * len(lines)
    dropped: list[str] = []
    for k, start in enumerate(starts):
        match = _LABEL.match(lines[start])
        assert match is not None
        label = match.group(1)
        if not any(p.fullmatch(label) for p in patterns):
            continue
        stop = starts[k + 1] if k + 1 < len(starts) else len(lines)
        ref = re.compile(re.escape(label) + r"\b")
        end = max(i for i in range(start, stop) if ref.search(lines[i]))
        span = list(range(start, end + 1))
        others = {m.removesuffix("_str") for i in range(start + 1, end + 1) for m in _REF.findall(lines[i])} - {label}
        if end == start or others or any(_MODE_SWITCH.search(lines[i]) for i in range(start + 1, end)):
            # Grouped cases: the instruction runs to the first blank line, the checks come later
            end = start
            while end + 1 < stop and lines[end + 1].strip() and not _DIRECTIVE.match(lines[end + 1]):
                end += 1
            span = list(range(start, end + 1))
            for i in range(end + 1, len(lines)):
                if ref.search(lines[i]):
                    if i > 0 and lines[i - 1].lstrip().startswith("# Check"):
                        span.append(i - 1)
                    span.append(i)
        # A check inside "#if __riscv_xlen == 32 ... #endif" ends the case before the #endif: take it too
        while _depth(lines[i] for i in sorted(span)) > 0 and span[-1] + 1 < len(lines) and span == list(range(start, span[-1] + 1)):
            span.append(span[-1] + 1)
        if not _balanced(lines[i] for i in sorted(span)):
            raise ValueError(f"{test_name}: case {label} spans an unbalanced preprocessor block; it cannot be dropped")
        for i in span:
            drop[i] = True
        dropped.append(label)
    return "".join(line for line, d in zip(lines, drop) if not d), dropped
