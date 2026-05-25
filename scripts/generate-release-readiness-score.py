#!/usr/bin/env python3
"""Thin wrapper: delegates to the PowerShell release readiness generator."""
import subprocess
import sys
import os
import json

script_dir = os.path.dirname(os.path.abspath(__file__))
ps1 = os.path.join(script_dir, "generate-release-readiness-score.ps1")

args = ["pwsh", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1, "-Json"]
if "-markdown" in sys.argv or "--markdown" in sys.argv:
    md_path = os.path.join(script_dir, "..", "docs", "release-readiness-score.md")
    args.extend(["-OutputPath", md_path])

result = subprocess.run(args, capture_output=True, text=True, cwd=script_dir)
if result.stdout:
    print(result.stdout, end="")
if result.stderr:
    print(result.stderr, file=sys.stderr)
sys.exit(result.returncode)
