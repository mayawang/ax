# Decoupled Brain and Remote Hands

This example demonstrates the **Brain Outside, Hands in Sandbox** execution topology on [AX](https://github.com/google/ax) and Agent Substrate:

1. **External Brain ([`brain.py`](brain.py))**: Runs outside the execution sandbox (on your laptop, in a control-plane pod, or in an external orchestrator). It plans each step and dispatches tool calls remotely.
2. **Remote Hands Sandbox (`hands-sandbox` `Task`)**: An isolated Agent Substrate sandbox initialized from `hands-workspace`. Because `spec.debug: true` is set, it serves the AX guest daemon over `ax ssh` so the external brain can inspect files, apply edits, and run tests without holding real model credentials inside the container (`ANTHROPIC_API_KEY` is only a placeholder).
3. **Egress Policy (`hands-egress` `Gateway`)**: Restricts outbound HTTPS from the sandbox (`github.com`, `api.github.com`, `*.githubusercontent.com`, and `api.anthropic.com` with host-side `replaceHeaders` injection from `ate-secret://...`).
4. **Suspend and Resume Across Turns**: When the external brain pauses between turns (`ax suspend task hands-sandbox`), Agent Substrate checkpoints `/workspace` and frees cluster compute until `ax resume task hands-sandbox` restores the workspace intact.

## Files

- [`manifest.yaml`](manifest.yaml): Declares `Gateway` (`hands-egress`), `Workspace` (`hands-workspace`), and `Task` (`hands-sandbox`).
- [`brain.py`](brain.py): External loop that runs tests over `ax ssh`, suspends between turns, resumes with `/workspace` preserved, applies the patch, and verifies tests pass.
- [`run-demo.sh`](run-demo.sh): Interactive (or `AUTO=1`) end-to-end walkthrough script.

## Prerequisites

1. **AX CLI and running stack**: Install `ax` and start either a local cluster (`ax local start`) or a remote Substrate `v1.0.0` cluster (`ax install`). See [`docs/local_installer.md`](../../../docs/local_installer.md).
2. **Default task image**: `manifest.yaml` omits `spec.profile.image` so `hands-sandbox` uses `ax-server`'s digest-pinned `--default-task-image` (`python:3.12-slim` + `git` + `curl` + `ax-task-runner`). Alternatively, set a digest-pinned image explicitly under `spec.profile.image`.
3. **Python 3** locally to run `brain.py`.
4. **Optional API secret** (if calling `api.anthropic.com` through `hands-egress`):

   ```bash
   kubectl -n ax-system create secret generic anthropic-creds --from-literal=api-key="sk-ant-..."
   kubectl -n ax-system label secret anthropic-creds ax.io/credential=true
   ```

## How to Run

### Option A: End-to-End Script

```bash
# Interactive mode (press Enter before each step)
bash examples/topologies/remote-hands/run-demo.sh

# Non-interactive mode
AUTO=1 bash examples/topologies/remote-hands/run-demo.sh
```

Override defaults with `AX_BIN=./bin/ax` and `ATESPACE=default`.

### Option B: Manual Steps

```bash
# 1. Provision Gateway, Workspace, and suspended Task
ax apply -f examples/topologies/remote-hands/manifest.yaml
ax get tasks

# 2. Drive the remote sandbox from outside using brain.py
python3 examples/topologies/remote-hands/brain.py --task hands-sandbox
```

## Cleanup

```bash
ax delete task hands-sandbox
ax delete gateway hands-egress
ax delete workspace hands-workspace
```
