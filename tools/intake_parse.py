"""Parse and validate a read-tsf contribution for tools/intake.sh.

    python3 tools/intake_parse.py <contribution.md>

Prints shell assignments (every value quoted, every name fixed here, never
taken from the file) and stages each carried file in a temporary directory.
Exits non-zero, touching nothing, on anything it does not expect.
"""
import os
import re
import shlex
import sys
import tempfile

# Same lists as read-tsf-sync and read-tsf-sync.ps1.
ALLOW_PATH = re.compile(r"^(plugins/read-tsf/.+|tools/[^/]+|\.claude-plugin/marketplace\.json|\.github/workflows/[^/]+|[A-Z]+\.md)$")
ALLOW_EXT = re.compile(r"(\.(md|sh|ps1|cmd|json|yml|yaml|txt)|/bin/read-tsf-sync)$")
MARK = re.compile(rb"^<!-- read-tsf file: (add|modify|delete) (\S+) base=([0-9a-f]{64}|-) lines=(\d+) -->$")
FENCE = re.compile(rb"^(`{3,})text$")


def main(path):
    raw = open(path, "rb").read()
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    lines = raw.replace(b"\r", b"").split(b"\n")
    if lines[0] != b"<!-- read-tsf contribution":
        sys.exit("not a read-tsf contribution")

    head, i = {}, 1
    while i < len(lines) and lines[i] != b"-->":
        k, _, v = lines[i].decode("utf-8", "replace").partition(": ")
        head[k] = v
        i += 1
    if head.get("Format") != "3":
        sys.exit(f"unsupported Format: {head.get('Format')}")
    for k in ("From", "Subject", "Base-Version", "Base-Commit"):
        if not head.get(k):
            sys.exit(f"header lacks {k}")

    text = [l.decode("utf-8", "replace") for l in lines]
    try:
        a = text.index("<!-- read-tsf pr-body -->")
        b = text.index("<!-- read-tsf pr-body end -->")
    except ValueError:
        sys.exit("no pr-body section")
    body = "\n".join(text[a + 1:b]).strip()
    summary = re.search(r"^## Summary\n\n(.*?)(?=\n## |\Z)", body, re.S | re.M)
    summary = summary.group(1).strip() if summary else ""

    files, i = [], b + 1
    while i < len(lines) and lines[i] != b"<!-- read-tsf end -->":
        m = MARK.match(lines[i])
        if not m:
            i += 1
            continue
        op, p, base, n = m.group(1).decode(), m.group(2).decode(), m.group(3).decode(), int(m.group(4))
        if ".." in p.split("/") or p.startswith("/") or not (ALLOW_PATH.match(p) and ALLOW_EXT.search(p)):
            sys.exit(f"refusing path outside the skill: {p}")
        data = b""
        if op == "delete":
            i += 1
        else:
            f = FENCE.match(lines[i + 1]) if i + 1 < len(lines) else None
            if not f:
                sys.exit(f"{p}: no opening fence")
            content = lines[i + 2:i + 2 + n]
            closing = lines[i + 2 + n] if i + 2 + n < len(lines) else None
            if len(content) != n or closing != f.group(1) or b"\x00" in b"".join(content):
                sys.exit(f"{p}: truncated, edited or binary content")
            data = b"".join(l + b"\n" for l in content)
            i += 3 + n
        files.append((op, p, base, data))
    if i >= len(lines):
        sys.exit("no end marker: the file is truncated")
    if not files:
        sys.exit("the contribution carries no file")

    stage = tempfile.mkdtemp(prefix="intake-")
    with open(os.path.join(stage, "pr-body.md"), "w", encoding="utf-8") as out:
        out.write(body + "\n")
    out = {"from": head["From"], "subject": head["Subject"], "base_version": head["Base-Version"],
           "base_commit": head["Base-Commit"], "summary": summary, "stage": stage}
    for k, v in out.items():
        print(f"{k}={shlex.quote(v)}")
    for n, (op, p, base, data) in enumerate(files):
        staged = os.path.join(stage, str(n))
        with open(staged, "wb") as f:
            f.write(data)
        print(f"files+=({shlex.quote(op)} {shlex.quote(p)} {shlex.quote(base)} {shlex.quote(staged)})")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
