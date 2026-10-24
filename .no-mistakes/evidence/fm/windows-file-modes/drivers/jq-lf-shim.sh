#!/usr/bin/env bash
# Isolates the native jq.exe CRLF issue: same jq, LF output.
exec /c/Users/amfne/AppData/Local/Microsoft/WinGet/Links/jq -b "$@"
