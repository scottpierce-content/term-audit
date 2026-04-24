#!/usr/bin/env python3

import argparse
import csv
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_REPO_URL = "https://github.com/MicrosoftDocs/microsoft-style-guide.git"
DEFAULT_GLOSSARY_PATH = "product-style-guide-msft-internal/a_z_names_terms"
DEFAULT_LEARN_BASE = "https://learn.microsoft.com/en-us/product-style-guide-msft-internal/a_z_names_terms"
DEFAULT_GITHUB_BASE = "https://github.com/MicrosoftDocs/microsoft-style-guide/blob/main"


def require_git():
    if shutil.which("git") is None:
        print("ERROR: git is not installed or not on PATH.", file=sys.stderr)
        sys.exit(1)


def run(cmd, check=True):
    """Run a subprocess command and return stdout as text."""
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(f"Command failed ({p.returncode}): {' '.join(cmd)}\n{p.stderr}")
    return p.stdout


def ensure_repo(repo_url: str, local_path: Path, pull: bool = True):
    """Clone repo if missing; otherwise optionally pull."""
    if not local_path.exists():
        local_path.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", repo_url, str(local_path)])
    elif pull:
        run(["git", "-C", str(local_path), "pull"])


def parse_iso_to_utc(iso_str: str) -> str | None:
    """Convert ISO 8601 string (possibly ending in Z) to normalized UTC '...Z'."""
    if not iso_str:
        return None
    s = iso_str.strip()
    try:
        # Python's fromisoformat doesn't accept 'Z' directly; convert to +00:00
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            # Assume UTC if no tzinfo (unlikely with %cI)
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return None


def git_created_and_modified(repo_root: Path, repo_relative_path: str, follow: bool) -> dict:
    """
    Get created + last modified dates for a file via git history.

    We use:
      git log [--follow] --format=%cI -- <path>
