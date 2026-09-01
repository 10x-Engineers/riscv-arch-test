# Bootstrap prompts — copy into any agent

Paths assume the **doc_skills** folder is attached or on disk. Replace `DOC_SKILLS` with your path.

---

## Generic (any tool)

```text
DOC_SKILLS = <path to this folder>

Read in order:
1. DOC_SKILLS/AGENTS.md
2. DOC_SKILLS/vaults/ACT4-riscv-arch-test/07-Known-Facts-Do-Not-Invent.md
3. The skill for my task (see DOC_SKILLS/HOW_TO_USE.md)

Task: <describe work>

Rules: one workstream only; no invented Make flags; regenerate SvH .S don't patch;
norm IDs from DOC_SKILLS/references/norm-rules.html; update vault after durable changes.
```

---

## SvH testgen

```text
Read DOC_SKILLS/skills/act4-testgen/SKILL.md and DOC_SKILLS/docs/SvH-Implementation-Readme.md.
Plan What/Why/How must be approved before Python.

Task: <e.g. fix SvH_perm generator / add coverpoint case>

Code lives in riscv-arch-test/generators/testgen/.../SvH*.py (full repo required).
Run: make testgen EXTENSIONS=SvH EXCLUDE_EXTENSIONS=Sm
Do not edit tests/priv/SvH/*.S by hand.
```

---

## Sail / coverage

```text
Read DOC_SKILLS/skills/act4-riscv-arch-test/SKILL.md and handoffs/AI_CONTEXT_SUMMARY.md.

Pipeline: Sail --trace → *.trace → sail_to_rvvi.py → *.rvvi → vsim TB → covergroups.
TB reads *.rvvi only. Starter Questa cannot sample covergroups — do not claim UCDB without licensed vsim.
```

---

## Hypervisor xlsx / norms

```text
Read DOC_SKILLS/skills/act4-hypervisor/SKILL.md and vaults/ACT4-Hypervisor/00-MOC-Index.md.
Use references/norm-rules.html for canonical norm IDs.

Pipeline order (repo root):
  pdf-env/bin/python3 generate_hypervisor_norm_gaps.py
  pdf-env/bin/python3 generate_consolidated_updates.py
  pdf-env/bin/python3 generate_highlighted_xlsx.py
  pdf-env/bin/python3 fill_norm_rules_xlsx.py
```

---

## New teammate onboarding

```text
Welcome. Install:
  cd DOC_SKILLS && ./install.sh link /path/to/ACT4

Then read DOC_SKILLS/TEAM_GUIDE.md §2 FAQ and try Lab A–B (§8).
```

---

## Review SvH generator PR

```text
Review against SvH Test Generator Review feedback (12 items):
- SvHCommon: no delete_old_asm_files, goto_* fns, pte_bits, count_sigupds, sigupd_gpr/csr/labeled
- Use GOTO_* / PTE_* constants, register allocator, native write_sigupd
- SvH.py: explicit _emit per scenario (39 tests), no _SCENARIOS loop

Read commented generators: riscv-arch-test/generators/testgen/.../SvH*.py
Verify: make testgen EXTENSIONS=SvH
```
