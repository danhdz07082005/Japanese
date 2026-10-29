"""Asset management and content-addressable hash cache-busting for static files."""
import hashlib
from pathlib import Path
from backend.core.config import STATIC_DIR

_asset_hashes: dict[str, str] = {}


def get_asset_hash(file_path: Path) -> str:
    """Computes a content digest (SHA-256 first 10 characters) cached by mtime."""
    if not file_path.is_file():
        return "0"
    try:
        stat = file_path.stat()
        cache_key = f"{file_path}_{stat.st_mtime_ns}"
        if cache_key in _asset_hashes:
            return _asset_hashes[cache_key]

        digest = hashlib.sha256(file_path.read_bytes()).hexdigest()[:10]
        _asset_hashes[cache_key] = digest
        return digest
    except OSError:
        return "0"


def static_url(rel_path: str) -> str:
    """Generates an automatically versioned static URL using file content digest."""
    clean_path = rel_path.lstrip("/")
    file_path = STATIC_DIR / clean_path
    version = get_asset_hash(file_path)
    return f"/static/{clean_path}?v={version}"
