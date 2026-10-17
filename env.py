# Loads KEY=value lines from a .env file next to the scripts into os.environ.
# Variables already set in the terminal win over the file.

import os
from pathlib import Path


def load_env():
    path = Path(__file__).resolve().parent / ".env"
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("'\""))
