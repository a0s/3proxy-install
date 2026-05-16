#!/bin/bash
# Run the installer with stdin from ANSWERS_FILE and append a full session trace.
# Usage: run-traced.sh ANSWERS_FILE INSTALLER_SCRIPT
# Env: TRACE_LOG (default /tmp/3proxy-test-trace.log)

set -euo pipefail

ANSWERS_FILE="${1:?answers file required}"
INSTALLER_SCRIPT="${2:?installer script required}"
TRACE_LOG="${TRACE_LOG:-/tmp/3proxy-test-trace.log}"

trace_header() {
	{
		echo ""
		echo "======== $(date -Iseconds 2>/dev/null || date) ========"
		echo ">>> programmed input (${ANSWERS_FILE}):"
		nl -ba "${ANSWERS_FILE}" | sed 's/^/    /'
		echo ">>> input (hex, first 512 bytes):"
		head -c 512 "${ANSWERS_FILE}" | od -An -tx1 | head -20 | sed 's/^/    /'
		echo ">>> installer: ${INSTALLER_SCRIPT}"
		echo ">>> PATH: ${PATH}"
		echo "-------- live session --------"
	} >>"${TRACE_LOG}"
}

trace_header

run_plain() {
	exec 0<"${ANSWERS_FILE}"
	bash "${INSTALLER_SCRIPT}" 2>&1 | tee -a "${TRACE_LOG}"
}

run_with_script() {
	# -f = flush after each write (good for tail -f)
	script -q -f -a "${TRACE_LOG}" -c "exec 0<\"${ANSWERS_FILE}\"; bash \"${INSTALLER_SCRIPT}\""
}

if command -v script &>/dev/null; then
	run_with_script
else
	run_plain
fi
