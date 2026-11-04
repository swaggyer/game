"""Prepare a source-only GitHub upload tree; never touches a remote repository.

Default source: E:/game/StarLanternIsland (inferred from this tool's location).
Default destination: E:/game/github_upload_staging.

Review the printed plan with --dry-run, then run without --dry-run to copy.
Root README/.gitignore/.git are owned by the publishing workflow and preserved.
This script never recursively deletes files, copies credentials, or bundles saves.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import sys
import tempfile
from typing import Iterable


SOURCE_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DESTINATION = SOURCE_ROOT.parent / "github_upload_staging"
MIB = 1024 * 1024
MANAGED_ROOTS = ("mobile_game", "source_models", "design_web/content", ".github")
GAME_FOLDERS = {"assets", "data", "scenes", "scripts", "shaders", "tests", "tools", "docs"}
GAME_TOP_FILES = {"project.godot", "export_presets.cfg", ".gitignore", "README.md", "打开手游工程.cmd"}
FORBIDDEN_DIRS = {
    ".git", ".godot", ".codex", ".agents", ".aws", ".ssh", ".build-toolchain",
    "__pycache__", ".pytest_cache", ".mypy_cache", ".gradle", "node_modules",
    "userdata", "user_data", "app_userdata", "cache", "caches", "logs",
    "references", "reference", "private", "private_photos", "privatephotos", "photos",
    "raw_photos", "user_photos", "原始照片", "参考照片", "个人照片", "旺仔image", "小馒头image",
}
FORBIDDEN_SUFFIXES = {
    ".exe", ".dll", ".pck", ".zip", ".7z", ".rar", ".tar", ".gz", ".xz",
    ".apk", ".aab", ".ipa", ".app", ".dmg", ".msi", ".pkg", ".pdb",
    ".pyc", ".pyo", ".tmp", ".bak", ".blend1", ".blend2", ".blend3",
    ".ctex", ".md5", ".dmp", ".pem", ".key", ".p12", ".pfx", ".jks",
    ".keystore", ".mobileprovision", ".cer", ".csr", ".heic", ".heif", ".dng",
}
PRIVATE_FILENAMES = {
    "auth.json", "credentials.json", "credential.json", "token.json", "tokens.json",
    "secrets.json", "secrets.toml", "export_credentials.cfg", "debug.keystore",
    "campaign.json", "campaign.json.world.json", "stage_checkpoint.json",
}
TEXT_SUFFIXES = {
    ".gd", ".gdshader", ".tscn", ".tres", ".import", ".uid", ".py", ".ps1",
    ".cmd", ".cfg", ".md", ".txt", ".json", ".html", ".yml", ".yaml", ".xml",
    ".csv", ".css", ".js", ".svg", ".gitignore", ".gitattributes", ".gdignore",
}
KEEP_SCREENSHOTS = {
    "v121-hud-fixed.png", "v121-packed-gameplay.png", "v12-village.png",
    "v12-main-course.png", "v12-forest-challenge.png", "v12-map.png",
    "v12-portraits-hud.png",
}
KEEP_VALIDATION_LOGS = {
    "v121-package-integrity.log", "v121-native-packed.log", "v12-packed-verification.log",
}
SECRET_PATTERNS = {
    "private-key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "github-token": re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{40,})\b"),
    "aws-access-key": re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "embedded-signing-password": re.compile(rb'(?im)^\s*keystore/release_password\s*=\s*"[^"\r\n]+"'),
}


@dataclass(frozen=True)
class Candidate:
    source: Path
    relative: str
    size: int

    @property
    def binary(self) -> bool:
        return self.source.suffix.lower() not in TEXT_SUFFIXES and self.source.name not in {
            ".gitignore", ".gitattributes", ".gdignore", "LICENSE", "NOTICE", "OFL"
        }


def is_link(path: Path) -> bool:
    return path.is_symlink() or bool(getattr(path, "is_junction", lambda: False)())


def exclusion_reason(relative: PurePosixPath, is_directory: bool = False) -> str | None:
    """One shared policy for source selection and destination contamination checks."""
    parts = relative.parts
    lowered = tuple(part.casefold() for part in parts)
    name = lowered[-1] if lowered else ""
    if any(part in FORBIDDEN_DIRS for part in lowered):
        return "cache-private-reference-or-toolchain-directory"
    if name.startswith(".env") or name.startswith(("id_rsa", "id_ed25519")) or name in PRIVATE_FILENAMES:
        return "credential-or-local-save"
    if any(part in {"backups", "backup", "builds", "installers", "releases"} for part in lowered):
        return "build-or-backup"
    if len(parts) >= 2 and parts[0] == "mobile_game":
        if len(parts) == 2 and not is_directory and parts[1] not in GAME_TOP_FILES:
            return "unselected-project-root-file"
        if len(parts) >= 2 and is_directory and parts[1] not in GAME_FOLDERS:
            return "unselected-project-directory"
        if len(parts) >= 3 and parts[1] == "tests":
            if is_directory or len(parts) > 3:
                return "test-generated-data"
        if parts[:3] in {("mobile_game", "assets", "actions"), ("mobile_game", "assets", "locomotion_v12")}:
            if len(parts) >= 4 and parts[3] in {"raw", "source"}:
                return "raw-animation-intermediate"
        if len(parts) >= 3 and parts[1] == "docs" and not is_directory:
            doc_name = parts[-1].removesuffix(".import")
            allowed = (
                doc_name.endswith((".md", ".json"))
                or doc_name in KEEP_SCREENSHOTS
                or doc_name in KEEP_VALIDATION_LOGS
                or bool(re.fullmatch(r"v12-test_[A-Za-z0-9_]+\.log", doc_name))
            )
            if not allowed:
                return "historical-document-or-nonessential-log"
    if not is_directory:
        suffix = Path(name).suffix
        if suffix in FORBIDDEN_SUFFIXES:
            return "binary-release-cache-or-signing-material"
        if suffix == ".log":
            key_log = (
                parts[:2] == ("mobile_game", "docs")
                and (name in KEEP_VALIDATION_LOGS or re.fullmatch(r"v12-test_[a-z0-9_]+\.log", name))
            )
            if not key_log:
                return "nonessential-log"
        if "in-progress" in name:
            return "unfinished-generation-report"
    return None


def iter_selected(source: Path, excluded: Counter[str]) -> Iterable[Candidate]:
    for root_name in MANAGED_ROOTS:
        root = source / root_name
        if not root.exists():
            if root_name != ".github":
                raise ValueError(f"Required source directory does not exist: {root}")
            continue
        if is_link(root):
            raise ValueError(f"Source roots must be real directories, not links: {root}")
        for folder, directories, filenames in os.walk(root, followlinks=False):
            directory = Path(folder)
            keep_dirs = []
            for name in sorted(directories):
                path = directory / name
                relative = PurePosixPath(path.relative_to(source).as_posix())
                reason = "symbolic-link-or-junction" if is_link(path) else exclusion_reason(relative, True)
                if reason:
                    excluded[reason + " (directory)"] += 1
                else:
                    keep_dirs.append(name)
            directories[:] = keep_dirs
            for name in sorted(filenames):
                path = directory / name
                relative = PurePosixPath(path.relative_to(source).as_posix())
                reason = "symbolic-link-or-junction" if is_link(path) else exclusion_reason(relative)
                # Retain Godot import configuration only for an included source asset.
                if not reason and name.endswith(".import"):
                    original = path.with_suffix("")
                    original_relative = PurePosixPath(original.relative_to(source).as_posix())
                    if not original.is_file() or exclusion_reason(original_relative):
                        reason = "orphan-import-configuration"
                if reason:
                    excluded[reason] += 1
                    continue
                yield Candidate(path, relative.as_posix(), path.stat().st_size)
    # Godot's runtime notice is useful for release attribution even though the EXE is excluded.
    notice = source / "mobile_game/builds/GODOT-LICENSE.txt"
    if notice.is_file() and not is_link(notice):
        yield Candidate(notice, "third_party/licenses/GODOT-LICENSE.txt", notice.stat().st_size)


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def font_names(path: Path) -> list[str]:
    """Read family/license names from an sfnt font with only the standard library."""
    raw = path.read_bytes()
    if len(raw) < 12 or raw[:4] not in {b"\x00\x01\x00\x00", b"OTTO", b"true"}:
        return []
    count = struct.unpack_from(">H", raw, 4)[0]
    for index in range(count):
        tag, _, start, length = struct.unpack_from(">4sIII", raw, 12 + index * 16)
        if tag != b"name":
            continue
        block = raw[start:start + length]
        if len(block) < 6:
            return []
        _, entries, strings = struct.unpack_from(">HHH", block)
        names = []
        for number in range(entries):
            platform, _, _, name_id, size, offset = struct.unpack_from(">HHHHHH", block, 6 + number * 12)
            if name_id not in {1, 13, 14}:
                continue
            value = block[strings + offset:strings + offset + size]
            value = value.decode("utf-16-be" if platform in {0, 3} else "mac_roman", errors="replace")
            if value and value not in names:
                names.append(value)
        return names
    return []


def secret_findings(candidates: list[Candidate]) -> list[dict[str, str]]:
    findings = []
    for entry in candidates:
        if entry.binary or entry.size > 2 * MIB:
            continue
        payload = entry.source.read_bytes()
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(payload):
                findings.append({"path": entry.relative, "signature": label})
    return findings


def make_plan(source: Path, candidates: list[Candidate], excluded: Counter[str]) -> dict:
    groups: dict[str, dict[str, int]] = {}
    for entry in candidates:
        group = entry.relative.split("/")[0]
        stats = groups.setdefault(group, {"files": 0, "bytes": 0, "binary_files": 0, "binary_bytes": 0})
        stats["files"] += 1
        stats["bytes"] += entry.size
        if entry.binary:
            stats["binary_files"] += 1
            stats["binary_bytes"] += entry.size
    licenses = [entry.relative for entry in candidates if any(word in entry.source.name.casefold() for word in ("license", "licence", "copyright", "notice", "ofl"))]
    font = source / "mobile_game/assets/ui.ttf"
    font_metadata = font_names(font) if font.is_file() else []
    return {
        "format": 1,
        "source_name": source.name,
        "files": len(candidates),
        "bytes": sum(entry.size for entry in candidates),
        "binary_files": sum(entry.binary for entry in candidates),
        "binary_bytes": sum(entry.size for entry in candidates if entry.binary),
        "groups": groups,
        "largest_files": [{"path": entry.relative, "bytes": entry.size} for entry in sorted(candidates, key=lambda item: item.size, reverse=True)[:15]],
        "excluded_by_reason": dict(sorted(excluded.items())),
        "licenses": licenses,
        "font_metadata": font_metadata,
    }


def validate_destination(source: Path, destination: Path, candidates: list[Candidate], overwrite: bool) -> None:
    if destination == source or destination.is_relative_to(source) or source.is_relative_to(destination):
        raise ValueError("Destination must be a separate staging directory outside the source tree")
    if not destination.is_relative_to(source.parent):
        raise ValueError(f"Destination must remain inside the intended workspace: {source.parent}")
    for ancestor in [destination, *destination.parents]:
        if ancestor.exists() and is_link(ancestor):
            raise ValueError(f"Destination must not traverse a symbolic link or junction: {ancestor}")
        if ancestor == source.parent:
            break
    allowed = {entry.relative for entry in candidates}
    for root_name in MANAGED_ROOTS:
        root = destination / root_name
        if not root.exists():
            continue
        if is_link(root):
            raise ValueError(f"Existing managed root is a link: {root}")
        for path in root.rglob("*"):
            if is_link(path):
                raise ValueError(f"Existing destination contains a symbolic link: {path}")
            if path.is_file() and path.relative_to(destination).as_posix() not in allowed:
                raise ValueError(f"Existing destination has an unselected managed file; use a fresh staging folder: {path}")
    for entry in candidates:
        target = destination / entry.relative
        if target.exists() and not target.is_file():
            raise ValueError(f"Destination path is not a regular file: {target}")
        if target.is_file() and not overwrite and sha256(target) != sha256(entry.source):
            raise ValueError(f"Destination differs; use --overwrite to update selected files: {target}")


def copy_candidates(destination: Path, candidates: list[Candidate]) -> list[dict]:
    result = []
    for entry in candidates:
        target = destination / entry.relative
        target.parent.mkdir(parents=True, exist_ok=True)
        initial = entry.source.stat()
        source_hash = sha256(entry.source)
        if not target.is_file() or sha256(target) != source_hash:
            temporary_name = None
            try:
                with tempfile.NamedTemporaryFile(prefix=".repository-copy-", suffix=".tmp", dir=target.parent, delete=False) as stream:
                    temporary_name = Path(stream.name)
                shutil.copy2(entry.source, temporary_name)
                final = entry.source.stat()
                if initial.st_size != final.st_size or initial.st_mtime_ns != final.st_mtime_ns:
                    raise ValueError(f"Source changed during copy; retry after generation finishes: {entry.relative}")
                if sha256(temporary_name) != source_hash:
                    raise ValueError(f"Copy verification failed: {entry.relative}")
                os.replace(temporary_name, target)
                temporary_name = None
            finally:
                if temporary_name is not None and temporary_name.exists():
                    temporary_name.unlink()  # Only this invocation's exact temporary file.
        result.append({"path": entry.relative, "bytes": entry.size, "sha256": source_hash})
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE_ROOT)
    parser.add_argument("--destination", type=Path, default=DEFAULT_DESTINATION)
    parser.add_argument("--dry-run", action="store_true", help="Print the selected-file audit without creating a staging directory")
    parser.add_argument("--overwrite", action="store_true", help="Replace differing selected files; unrelated root README/.gitignore/.git remain untouched")
    parser.add_argument("--max-file-mib", type=float, default=90.0, help="Refuse a selected file above this conservative GitHub threshold")
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    destination = args.destination.resolve()
    if not (source / "mobile_game/project.godot").is_file():
        raise ValueError("Source must contain mobile_game/project.godot")
    excluded: Counter[str] = Counter()
    candidates = sorted(iter_selected(source, excluded), key=lambda entry: entry.relative)
    if not candidates:
        raise ValueError("No deliverable files selected")
    if args.max_file_mib <= 0:
        raise ValueError("--max-file-mib must be positive")
    large = [entry.relative for entry in candidates if entry.size > args.max_file_mib * MIB]
    if large:
        raise ValueError(f"Selected files exceed {args.max_file_mib:g}MiB; move release binaries out of Git or choose Git LFS explicitly: {large}")
    secrets = secret_findings(candidates)
    if secrets:
        raise ValueError("Potential credential signatures found (contents withheld): " + json.dumps(secrets))
    plan = make_plan(source, candidates, excluded)
    validate_destination(source, destination, candidates, args.overwrite)
    if args.dry_run:
        print(json.dumps({"dry_run": True, **plan}, ensure_ascii=False, indent=2))
        return 0
    destination.mkdir(parents=True, exist_ok=True)
    inventory = copy_candidates(destination, candidates)
    manifest = {**plan, "copied_files": inventory}
    report = destination / "repository_preparation_manifest.json"
    temporary_report = report.with_suffix(".json.tmp")
    temporary_report.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary_report, report)
    print(json.dumps({"destination": str(destination), "manifest": report.name, **plan}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, struct.error) as error:
        print(f"Repository preparation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
