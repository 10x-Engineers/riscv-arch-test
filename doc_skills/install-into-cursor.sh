#!/usr/bin/env bash
# Legacy wrapper — prefer ./install.sh (see PLUGIN.md)
exec "$(cd "$(dirname "$0")" && pwd)/install.sh" cursor "$@"
