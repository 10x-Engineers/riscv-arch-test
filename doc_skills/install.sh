#!/usr/bin/env bash
# ACT4 doc_skills — universal plug-in installer (any agent / any IDE)
#
# Usage:
#   ./install.sh                         # show help
#   ./install.sh verify                  # sanity-check this pack
#   ./install.sh cursor                  # install skills+rules → ~/.cursor/
#   ./install.sh cursor /path/to/ACT4    # also wire project .cursor/ + copy vault/graphify if missing
#   ./install.sh link /path/to/ACT4      # symlink this pack → repo/.cursor/doc_skills (recommended for teams)
#   ./install.sh repo /path/to/ACT4      # link pack + install cursor + sync vault/graphify/handoffs into repo
#
set -euo pipefail

PACK="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-help}"
REPO="${2:-}"

die() { echo "ERROR: $*" >&2; exit 1; }

require_repo() {
  [[ -n "$REPO" ]] || die "repo path required. Example: $0 $CMD /path/to/ACT4"
  [[ -d "$REPO" ]] || die "repo path not found: $REPO"
  [[ -d "$REPO/riscv-arch-test" || -f "$REPO/AGENTS.md" ]] || \
    die "does not look like ACT4 root (need riscv-arch-test/ or AGENTS.md): $REPO"
}

install_cursor_user() {
  mkdir -p "$HOME/.cursor/skills" "$HOME/.cursor/rules"
  rsync -a "$PACK/skills/" "$HOME/.cursor/skills/"
  rsync -a "$PACK/rules/" "$HOME/.cursor/rules/"
  echo "✓ skills + rules → ~/.cursor/skills and ~/.cursor/rules"
}

install_cursor_project() {
  require_repo
  mkdir -p "$REPO/.cursor/skills" "$REPO/.cursor/rules"
  rsync -a "$PACK/skills/" "$REPO/.cursor/skills/"
  rsync -a "$PACK/rules/" "$REPO/.cursor/rules/"
  echo "✓ skills + rules → $REPO/.cursor/"
}

copy_repo_assets() {
  require_repo
  if [[ ! -d "$REPO/obsidian-vault/ACT4-riscv-arch-test" ]]; then
    mkdir -p "$REPO/obsidian-vault"
    rsync -a "$PACK/vaults/" "$REPO/obsidian-vault/"
    echo "✓ vaults → $REPO/obsidian-vault/"
  else
    echo "· vaults already present — skipped (run sync-from-repo.sh from maintainer to refresh)"
  fi
  if [[ ! -f "$REPO/graphify-out/GRAPH_REPORT.md" ]]; then
    mkdir -p "$REPO/graphify-out"
    rsync -a "$PACK/graphify-out/" "$REPO/graphify-out/"
    echo "✓ graphify-out → $REPO/graphify-out/"
  else
    echo "· graphify-out already present — skipped"
  fi
  if [[ -f "$REPO/riscv-arch-test/AI_CONTEXT_SUMMARY.md" ]]; then
    cp -a "$PACK/handoffs/AI_CONTEXT_SUMMARY.md" "$REPO/riscv-arch-test/AI_CONTEXT_SUMMARY.md"
    echo "✓ handoff → riscv-arch-test/AI_CONTEXT_SUMMARY.md"
  fi
  if [[ ! -f "$REPO/docs/DV-Monthly-AI-Agent-Stack-and-Testgen-Demo-Plan.md" ]]; then
    mkdir -p "$REPO/docs"
    cp -a "$PACK/TEAM_GUIDE.md" "$REPO/docs/DV-Monthly-AI-Agent-Stack-and-Testgen-Demo-Plan.md"
    echo "✓ TEAM_GUIDE → docs/DV-Monthly-…"
  fi
}

link_into_repo() {
  require_repo
  mkdir -p "$REPO/.cursor"
  local dest="$REPO/.cursor/doc_skills"
  if [[ -e "$dest" && ! -L "$dest" ]]; then
    die "$dest exists and is not a symlink — move it aside first"
  fi
  ln -sfn "$PACK" "$dest"
  echo "✓ linked $dest → $PACK"
}

verify_pack() {
  local ok=1
  for f in README.md TEAM_GUIDE.md HOW_TO_USE.md PLUGIN.md AGENTS.md skills/act4-testgen/SKILL.md \
           vaults/ACT4-riscv-arch-test/07-Known-Facts-Do-Not-Invent.md references/norm-rules.html; do
    if [[ -f "$PACK/$f" ]]; then
      echo "✓ $f"
    else
      echo "✗ missing: $f" >&2
      ok=0
    fi
  done
  if command -v node >/dev/null 2>&1; then
    node "$PACK/skills/unlazy/scripts/gate-check.mjs" --help >/dev/null 2>&1 && echo "✓ unlazy gate-check (node)" || echo "· unlazy needs node 16+"
  else
    echo "· node not found (optional; needed for unlazy gates only)"
  fi
  [[ "$ok" -eq 1 ]] || exit 1
  echo "Pack OK ($(cat "$PACK/.pack-version" 2>/dev/null || echo 'version unknown'))"
}

show_help() {
  cat <<EOF
ACT4 doc_skills plug-in — install for anyone

Pack: $PACK

Modes:
  verify              Check pack integrity (no writes)
  cursor              Install skills+rules to ~/.cursor/ (Cursor IDE)
  cursor <ACT4>       Also install into <ACT4>/.cursor/ + copy vault/graphify if missing
  link <ACT4>         Symlink pack → <ACT4>/.cursor/doc_skills (best for teams)
  repo <ACT4>         link + cursor user + project + copy assets

No IDE? Open this folder in any agent and read AGENTS.md or TEAM_GUIDE.md — no install needed.

See PLUGIN.md for Claude Code, Codex, Copilot, and copy-paste bootstrap prompts.
EOF
}

case "$CMD" in
  help|-h|--help) show_help ;;
  verify) verify_pack ;;
  cursor)
    install_cursor_user
    [[ -n "$REPO" ]] && install_cursor_project && copy_repo_assets
    echo "Done. Open Cursor; rules load from ~/.cursor/rules and project .cursor/rules."
    ;;
  link)
    link_into_repo
    echo "Done. Point agents at $REPO/.cursor/doc_skills/AGENTS.md"
    ;;
  repo)
    link_into_repo
    install_cursor_user
    install_cursor_project
    copy_repo_assets
    echo "Done. Full repo integration at $REPO"
    ;;
  *)
    die "unknown command: $CMD (try: ./install.sh help)"
    ;;
esac
