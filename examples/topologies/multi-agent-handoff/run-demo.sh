#!/usr/bin/env bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# End-to-end demo: Multi-Agent Handoff Across Trust Boundaries on AX.
#   bash examples/topologies/multi-agent-handoff/run-demo.sh          # interactive pauses
#   AUTO=1 bash examples/topologies/multi-agent-handoff/run-demo.sh   # non-interactive
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

AX_BIN=${AX_BIN:-ax}
ATESPACE=${ATESPACE:-default}
AUTO=${AUTO:-}
TIMEOUT=${AX_TIMEOUT:-120}

step() {
  printf '\n\033[1;34m== %s\033[0m\n' "$1"
  shift
  for l in "$@"; do printf '   \033[2m%s\033[0m\n' "$l"; done
  if [ -n "$AUTO" ]; then sleep "${STEP_WAIT:-2}"; else read -r -p "   (enter to run) " _; fi
}

show() { printf '\033[1;37m$ %s\033[0m\n' "$1"; }
ax_cmd() { show "$AX_BIN -a $ATESPACE $*"; "$AX_BIN" -a "$ATESPACE" "$@"; }

wait_for_file() {
  local task="$1"
  local path="$2"
  local deadline=$((SECONDS + TIMEOUT))
  while ((SECONDS < deadline)); do
    if "$AX_BIN" -a "$ATESPACE" ssh "$task" -- test -f "$path" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for $path in task $task" >&2
  return 1
}

step "1. One Workspace seed, one Gateway, two asymmetric Tasks" \
  "github-issue-triage binds github-egress (api.github.com allowed; secret injected outside the sandbox)." \
  "sandboxed-code-fixer has no Gateway attached (outbound network denied by default)."
show "sed -n '1,120p' manifest.yaml"

step "2. Apply Workspace, Gateway, and both suspended Tasks" \
  "ax apply creates resources in the initial Suspended state."
ax_cmd apply -f manifest.yaml
ax_cmd get workspaces
ax_cmd get gateways
ax_cmd get tasks

step "3. Resume github-issue-triage to reproduce the issue and write /workspace/triage-report.md" \
  "Then suspend github-issue-triage so it releases cluster compute."
ax_cmd resume task github-issue-triage
wait_for_file github-issue-triage /workspace/triage-report.md
ax_cmd ssh github-issue-triage -- cat /workspace/triage-report.md
REPORT_B64=$(
  "$AX_BIN" -a "$ATESPACE" ssh github-issue-triage -- \
    python3 -c 'import base64,pathlib; print(base64.b64encode(pathlib.Path("/workspace/triage-report.md").read_bytes()).decode())' \
    | tr -d '\r\n'
)
ax_cmd suspend task github-issue-triage

step "4. Resume air-gapped sandboxed-code-fixer and hand off /workspace/triage-report.md" \
  "sandboxed-code-fixer applies the fix, runs unit tests, and proves outbound egress is blocked."
ax_cmd resume task sandboxed-code-fixer
show "ax ssh sandboxed-code-fixer -- write /workspace/triage-report.md"
"$AX_BIN" -a "$ATESPACE" ssh sandboxed-code-fixer -- \
  python3 -c "import base64,pathlib; pathlib.Path('/workspace/triage-report.md').write_bytes(base64.b64decode('${REPORT_B64}'))"
wait_for_file sandboxed-code-fixer /workspace/fix-report.md
ax_cmd ssh sandboxed-code-fixer -- cat /workspace/fix-report.md

step "5. Suspend sandboxed-code-fixer and verify idle state"
ax_cmd suspend task sandboxed-code-fixer
ax_cmd get tasks

printf '\n\033[1;34m== Done: asymmetric egress policies, explicit workspace handoff, zero idle compute.\033[0m\n'
