# ACT4 AI Agent Stack — Team Guide (test generation & DV)

> Same content as `.cursor/doc_skills/TEAM_GUIDE.md` (agent-agnostic pack).

# ACT4 AI Agent Stack — Team Guide

**Audience:** DV / ACT teammates and **any** coding agent (Cursor, Claude Code, Codex, Copilot, etc.)
**Purpose:** Use one named stack (skills, vaults, rules, Graphify) for test generation and coverage — not ad-hoc chat.
**Shareable pack:** [`.cursor/doc_skills/`](../.cursor/doc_skills/) — copy that folder; open its [`README.md`](../.cursor/doc_skills/README.md) and start.

| Doc in this pack | Role |
|------------------|------|
| [`HOW_TO_USE.md`](../.cursor/doc_skills/HOW_TO_USE.md) | 2-minute skill picker |
| [`EXTERNAL_LINKS.md`](../.cursor/doc_skills/EXTERNAL_LINKS.md) | norm-rules URL, sheets, tools |
| [`PATH_INDEX.md`](../.cursor/doc_skills/PATH_INDEX.md) | Full path catalog (not repeated below) |
| [`TEAM_GUIDE.md`](../.cursor/doc_skills/TEAM_GUIDE.md) | This guide |

**With a full ACT4 checkout also see:** `AI_TOOLING.md` · root `AGENTS.md`.

**Agent bootstrap (any tool):** Read this guide → pick one workstream skill under `skills/` → read the matching vault note → then act. Point your agent at this folder as context; no IDE-specific setup required.

---

## 1. Idea (30 seconds)

Don’t use a bare chatbot with no project memory. This pack is a **named stack** any agent can load:

1. **Map** — `graphify-out/GRAPH_REPORT.md` or `graphify explain "…"`
2. **Remember** — Obsidian vault + `handoffs/AI_CONTEXT_SUMMARY.md`
3. **Contract** — `handoffs/*AGENTS*` + standing rules in `rules/`
4. **Playbook** — load one skill under `skills/`
5. **Generate** — Python → `make testgen` (never hand-edit generated `.S`)
6. **Run** — Sail → `*.rvvi` → coverage (licensed Questa for UCDB)
7. **Prove** — unlazy gates / Sail logs
8. **Write memory** — update vault + handoff in the same session

**Result:** fewer invented Make flags, Tracefile keys, and norm IDs — plus reviewable Plan / Walkthrough / 39 SvH tests.

---

## 2. FAQ

| Question | Answer |
|----------|--------|
| What skill for my task? | §3 · or [`HOW_TO_USE.md`](../.cursor/doc_skills/HOW_TO_USE.md) |
| How do I add an SvH test? | Skill **`act4-testgen`** → edit Python → `make testgen EXTENSIONS=SvH` |
| New sheet from xlsx/csv? | **§5.2** — `explore` → main Plan → user OK → `generalPurpose` → `shell` → Walkthrough |
| Plan vs Walkthrough? | **Plan first**. Walkthrough **after** generators exist |
| Sail / coverage? | Skill **`act4-riscv-arch-test`**; TB reads `*.rvvi`, not `*.trace` |
| Norms ↔ coverpoints? | Skill **`act4-hypervisor`** + [`references/norm-rules.html`](../.cursor/doc_skills/references/norm-rules.html) ([online](../.cursor/doc_skills/EXTERNAL_LINKS.md)) |
| Edit `tests/priv/SvH/*.S` by hand? | **No** — regenerate |
| Quality today? | §7 — 39 tests, ~99.7% on licensed host (VSBE = Sail hole) |
| Agent invents commands? | Vault `07-Known-Facts` + `handoffs/AI_CONTEXT_SUMMARY.md` |
| Lost in repo? | `graphify-out/GRAPH_REPORT.md` |
| Every path? | [`PATH_INDEX.md`](../.cursor/doc_skills/PATH_INDEX.md) |
| Share with a teammate? | Copy **this whole folder** |

---

## 3. Workstreams, skills, helpers (once)

### 3.1 Workstreams — pick **one**

| Workstream | Skill | Vault (in pack) |
|------------|-------|-----------------|
| Generate / fix tests | `act4-testgen` | `vaults/ACT4-riscv-arch-test/` |
| Sail + coverage | `act4-riscv-arch-test` | same |
| Hypervisor xlsx / norms | `act4-hypervisor` | `vaults/ACT4-Hypervisor/` |
| Upstream RVVI (read-only) | `rvvi` | vault `09-RVVI-Clone.md` |

Contracts in pack: `handoffs/ROOT-AGENTS.md`, `handoffs/riscv-arch-test-AGENTS.md`.

### 3.2 Skills that matter daily

| Skill | When |
|-------|------|
| **`act4-testgen`** | Spec → Plan What/Why/How → Python → `make testgen` → coverpoints |
| **`act4-riscv-arch-test`** | ELF / Sail / `.rvvi` / Questa — no fake “coverage passed” |
| **`act4-hypervisor`** | xlsx, `norm-rules.html`, gap scripts |
| **`rvvi`** | Upstream RVVI only until team wires ACT4 |
| **`unlazy`** | Big work: `GATES.md` + `gate-check.mjs` |
| Process skills | Plan, TDD, debug, review — under `skills/` |

One conversation; skills are playbooks the agent reads — not separate products.

### 3.3 Parallel / focused helpers (optional)

Some IDEs can spawn focused child sessions. If yours can, use this pattern; if not, do the same steps in one session:

| Role | Job | Example |
|------|-----|---------|
| **Read / orient** | Search repo, report back | Find `generate_*` ↔ coverpoints |
| **Implement** | Write generators / docs | Add `generate_foo`, register `_SCENARIOS` |
| **Run / debug** | Shell + logs | `make testgen EXTENSIONS=SvH` |
| **Review** | Diff review | Uncommitted generator changes |

**Typical testgen:** read → implement → run.
**Parallel unrelated bugs:** skill `dispatching-parallel-agents`.
**One plan, many steps:** skill `subagent-driven-development`.

*(Cursor names for those roles, if you use Cursor: `explore`, `generalPurpose`, `shell`, `bugbot`, plus optional `security-review`, `ci-investigator`, `cursor-guide`, `best-of-n-runner`.)*

### 3.4 Stack pieces

| Piece | In this pack | Why |
|-------|--------------|-----|
| Obsidian vaults | `vaults/` | Facts survive chats |
| Skills | `skills/` | Right workflow |
| Standing rules | `rules/` | Hard don’ts (markdown playbooks any agent can read) |
| AGENTS / handoffs | `handoffs/` | Entry contract + living facts |
| Graphify | `graphify-out/` | Repo map |
| unlazy | `skills/unlazy/` + `rules/unlazy-default.mdc` | Evidence before “done” |
| Norms / spec | `references/` | Offline IDs + ISA text |

---

## 4. Hard behaviors

| Do | Prevents |
|----|----------|
| Read skill + vault before coding | Invented Make / Tracefile keys |
| One workstream at a time | Mixing xlsx scripts with `make coverage` |
| Regenerate `.S`, don’t patch | CI drift |
| No UCDB claim without licensed sim | Fake coverage on Starter Questa |
| unlazy gates on big tasks | “Done” without evidence |
| Update vault after real changes | Re-teaching Sail / GCC every chat |
| Canonical norms only | Fake `norm:csr:*:reg` IDs |

---

## 5. Test generation (end-to-end)

### 5.1 Three documents

| Phase | Deliverable | Gate |
|-------|-------------|------|
| **1 — Plan** | `<Suite>-Testgen-Plan.md` + Implementation Readme | **What / Why / How per test** → **user approves** before Python. Template: [`docs/SvH-Implementation-Readme.md`](../riscv-arch-test/docs/SvH-Implementation-Readme.md) |
| **2 — Code** | `generators/.../<Suite>*.py` (in full repo) | `make testgen` |
| **3 — Walkthrough** | `<Suite>_Testgen_Codebase_Walkthrough.md` | After generators + `.S` validate |

**SvH docs in pack:** [`docs/SvH-Testgen-Plan.md`](../riscv-arch-test/docs/SvH-Testgen-Plan.md) · [`docs/SvH-Implementation-Readme.md`](../riscv-arch-test/docs/SvH-Implementation-Readme.md) · [`docs/SvH_Testgen_Codebase_Walkthrough.md`](../riscv-arch-test/docs/SvH_Testgen_Codebase_Walkthrough.md).

**Norms / sheet exports:** [`references/`](../.cursor/doc_skills/references/) · live URLs in [`EXTERNAL_LINKS.md`](../.cursor/doc_skills/EXTERNAL_LINKS.md).

### 5.2 New suite from xlsx/csv — agent + sub-agent playbook

**When:** someone adds or refreshes a sheet like `Hypervisor (10x) - Gap Highlighted.xlsx` / `.csv` and you need a **new or extended** priv suite.

```text
  INPUT: Gap Highlighted.xlsx (+ .csv export) + norm-rules.html + riscv-spec.md
           │
           ▼
  ┌─ explore sub-agent ─────────────────────────────────────────┐
  │  Read sheet rows (cp_*), norm cols, existing hypervisor-10x │
  │  export; grep repo for already-covered stems                │
  │  Skills: act4-hypervisor, act4-testgen/reuse-map.md         │
  └───────────────────────────┬─────────────────────────────────┘
                              ▼
  ┌─ main agent + act4-hypervisor ─────────────────────────────────┐
  │  Map coverpoint → directed test(s); count cases; pick family   │
  │  file (twostage / csr / perm / fault / misc pattern)           │
  │  Rules: hypervisor-10x-act4.mdc, act4-project-bootstrap.mdc    │
  └───────────────────────────┬────────────────────────────────────┘
                              ▼
  ┌─ main agent + writing-plans + unlazy ──────────────────────────┐
  │  WRITE Phase 1: riscv-arch-test/docs/<Suite>-Testgen-Plan.md   │
  │  (+ Implementation Readme: What/Why/How per test)              │
  │  One section per planned test: What/Why/How, cp_*, case #      │
  │  Gate: GATES.md row "Plan reviewed by user" = PENDING          │
  └───────────────────────────┬────────────────────────────────────┘
                              ▼
                    ⛔ USER REVIEWS PLAN — NO PYTHON YET
                              │
                    (user approves or edits plan doc)
                              ▼
  ┌─ generalPurpose sub-agent + act4-testgen ───────────────────────┐
  │  WRITE Phase 2: generators/testgen/.../extensions/<Suite>*.py   │
  │  Register _SCENARIOS; reuse *Common.py; SPDX headers            │
  │  Comments: plain-English; match nearest SvH family              │
  └───────────────────────────┬─────────────────────────────────────┘
                              ▼
  ┌─ shell sub-agent + act4-riscv-arch-test ───────────────────────┐
  │  make testgen → make elfs → Sail; fix generator failures       │
  │  Edit coverpoints/priv/<Suite>_coverage.svh if new bins        │
  └───────────────────────────┬────────────────────────────────────┘
                              ▼
  ┌─ main agent (or generalPurpose) ───────────────────────────────┐
  │  WRITE Phase 3: docs/<Suite>_Testgen_Codebase_Walkthrough.md   │
  │  Per-test: Python refs, asm spine, coverpoint map, deps        │
  │  Style: SvH walkthrough T01–T39 (What/Why/How + code cites)    │
  └───────────────────────────┬────────────────────────────────────┘
                              ▼
  Update vault + AI_CONTEXT_SUMMARY.md
                              │
                    (optional) ▼
  ┌─ bugbot sub-agent ─────────────────────────────────────────────┐
  │  Review generator / coverpoint diff before merge               │
  │  Skill: requesting-code-review                                 │
  └────────────────────────────────────────────────────────────────┘
```

**Sub-agent cheat sheet for this flow:**

| Step | Sub-agent / who | Skills / rules |
|------|-----------------|----------------|
| Read sheet + repo overlap | **`explore`** | `act4-hypervisor`, `act4-testgen`, Graphify optional |
| Map cp → family / case count | **main** + `act4-hypervisor` | `hypervisor-10x-act4.mdc`, `act4-project-bootstrap.mdc` |
| Draft Plan + What/Why/How | **main** | `writing-plans`, `brainstorming`, `unlazy` |
| ⛔ Human | **user** | Approve Plan — **no Python yet** |
| Implement Python | **`generalPurpose`** | `act4-testgen`, `test-driven-development` |
| Run Make / debug Sail | **`shell`** | `act4-riscv-arch-test`, `systematic-debugging` |
| Walkthrough doc | **main** or **`generalPurpose`** | `act4-testgen`, `svh-code-explainer` tone |
| Vault / handoff | **main** | memory protocol |
| Review diff (optional) | **`bugbot`** | `requesting-code-review` |

**One line:** `explore` → main (map + Plan) → **user OK** → `generalPurpose` → `shell` → Walkthrough → vault → (opt) `bugbot`.

**Hard stop:** If the user has not approved the **Plan doc**, the agent must not write suite Python or claim testgen complete.
**Template:** [`docs/SvH-Implementation-Readme.md`](../riscv-arch-test/docs/SvH-Implementation-Readme.md).

If your tool has **no** sub-agents: same boxes, all done by the main agent — names above are the preferred split when helpers exist.

### 5.3 Comments

Plain-English in Python and emitted `// Test case N:` banners. Tone guide: `rules/svh-code-explainer.mdc`.

### 5.4 Day-to-day (small fix)

Graphify (optional) → AGENTS/rules → vault/handoff → Plan catalog → **`act4-testgen`** → `make testgen` → **`act4-riscv-arch-test`** → edit `coverpoints/priv` only → update Walkthrough if needed → update vault.

---

## 6. Hypervisor xlsx pipeline (full repo)

```bash
pdf-env/bin/python3 generate_hypervisor_norm_gaps.py
pdf-env/bin/python3 generate_consolidated_updates.py
pdf-env/bin/python3 generate_highlighted_xlsx.py
pdf-env/bin/python3 fill_norm_rules_xlsx.py
```

Edit `GOLDEN` + `PLACEMENT` + `CP_NORMS` / `NORM_ALIASES` together. Skill: `skills/act4-hypervisor/`.

---

## 7. Quality today (SvH)

| Artifact | Proof |
|----------|--------|
| 39 `SvH_*-00.S` | `make testgen EXTENSIONS=SvH` reproduces |
| Python generators | `_SCENARIOS` in `SvH.py` (full repo) |
| Covergroup | `coverpoints/priv/SvH_coverage.svh` |
| Coverage (licensed) | ~99.66% RV32 / ~99.71% RV64; VSBE open (Sail) |

**Limits:** Starter Questa = no covergroup sampling · RVVI skill = read-only until wired · human judgment for new suite names / trap handler / ambiguous WARL.

---

## 8. Try it (~5–15 min each)

| Lab | Steps |
|-----|--------|
| **A Orient** | `handoffs/ROOT-AGENTS.md` → `vaults/.../07-Known-Facts-Do-Not-Invent.md` → `graphify-out/GRAPH_REPORT.md` |
| **B Testgen** | `skills/act4-testgen/SKILL.md` → (in full repo) `SvH.py` → one `.S` → Walkthrough chapter → `make testgen EXTENSIONS=SvH EXCLUDE_EXTENSIONS=Sm JOBS=1` |
| **C Memory** | `handoffs/AI_CONTEXT_SUMMARY.md` → new session: “read handoff + vault first” |
| **D Gates** | Copy `skills/unlazy/templates/gates-leaf.md` → `GATES.md` → `node skills/unlazy/scripts/gate-check.mjs --status GATES.md` |

---

## 9. Why not raw prompting

Grounding (vault/rules) · regenerable `.S` · separated skills · reuse-map · evidence (unlazy/Sail/UCDB) · reviewable Walkthrough · open tooling ([`EXTERNAL_LINKS.md`](../.cursor/doc_skills/EXTERNAL_LINKS.md)).

---

## 10. Cheat sheet

| Layer | One line |
|-------|----------|
| Pack | Copy this folder; tell any agent to read `TEAM_GUIDE.md` + one skill |
| Map | `graphify-out/GRAPH_REPORT.md` |
| Memory | `vaults/` + `handoffs/AI_CONTEXT_SUMMARY.md` |
| Contract | `handoffs/*AGENTS*` + `rules/` |
| Domain | `act4-testgen` / `act4-riscv-arch-test` / `act4-hypervisor` |
| Flow | read → implement → run / prove |
| Proof | `.rvvi` + licensed coverage / gates |
| Paths | [`PATH_INDEX.md`](../.cursor/doc_skills/PATH_INDEX.md) |

---

## 11. Paths

Full catalog: [`PATH_INDEX.md`](../.cursor/doc_skills/PATH_INDEX.md) (not duplicated here).

Live generators and Make need a full **ACT4 / `riscv-arch-test`** checkout — this pack is the **agent stack + memory + docs**, not a replacement for the source tree.
