# Execution Topologies on AX

Runnable examples showing how to separate reasoning, credentials, network access, and sandboxed tool execution with [AX](https://github.com/google/ax) (`ax.io/v1alpha1`) and Agent Substrate.

| Example | Topology | Key primitives |
|---|---|---|
| [`remote-hands/`](remote-hands/README.md) | External reasoning loop driving an isolated sandbox over `ax ssh` | `Gateway` with host-side `replaceHeaders`, `Task` with `spec.debug: true`, `ax suspend` and `ax resume` between turns |
| [`multi-agent-handoff/`](multi-agent-handoff/README.md) | Network-privileged triage agent handing artifacts to an air-gapped fixer | Two `Task`s sharing one `Workspace` seed, `Gateway` bound only to triage, explicit artifact handoff |

## Prerequisites

Install the `ax` CLI and start a local cluster with `ax local start`, or target an existing cluster with `ax install`. See [`docs/local_installer.md`](../../docs/local_installer.md) for setup details.
