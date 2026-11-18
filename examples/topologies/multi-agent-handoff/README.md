# Multi-Agent Handoff Across Trust Boundaries

This example shows two [AX](https://github.com/google/ax) `Task`s collaborating across different network and credential boundaries:

1. **Network-privileged Triage (`github-issue-triage`)**: Binds `github-egress`, an AX `Gateway` backed by Agent Substrate's `EgressPolicy`. Outbound HTTPS is restricted to `api.github.com`, and `effects.replaceHeaders` injects the real bearer token from a Kubernetes `Secret` outside the sandbox so the container only holds `GITHUB_TOKEN=placeholder`. It reproduces the failing test in `/workspace` and writes `/workspace/triage-report.md`.
2. **Air-gapped Fixer (`sandboxed-code-fixer`)**: Binds the same declarative `Workspace` (`repo-fixing-ws`) with **no `Gateway` attached**, denying all outbound network traffic by default. Once `/workspace/triage-report.md` is handed into its `/workspace`, it patches `calc.py`, verifies `test_calc.py` passes, confirms `https://api.github.com` is unreachable, and writes `/workspace/fix-report.md`.
3. **Checkpoint Between Stages (`ax suspend` / `ax resume`)**: Each `Task` checkpoints its `/workspace` state and releases cluster compute between handoff stages.

> **Workspace isolation note:** In `ax.io/v1alpha1` today, each `Task` initializes an isolated `/workspace` copy from `Workspace.spec.setup` and checkpoints that copy independently across suspend and resume. [`run-demo.sh`](run-demo.sh) transfers `/workspace/triage-report.md` explicitly over `ax ssh` between the triage and fixer sandboxes.

## Files

- [`manifest.yaml`](manifest.yaml): Declares `Workspace` (`repo-fixing-ws`), `Gateway` (`github-egress`), and two `Task`s (`github-issue-triage` and `sandboxed-code-fixer`).
- [`run-demo.sh`](run-demo.sh): Interactive (or `AUTO=1`) end-to-end walkthrough using `ax apply`, `ax resume`, `ax ssh`, and `ax suspend`.

## Prerequisites

1. **AX CLI and running stack**: Install `ax` and bring up either a local cluster (`ax local start`) or a remote Substrate `v1.0.0` cluster (`ax install`). See [`docs/local_installer.md`](../../../docs/local_installer.md).
2. **Default task image**: `manifest.yaml` omits `spec.profile.image` so tasks use `ax-server`'s digest-pinned `--default-task-image` (`python:3.12-slim` + `git` + `curl` + `ax-task-runner`). Alternatively, set a digest-pinned image explicitly under `spec.profile.image`.
3. **Optional GitHub token Secret** (for authenticated `api.github.com` header injection):

   ```bash
   kubectl -n ax-system create secret generic github-token --from-literal=token="<your-github-pat>"
   kubectl -n ax-system label secret github-token ax.io/credential=true
   ```

   `ax local start` and `ax install` grant atespace `default` access to secrets in `ax-system` labeled `ax.io/credential=true`. Without this secret, the `github-egress` proxy still blocks arbitrary hosts; the triage task records the returned HTTP status (`403` or `401` depending on gateway and upstream response) and continues to `/workspace/triage-report.md`.

## How to Run

### Option A: Automated Walkthrough Script

```bash
# Interactive mode (press Enter before each step)
bash examples/topologies/multi-agent-handoff/run-demo.sh

# Non-interactive mode
AUTO=1 bash examples/topologies/multi-agent-handoff/run-demo.sh
```

Override defaults with environment variables if needed (`AX_BIN=./bin/ax`, `ATESPACE=default`, `AX_TIMEOUT=120`).

### Option B: Step-by-Step `ax` Commands

```bash
# 1. Apply the Workspace, Gateway, and both Tasks (tasks start Suspended)
ax apply -f examples/topologies/multi-agent-handoff/manifest.yaml
ax get workspaces
ax get gateways
ax get tasks

# 2. Run Stage 1 (triage with github-egress) and inspect its output
ax resume task github-issue-triage
ax ssh github-issue-triage -- cat /workspace/triage-report.md

# 3. Hand off the triage artifact to Stage 2, then suspend Stage 1
REPORT_B64=$(ax ssh github-issue-triage -- python3 -c 'import base64,pathlib; print(base64.b64encode(pathlib.Path("/workspace/triage-report.md").read_bytes()).decode())' | tr -d '\r\n')
ax suspend task github-issue-triage

# 4. Resume Stage 2 (no Gateway attached), deliver the report, and inspect the fix
ax resume task sandboxed-code-fixer
ax ssh sandboxed-code-fixer -- python3 -c "import base64,pathlib; pathlib.Path('/workspace/triage-report.md').write_bytes(base64.b64decode('${REPORT_B64}'))"
ax ssh sandboxed-code-fixer -- cat /workspace/fix-report.md

# 5. Suspend Stage 2 to release idle compute
ax suspend task sandboxed-code-fixer
ax describe task sandboxed-code-fixer
```

## Cleanup

```bash
ax delete task sandboxed-code-fixer
ax delete task github-issue-triage
ax delete gateway github-egress
ax delete workspace repo-fixing-ws
```
