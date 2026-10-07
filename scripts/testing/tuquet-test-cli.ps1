# ============================================================================
# TUQUET-CLOUD TEST PRESET CLI (POWERSHELL WRAPPER)
# Description: Delegates to Node.js CLI engine (DRY)
# ============================================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
node "$ScriptDir/tuquet-test-cli.mjs" @args
