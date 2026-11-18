#!/usr/bin/env python3
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

"""External agent brain driving an AX Task as isolated remote sandbox hands.

Demonstrates the decoupled Brain-Outside / Hands-in-Sandbox topology:
- The reasoning loop and real model credentials stay outside the sandbox.
- All code inspection, edits, and test execution happen inside `hands-sandbox`
  over `ax ssh`.
- Between turns, the external brain suspends the sandbox to checkpoint
  `/workspace` and free cluster compute, then resumes it seamlessly.
"""

import argparse
import base64
import subprocess
import time


def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
  print(f"$ {' '.join(cmd)}", flush=True)
  res = subprocess.run(cmd, text=True, capture_output=True)
  if res.stdout.strip():
    print(res.stdout.rstrip())
  if res.stderr.strip():
    print(res.stderr.rstrip())
  if check and res.returncode != 0:
    raise RuntimeError(f"command failed ({res.returncode}): {' '.join(cmd)}")
  return res


def ax(ax_bin: str, atespace: str, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
  return run([ax_bin, "-a", atespace, *args], check=check)


def main() -> None:
  parser = argparse.ArgumentParser(
      description="Drive an isolated AX Task as remote hands."
  )
  parser.add_argument(
      "--task", default="hands-sandbox", help="AX Task name acting as remote hands"
  )
  parser.add_argument("--atespace", default="default", help="AX atespace name")
  parser.add_argument("--ax-bin", default="ax", help="Path to ax CLI binary")
  args = parser.parse_args()

  task = args.task
  ns = args.atespace
  bin_ = args.ax_bin

  print("\n== Turn 1: External Brain starts remote hands and runs failing tests ==")
  ax(bin_, ns, "resume", "task", task)
  res = ax(
      bin_,
      ns,
      "ssh",
      task,
      "--",
      "python3",
      "-m",
      "unittest",
      "-v",
      "test_calc.py",
      check=False,
  )
  if res.returncode == 0:
    print("Tests already passed cleanly.")
    ax(bin_, ns, "suspend", "task", task)
    return

  print("\n== External Brain suspending sandbox while planning patch ==")
  ax(bin_, ns, "suspend", "task", task)
  time.sleep(2)

  print("\n== Turn 2: External Brain resumes sandbox with /workspace intact ==")
  ax(bin_, ns, "resume", "task", task)
  src_res = ax(bin_, ns, "ssh", task, "--", "cat", "/workspace/calc.py")
  patched = src_res.stdout.replace("if val < -1:", "if val < 0:").replace(
      "    # BUG: off-by-one allows negative -1 sentinel through\n", ""
  )
  b64_src = base64.b64encode(patched.encode("utf-8")).decode("ascii")
  ax(
      bin_,
      ns,
      "ssh",
      task,
      "--",
      "python3",
      "-c",
      f"import base64,pathlib; pathlib.Path('/workspace/calc.py').write_bytes(base64.b64decode('{b64_src}'))",
  )

  print("\n== Verify fix inside remote hands ==")
  ax(bin_, ns, "ssh", task, "--", "python3", "-m", "unittest", "-v", "test_calc.py")

  print("\n== Suspend sandbox to zero compute until the next user turn ==")
  ax(bin_, ns, "suspend", "task", task)
  ax(bin_, ns, "get", "tasks")


if __name__ == "__main__":
  main()
