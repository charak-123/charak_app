#!/usr/bin/env python3
"""
Turn a folder of legal documents into the migration that publishes them.

    python3 docs/legal/publish.py 2026-10-28 0031           # write the migration
    python3 docs/legal/publish.py 2026-10-28 0031 --check   # fail if it's out of date

Each document is a markdown file in docs/legal/<version>/ with a header:

    ---
    type: refund_policy                 tos | privacy | telemedicine | practitioner_terms | refund_policy
    version: 2026-10-28                 must match the folder
    title: Cancellation & Refund Policy
    audience: patient, doctor
    url: https://www.charak.care/refunds
    summary: One line for the list of documents.
    highlights:
    - A key point, shown above the full text.
    ---

The body may use only what the apps render (packages/charak_core/lib/legal_text.dart):
## and ### headings, paragraphs, "- " and "1. " lists, two-column tables, and
**bold** / *italic*. Anything else is refused here rather than shown as raw
markdown on someone's phone.

The migration inserts each version once (on conflict do nothing). A published
version is never edited: change the text in a new folder with a new version.
A new version applies only once it is approved in admin → Policies.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LEGAL = ROOT / "docs" / "legal"
MIGRATIONS = ROOT / "supabase" / "migrations"

TYPES = ("tos", "privacy", "telemedicine", "practitioner_terms", "refund_policy")
AUDIENCES = ("patient", "doctor")
ORDER = {t: i for i, t in enumerate(("tos", "practitioner_terms", "privacy", "refund_policy", "telemedicine"))}

_LINE_OK = (
    re.compile(r"^$"),
    re.compile(r"^#{2,3} \S"),
    re.compile(r"^- \S"),
    re.compile(r"^\d+\. \S"),
    re.compile(r"^\|.*\|$"),
    re.compile(r"^[^#|>`\-*\s\d]"),            # an ordinary paragraph line
    re.compile(r"^\*\*?[^*\s]"),               # a paragraph that opens in bold/italic
    re.compile(r"^\d+[^.\d]"),                  # a paragraph that opens with a number
)


class DocumentError(ValueError):
    pass


def parse(path: Path) -> dict:
    """Read one document: its header fields and its body."""
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise DocumentError(f"{path.name}: must start with a --- header")
    try:
        header, body = text[4:].split("\n---\n", 1)
    except ValueError:
        raise DocumentError(f"{path.name}: header isn't closed with ---") from None

    fields: dict = {"highlights": []}
    in_highlights = False
    for line in header.splitlines():
        if in_highlights and line.startswith("- "):
            fields["highlights"].append(line[2:].strip())
            continue
        in_highlights = False
        key, sep, value = line.partition(":")
        if not sep:
            raise DocumentError(f"{path.name}: header line {line!r} isn't 'key: value'")
        key, value = key.strip(), value.strip()
        if key == "highlights":
            in_highlights = True
        else:
            fields[key] = value

    for key in ("type", "version", "title", "audience", "url", "summary"):
        if not fields.get(key):
            raise DocumentError(f"{path.name}: header needs '{key}'")
    if fields["type"] not in TYPES:
        raise DocumentError(f"{path.name}: type must be one of {', '.join(TYPES)}")
    fields["audience"] = [a.strip() for a in fields["audience"].split(",") if a.strip()]
    if not fields["audience"] or any(a not in AUDIENCES for a in fields["audience"]):
        raise DocumentError(f"{path.name}: audience must be patient and/or doctor")
    if not 1 <= len(fields["highlights"]) <= 6:
        raise DocumentError(f"{path.name}: give 1 to 6 highlights")

    fields["body"] = body.strip() + "\n"
    _check_body(path.name, fields["body"])
    return fields


def _check_body(name: str, body: str) -> None:
    for n, line in enumerate(body.splitlines(), 1):
        if line.startswith("# "):
            raise DocumentError(f"{name}:{n}: use ## for headings; the title comes from the header")
        if "$doc$" in line:
            raise DocumentError(f"{name}:{n}: '$doc$' is reserved")
        if not any(p.match(line) for p in _LINE_OK):
            raise DocumentError(f"{name}:{n}: the apps can't show {line[:40]!r}")
        if line.startswith("|") and not re.fullmatch(r"\|[^|]+\|[^|]+\|", line):
            raise DocumentError(f"{name}:{n}: tables have exactly two columns")


def documents(version: str) -> list[dict]:
    folder = LEGAL / version
    if not folder.is_dir():
        raise DocumentError(f"no folder docs/legal/{version}")
    docs = [parse(p) for p in sorted(folder.glob("*.md"))]
    if not docs:
        raise DocumentError(f"docs/legal/{version} has no documents")
    for d in docs:
        if d["version"] != version:
            raise DocumentError(f"{d['type']}: version {d['version']} doesn't match the folder {version}")
    types = [d["type"] for d in docs]
    if len(types) != len(set(types)):
        raise DocumentError(f"docs/legal/{version} has two documents of one type")
    return sorted(docs, key=lambda d: ORDER[d["type"]])


def fingerprint(body: str) -> str:
    """What the database stores in legal_documents.sha256 for this body."""
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def _sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def migration(version: str, number: str) -> str:
    docs = documents(version)
    out = [
        "-- ═══════════════════════════════════════════════════════════════════════════",
        f"-- {number}: legal documents, version {version}. Generated; do not edit.",
        "--",
        f"--   python3 docs/legal/publish.py {version} {number}",
        "--",
        f"-- From docs/legal/{version}/. Each version applies only once it is",
        "-- approved in admin → Policies (the review gate, migration 0029). Until",
        "-- then the apps keep showing the version people already accepted.",
        "--",
        "-- Fingerprints (legal_documents.sha256, set by the database from the body):",
    ]
    out += [f"--   {d['type']:<20} {fingerprint(d['body'])}" for d in docs]
    out += [
        "--",
        "-- Idempotent: safe to re-run in the SQL Editor.",
        "-- ═══════════════════════════════════════════════════════════════════════════",
        "",
    ]
    for d in docs:
        highlights = "jsonb_build_array(\n    " + ",\n    ".join(_sql_text(h) for h in d["highlights"]) + ")"
        audience = "'{" + ",".join(d["audience"]) + "}'"
        out += [
            f"-- {d['title']}",
            "insert into legal_documents (type, version, title, url, audience, material, summary, highlights, body)",
            "values (",
            f"  {_sql_text(d['type'])}, {_sql_text(d['version'])}, {_sql_text(d['title'])},",
            f"  {_sql_text(d['url'])}, {audience}, true,",
            f"  {_sql_text(d['summary'])},",
            f"  {highlights},",
            f"  $doc${d['body']}$doc$",
            ")",
            "on conflict (type, version) do nothing;",
            "",
        ]
    out.append("notify pgrst, 'reload schema';")
    return "\n".join(out) + "\n"


def migration_path(version: str, number: str) -> Path:
    return MIGRATIONS / f"{number}_legal_documents_{version.replace('-', '_')}.sql"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("version", help="the folder under docs/legal, e.g. 2026-10-28")
    ap.add_argument("number", help="the migration number, e.g. 0031")
    ap.add_argument("--check", action="store_true", help="fail if the migration is out of date")
    args = ap.parse_args(argv)
    try:
        sql = migration(args.version, args.number)
    except DocumentError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    path = migration_path(args.version, args.number)
    if args.check:
        if not path.exists() or path.read_text(encoding="utf-8") != sql:
            print(f"{path.relative_to(ROOT)} is out of date: run without --check", file=sys.stderr)
            return 1
        print(f"{path.relative_to(ROOT)} is up to date")
        return 0
    path.write_text(sql, encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
