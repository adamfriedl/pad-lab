"""Load pad-lab/.env into os.environ (stdlib only, no python-dotenv)."""

import os
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
_LOADED = False


def load_dotenv(path: Path | None = None) -> None:
    """Load KEY=VALUE lines from .env. Existing env vars are not overwritten."""
    global _LOADED
    if _LOADED:
        return

    env_file = path or (_ROOT / ".env")
    if not env_file.is_file():
        _LOADED = True
        return

    for raw in env_file.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        key, sep, value = line.partition("=")
        if not sep:
            continue
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value

    _LOADED = True
