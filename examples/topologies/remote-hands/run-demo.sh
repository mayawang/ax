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

# End-to-end demo: External Brain Driving Remote Sandbox Hands on AX.
#   bash examples/topologies/remote-hands/run-demo.sh          # interactive pauses
#   AUTO=1 bash examples/topologies/remote-hands/run-demo.sh   # non-interactive
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

AX_BIN=${AX_BIN:-ax}
ATESPACE=${ATESPACE:-default}
AUTO=${AUTO:-}

step() {
  printf '\n\033[1;34m== %s\033[0m\n' "$1"
  shift
  for l in "$@"; do printf '   \033[2m%s\033[0m\n' "$l"; done
  if [ -n "$AUTO" ]; then sleep "${STEP_WAIT:-2}"; else read -r -p "   (enter to run) " _; fi
}

show() { printf '\033[1;37m$ %s\033[0m\n' "$1"; }
ax_cmd() { show "$AX_BIN -a $ATESPACE $*"; "$AX_BIN" -a "$ATESPACE" "$@"; }

step "1. External Brain, Remote Hands: zero model credentials inside the Task" \
  "brain.py runs outside the sandbox and drives /workspace via ax ssh." \
  "hands-sandbox only holds ANTHROPIC_API_KEY=placeholder."
show "sed -n '1,120p' manifest.yaml"

step "2. Apply Gateway, Workspace, and hands-sandbox Task" \
  "AX creates hands-workspace and provisions hands-sandbox in Suspended state."
ax_cmd apply -f manifest.yaml
ax_cmd get gateways
ax_cmd get workspaces
ax_cmd get tasks

step "3. Run external brain loop (Turn 1 -> suspend -> Turn 2 -> verify -> suspend)" \
  "Notice /workspace state survives suspend and resume cleanly across turns."
show "python3 brain.py --ax-bin $AX_BIN --atespace $ATESPACE --task hands-sandbox"
python3 brain.py --ax-bin "$AX_BIN" --atespace "$ATESPACE" --task hands-sandbox

printf '\n\033[1;34m== Done: external brain outside, isolated tool execution inside, suspended between turns.\033[0m\n'
