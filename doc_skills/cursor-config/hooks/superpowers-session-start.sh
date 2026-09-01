#!/usr/bin/env bash
# Project wrapper: inject Superpowers bootstrap on every Cursor agent session.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../superpowers" && pwd)"
export CURSOR_PLUGIN_ROOT="$ROOT"
exec bash "$ROOT/hooks/session-start"
