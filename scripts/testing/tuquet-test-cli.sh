#!/usr/bin/env bash

# ============================================================================
# TUQUET-CLOUD TEST PRESET CLI (POSIX BASH WRAPPER)
# Description: Delegates to Node.js CLI engine
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
node "${SCRIPT_DIR}/tuquet-test-cli.mjs" "$@"
