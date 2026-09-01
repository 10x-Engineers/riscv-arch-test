#!/usr/bin/env bash
# Maintainer: refresh doc_skills pack from a live ACT4 checkout.
#
# Usage (from anywhere):
#   ./sync-from-repo.sh /path/to/ACT4
#
set -euo pipefail

PACK="$(cd "$(dirname "$0")" && pwd)"
REPO="${1:-}"

if [[ -z "$REPO" || ! -d "$REPO" ]]; then
  echo "Usage: $0 /path/to/ACT4" >&2
  exit 1
fi

echo "Refreshing pack from: $REPO"
echo "Pack: $PACK"

# Domain skills + unlazy + rvvi
for skill in act4-testgen act4-riscv-arch-test act4-hypervisor rvvi unlazy; do
  if [[ -d "$REPO/.cursor/skills/$skill" ]]; then
    rsync -a --delete "$REPO/.cursor/skills/$skill/" "$PACK/skills/$skill/"
    echo "✓ skills/$skill"
  fi
done

# Process skills (superpowers) — follow symlinks
if [[ -d "$REPO/.cursor/skills" ]]; then
  for skill in brainstorming writing-plans executing-plans test-driven-development \
    systematic-debugging subagent-driven-development dispatching-parallel-agents \
    verification-before-completion requesting-code-review receiving-code-review \
    finishing-a-development-branch using-git-worktrees using-superpowers writing-skills; do
    src="$REPO/.cursor/skills/$skill"
    if [[ -d "$src" || -L "$src" ]]; then
      rsync -aL --delete "$src/" "$PACK/skills/$skill/"
      echo "✓ skills/$skill"
    fi
  done
fi

# Rules
if [[ -d "$REPO/.cursor/rules" ]]; then
  rsync -a "$REPO/.cursor/rules/" "$PACK/rules/"
  echo "✓ rules/"
fi

# Vaults
if [[ -d "$REPO/obsidian-vault/ACT4-riscv-arch-test" ]]; then
  rsync -a --delete "$REPO/obsidian-vault/ACT4-riscv-arch-test/" "$PACK/vaults/ACT4-riscv-arch-test/"
  echo "✓ vaults/ACT4-riscv-arch-test/"
fi
if [[ -d "$REPO/obsidian-vault/ACT4-Hypervisor" ]]; then
  rsync -a --delete "$REPO/obsidian-vault/ACT4-Hypervisor/" "$PACK/vaults/ACT4-Hypervisor/"
  echo "✓ vaults/ACT4-Hypervisor/"
fi

# Graphify (exclude cache)
if [[ -d "$REPO/graphify-out" ]]; then
  mkdir -p "$PACK/graphify-out"
  for f in GRAPH_REPORT.md graph.json manifest.json .graphify_root; do
    [[ -f "$REPO/graphify-out/$f" ]] && cp -a "$REPO/graphify-out/$f" "$PACK/graphify-out/"
  done
  echo "✓ graphify-out/ (no cache/)"
fi

# Handoffs
[[ -f "$REPO/AGENTS.md" ]] && cp -a "$REPO/AGENTS.md" "$PACK/handoffs/ROOT-AGENTS.md"
[[ -f "$REPO/riscv-arch-test/AGENTS.md" ]] && cp -a "$REPO/riscv-arch-test/AGENTS.md" "$PACK/handoffs/riscv-arch-test-AGENTS.md"
[[ -f "$REPO/riscv-arch-test/AI_CONTEXT_SUMMARY.md" ]] && cp -a "$REPO/riscv-arch-test/AI_CONTEXT_SUMMARY.md" "$PACK/handoffs/AI_CONTEXT_SUMMARY.md"
[[ -f "$REPO/riscv-arch-test/AI_TOOLING.md" ]] && cp -a "$REPO/riscv-arch-test/AI_TOOLING.md" "$PACK/handoffs/AI_TOOLING.md"
[[ -f "$REPO/PROJECT.md" ]] && cp -a "$REPO/PROJECT.md" "$PACK/handoffs/PROJECT.md"
echo "✓ handoffs/"

# Docs + references
mkdir -p "$PACK/docs" "$PACK/references"
for doc in SvH-Testgen-Plan.md SvH-Implementation-Readme.md SvH_Testgen_Codebase_Walkthrough.md SvH_REVIEW_WALKTHROUGH.md \
           DV-Monthly-AI-Agent-Stack-and-Testgen-Demo-Plan.md; do
  [[ -f "$REPO/docs/$doc" ]] && cp -a "$REPO/docs/$doc" "$PACK/docs/$doc"
  [[ -f "$REPO/riscv-arch-test/docs/$doc" ]] && cp -a "$REPO/riscv-arch-test/docs/$doc" "$PACK/docs/$doc"
done
[[ -f "$REPO/riscv-arch-test/SvH_REVIEW_WALKTHROUGH.md" ]] && cp -a "$REPO/riscv-arch-test/SvH_REVIEW_WALKTHROUGH.md" "$PACK/docs/"
[[ -f "$REPO/norm-rules.html" ]] && cp -a "$REPO/norm-rules.html" "$PACK/references/"
[[ -f "$REPO/riscv-spec.md" ]] && cp -a "$REPO/riscv-spec.md" "$PACK/references/"
[[ -f "$REPO/hypervisor-10x-test-plan.md" ]] && cp -a "$REPO/hypervisor-10x-test-plan."* "$PACK/references/" 2>/dev/null || true

# After syncing TEAM_GUIDE into docs/DV-Monthly-…, fix repo-relative links back to pack-local paths (see doc_skills/TEAM_GUIDE.md header).
cp -a "$PACK/TEAM_GUIDE.md" "$REPO/docs/DV-Monthly-AI-Agent-Stack-and-Testgen-Demo-Plan.md" 2>/dev/null || true
echo "✓ TEAM_GUIDE.md (pack canonical; monthly doc copy optional)"

date -Iseconds > "$PACK/.pack-version"
find "$PACK" -type f ! -path '*/graphify-out/graph.json' | sort > "$PACK/MANIFEST.txt"
echo "✓ MANIFEST.txt + .pack-version"
echo "Done."
