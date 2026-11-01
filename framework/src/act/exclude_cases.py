"""Per-DUT test-case exclusion: drop named cases from a test source before it is built.

A DUT config can name an exclude_cases_file: tab-separated lines of test name, case-label regex and
reason (# comments and blank lines ignored). Each matching case is removed from that test's source, so
the reference model and the DUT both run the test without it. Used for cases that stop at a known
hardware deviation, so the rest of the test still runs on the board.

A case runs from its "<group>_cg_cp_<bin>:" label to the last line before the next case label that
names it (the instruction and its signature checks). Setup before the label and restores after the
checks stay.
"""

import re
from functools import lru_cache
from pathlib import Path

_LABEL = re.compile(r"^(\w+_cg_cp_\w+):\s*$")
# Preprocessor lines only: "# comment" lines in assembly are not directives.
_DIRECTIVE = re.compile(r"^\s*#\s*(if|ifdef|ifndef|elif|else|endif|define|undef|include)\b")


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
        if any(_DIRECTIVE.match(lines[i]) for i in range(start, end + 1)):
            raise ValueError(f"{test_name}: case {label} spans a preprocessor line; it cannot be dropped")
        for i in range(start, end + 1):
            drop[i] = True
        dropped.append(label)
    return "".join(line for line, d in zip(lines, drop) if not d), dropped
