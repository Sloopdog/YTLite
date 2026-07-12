#!/usr/bin/env python3
"""Generate ytlite's option catalog from a yt-dlp zipapp or source tree.

The parser is the source of truth.  This intentionally walks its option groups
instead of formatted help output because yt-dlp adds preset examples to the help
with temporary Option objects that are not real command-line options.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import optparse
import os
from pathlib import Path
import re
import sys
from typing import Any, Iterable


SCHEMA_VERSION = 1
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "ytlite/Resources/OptionCatalog.json"

EXEC_FLAGS = {
    "--downloader",
    "--exec",
    "--exec-before-download",
    "--external-downloader",
    "--ffmpeg-location",
    "--netrc-cmd",
}
PLUGIN_FLAGS = {
    "--plugin-dirs",
    "--use-postprocessor",
}
FILE_URL_FLAGS = {"--enable-file-urls"}
CERT_BYPASS_FLAGS = {"--no-check-certificates"}
SENSITIVE_CREDENTIAL_FLAGS = {
    "--username",
    "--ap-username",
    "--twofactor",
    "--add-headers",
    "--proxy",
    "--geo-verification-proxy",
    "--extractor-args",
    "--netrc-cmd",
    "--cookies",
    "--client-certificate",
    "--client-certificate-key",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "yt_dlp_path",
        type=Path,
        help="Path to the platform-independent yt-dlp zipapp or a source checkout",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Catalog destination (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--expected-sha256",
        help="Expected SHA-256 for a zipapp; generation fails if it does not match",
    )
    parser.add_argument(
        "--generated-at",
        help=(
            "Stable ISO-8601 catalog timestamp. By default the release date is "
            "derived from yt-dlp's date-based version"
        ),
    )
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_input(path: Path, expected_sha256: str | None) -> None:
    if not path.exists():
        raise ValueError(f"yt-dlp path does not exist: {path}")
    if not expected_sha256:
        return
    if not path.is_file():
        raise ValueError("--expected-sha256 can only be used with a yt-dlp file")

    expected = expected_sha256.strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("--expected-sha256 must be exactly 64 hexadecimal characters")

    actual = sha256(path)
    if actual != expected:
        raise ValueError(
            f"SHA-256 mismatch for {path}: expected {expected}, got {actual}"
        )


def import_root(path: Path) -> Path:
    """Return the sys.path entry needed for a zipapp or source directory."""
    path = path.resolve()
    if path.is_file():
        return path
    if (path / "yt_dlp").is_dir():
        return path
    if path.name == "yt_dlp" and (path / "options.py").is_file():
        return path.parent
    raise ValueError(
        f"{path} is not a yt-dlp zipapp, checkout root, or yt_dlp package directory"
    )


def load_parser(path: Path) -> tuple[Any, str]:
    # Refuse to silently introspect an unrelated globally installed yt-dlp.
    for module_name in tuple(sys.modules):
        if module_name == "yt_dlp" or module_name.startswith("yt_dlp."):
            del sys.modules[module_name]

    root = import_root(path)
    sys.path.insert(0, os.fspath(root))
    try:
        options_module = importlib.import_module("yt_dlp.options")
        version_module = importlib.import_module("yt_dlp.version")
        parser = options_module.create_parser()
        return parser, str(version_module.__version__)
    finally:
        sys.path.remove(os.fspath(root))


def slug(value: str) -> str:
    result = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return result or "options"


def flags_for(option: optparse.Option) -> list[str]:
    return [*option._short_opts, *option._long_opts]


def canonical_flag(option: optparse.Option) -> str:
    # yt-dlp declares the preferred spelling first; prefer a long spelling for
    # a stable, readable identifier even when a short alias is listed first.
    if option._long_opts:
        return option._long_opts[0]
    if option._short_opts:
        return option._short_opts[0]
    raise ValueError("Encountered an option with no command-line flags")


def default_description(value: Any) -> str | None:
    if value == optparse.NO_DEFAULT or value is None:
        return None
    if isinstance(value, str):
        return value
    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        )
    except (TypeError, ValueError):
        return None


def help_text(option: optparse.Option, formatter: optparse.HelpFormatter) -> str:
    if option.help in (None, optparse.SUPPRESS_HELP):
        return ""
    # This replaces yt-dlp's %default markers using the same logic as --help.
    return formatter.expand_default(option).strip()


def is_repeatable(option: optparse.Option) -> bool:
    if option.action in {"append", "append_const", "count"}:
        return True
    if option.action != "callback":
        return False
    if isinstance(option.default, (dict, list, set)):
        return True
    return "multiple times" in (option.help or "").lower()


def safety_for(flags: Iterable[str]) -> str:
    flag_set = {flag.lower() for flag in flags}
    if flag_set & EXEC_FLAGS:
        return "exec"
    if flag_set & PLUGIN_FLAGS:
        return "plugin"
    if flag_set & FILE_URL_FLAGS:
        return "file-url"
    if flag_set & CERT_BYPASS_FLAGS:
        return "cert-bypass"
    if flag_set & SENSITIVE_CREDENTIAL_FLAGS or any("password" in flag for flag in flag_set):
        return "password"
    return "normal"


def metavar_for(option: optparse.Option, takes_value: bool) -> str | None:
    if not takes_value or option.metavar is None:
        return None
    if isinstance(option.metavar, (tuple, list)):
        return " ".join(map(str, option.metavar))
    return str(option.metavar)


def catalog_option(
    option: optparse.Option,
    formatter: optparse.HelpFormatter,
) -> dict[str, Any]:
    flags = flags_for(option)
    canonical = canonical_flag(option)
    takes_value = bool(option.takes_value())
    return {
        "id": canonical,
        "canonicalFlag": canonical,
        "flags": flags,
        "signature": formatter.format_option_strings(option),
        "action": str(option.action),
        "nargs": str(option.nargs) if takes_value and option.nargs is not None else None,
        "metavar": metavar_for(option, takes_value),
        "choices": [str(choice) for choice in (option.choices or ())],
        "help": help_text(option, formatter),
        "repeatable": is_repeatable(option),
        "takesValue": takes_value,
        # optparse has no optional-value action; callback options that inspect
        # following arguments still declare a required nargs value.
        "valueOptional": False,
        "defaultValue": default_description(option.default),
        "safety": safety_for(flags),
    }


def release_timestamp(version: str, override: str | None) -> str:
    if override:
        return override
    match = re.match(r"^(\d{4})\.(\d{2})\.(\d{2})(?:\D|$)", version)
    if not match:
        raise ValueError(
            "Cannot derive a deterministic generatedAt value from version "
            f"{version!r}; pass --generated-at"
        )
    year, month, day = map(int, match.groups())
    # Constructing a date validates values while keeping output independent of
    # the machine's timezone and the time at which the generator was run.
    import datetime as _datetime

    release_date = _datetime.date(year, month, day)
    return f"{release_date.isoformat()}T00:00:00Z"


def build_catalog(parser: Any, version: str, generated_at: str) -> dict[str, Any]:
    formatter = parser.formatter
    formatter.set_parser(parser)

    groups: list[dict[str, Any]] = []
    used_group_ids: set[str] = set()
    used_option_ids: set[str] = set()

    def add_group(name: str, options: Iterable[optparse.Option]) -> None:
        options = list(options)
        if not options:
            return

        base_id = slug(name)
        group_id = base_id
        suffix = 2
        while group_id in used_group_ids:
            group_id = f"{base_id}-{suffix}"
            suffix += 1
        used_group_ids.add(group_id)

        encoded_options = []
        for option in options:
            encoded = catalog_option(option, formatter)
            if encoded["id"] in used_option_ids:
                raise ValueError(f"Duplicate canonical option flag: {encoded['id']}")
            used_option_ids.add(encoded["id"])
            encoded_options.append(encoded)

        groups.append({"id": group_id, "name": name, "options": encoded_options})

    for group in parser.option_groups:
        add_group(group.title, group.option_list)

    # create_parser() also registers supported-but-deprecated compatibility
    # switches directly on the parser. They are real accepted options, so keep
    # them in the catalog while separating them from normal UI-facing groups.
    add_group("Deprecated Compatibility Options", parser.option_list)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "ytDlpVersion": version,
        "generatedAt": generated_at,
        "groups": groups,
    }


def write_catalog(catalog: dict[str, Any], destination: Path) -> None:
    destination = destination.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    rendered = json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"

    temporary = destination.with_name(f".{destination.name}.tmp")
    temporary.write_text(rendered, encoding="utf-8")
    os.replace(temporary, destination)


def main() -> int:
    args = parse_args()
    try:
        source = args.yt_dlp_path.resolve()
        verify_input(source, args.expected_sha256)
        parser, version = load_parser(source)
        generated_at = release_timestamp(version, args.generated_at)
        catalog = build_catalog(parser, version, generated_at)
        write_catalog(catalog, args.output)
    except (ImportError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    option_count = sum(len(group["options"]) for group in catalog["groups"])
    print(
        f"Wrote {option_count} options in {len(catalog['groups'])} groups "
        f"for yt-dlp {version} to {args.output.resolve()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
