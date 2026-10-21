#!/usr/bin/env python3
"""Helpers for preview.sh (Quick Look), standard library plus Pygments.

  preview_extra.py bbox FILE            → "L × W × H" of a 3D model (STL, OBJ, 3MF)
  preview_extra.py table FILE [SHEET]   → HTML table of a CSV / TSV file
  preview_extra.py code FILE            → HTML of the file with syntax colours
  preview_extra.py epub FILE OUTDIR     → JSON {title, author, cover}
  preview_extra.py note FILE            → Obsidian note as plain Markdown
  preview_extra.py archive FILE         → HTML listing of an archive (via bsdtar)
"""

import csv
import hashlib
import html
import io
import json
import os
import re
import struct
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as ET

MAX_ROWS, MAX_COLS, MAX_CODE = 200, 30, 60_000


# ------------------------------------------------------------------ 3D
def bbox_points(path):
    low = path.lower()
    if low.endswith(".stl"):
        with open(path, "rb") as f:
            data = f.read()
        if len(data) >= 84:
            n = struct.unpack_from("<I", data, 80)[0]
            if 84 + 50 * n == len(data):
                for i in range(n):
                    off = 84 + 50 * i + 12
                    for k in range(3):
                        yield struct.unpack_from("<3f", data, off + 12 * k)
                return
        for m in re.finditer(rb"vertex\s+(\S+)\s+(\S+)\s+(\S+)", data):
            yield tuple(float(x) for x in m.groups())
    elif low.endswith(".obj"):
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.startswith("v "):
                    p = line.split()
                    yield float(p[1]), float(p[2]), float(p[3])
    elif low.endswith(".3mf"):
        with zipfile.ZipFile(path) as z:
            for name in z.namelist():
                if name.lower().endswith(".model"):
                    for _, el in ET.iterparse(io.BytesIO(z.read(name))):
                        if el.tag.endswith("}vertex") or el.tag == "vertex":
                            yield float(el.get("x")), float(el.get("y")), float(el.get("z"))
                        el.clear()


def bbox(path):
    lo, hi, n = [float("inf")] * 3, [float("-inf")] * 3, 0
    for p in bbox_points(path):
        n += 1
        for i in range(3):
            lo[i] = min(lo[i], p[i])
            hi[i] = max(hi[i], p[i])
    if not n:
        return ""
    size = [hi[i] - lo[i] for i in range(3)]
    fmt = lambda v: f"{v:.1f}".rstrip("0").rstrip(".")
    return " × ".join(fmt(v) for v in size)


# --------------------------------------------------------------- tables
def table(path):
    with open(path, encoding="utf-8", errors="replace", newline="") as f:
        sample = f.read(65536)
        f.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",;\t|")
        except csv.Error:
            dialect = csv.excel_tab if path.lower().endswith(".tsv") else csv.excel
        rows = []
        total = 0
        for row in csv.reader(f, dialect):
            total += 1
            if len(rows) < MAX_ROWS:
                rows.append(row[:MAX_COLS])
    if not rows:
        return ""
    cells = lambda r, tag: "".join(f"<{tag}>{html.escape(c.strip())[:120]}</{tag}>" for c in r)
    head = f"<tr>{cells(rows[0], 'th')}</tr>"
    body = "".join(f"<tr>{cells(r, 'td')}</tr>" for r in rows[1:])
    more = f"<p>… {total - len(rows)} more rows</p>" if total > len(rows) else ""
    width = max(len(r) for r in rows)
    return (f"<p>{total} rows × {width} columns</p>"
            f"<table border='0' cellspacing='0' cellpadding='4'>{head}{body}</table>{more}")


# ----------------------------------------------------------------- code
def code(path):
    from pygments import highlight
    from pygments.formatters import HtmlFormatter
    from pygments.lexers import get_lexer_for_filename, guess_lexer, TextLexer
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read(MAX_CODE)
    if path.lower().endswith(".json"):
        try:
            text = json.dumps(json.loads(text), indent=2, ensure_ascii=False)
        except ValueError:
            pass
    try:
        lexer = get_lexer_for_filename(path, text)
    except Exception:
        try:
            lexer = guess_lexer(text)
        except Exception:
            lexer = TextLexer()
    out = highlight(text, lexer, HtmlFormatter(noclasses=True, nowrap=True, style="one-dark"))
    return f"<pre>{out}</pre>"


# ----------------------------------------------------------------- epub
def epub(path, outdir):
    info = {"title": "", "author": "", "cover": ""}
    with zipfile.ZipFile(path) as z:
        try:
            container = ET.fromstring(z.read("META-INF/container.xml"))
            opf_path = next(el.get("full-path") for el in container.iter() if el.tag.endswith("rootfile"))
        except Exception:
            return info
        opf = ET.fromstring(z.read(opf_path))
        base = os.path.dirname(opf_path)
        for el in opf.iter():
            tag = el.tag.split("}")[-1]
            if tag == "title" and not info["title"]:
                info["title"] = (el.text or "").strip()
            elif tag == "creator" and not info["author"]:
                info["author"] = (el.text or "").strip()
        cover_id, items = None, {}
        for el in opf.iter():
            tag = el.tag.split("}")[-1]
            if tag == "meta" and el.get("name") == "cover":
                cover_id = el.get("content")
            elif tag == "item":
                items[el.get("id")] = el
        href = None
        for el in items.values():
            if "cover-image" in (el.get("properties") or ""):
                href = el.get("href")
        if not href and cover_id in items:
            href = items[cover_id].get("href")
        if not href:
            for el in items.values():
                if (el.get("media-type") or "").startswith("image/") and "cover" in (el.get("href") or "").lower():
                    href = el.get("href")
                    break
        if href:
            name = os.path.normpath(os.path.join(base, href)).replace("\\", "/")
            try:
                data = z.read(name)
                os.makedirs(outdir, exist_ok=True)
                out = os.path.join(outdir, "epub-cover-" + hashlib.md5(path.encode()).hexdigest()[:16] + os.path.splitext(name)[1])
                with open(out, "wb") as f:
                    f.write(data)
                info["cover"] = out
            except KeyError:
                pass
    return info


# ----------------------------------------------------------------- note
def note(path):
    """Obsidian Markdown → plain Markdown: front matter as a list,
    [[links]] as bold text, ![[embeds]] of images as images."""
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read(200_000)
    props = ""
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if m:
        lines = [l for l in m.group(1).splitlines() if l.strip()]
        props = "\n".join(f"- {html.escape(l)}" for l in lines[:12]) + "\n\n---\n\n"
        text = text[m.end():]
    vault = os.path.dirname(path)
    while vault != "/" and not os.path.isdir(os.path.join(vault, ".obsidian")):
        vault = os.path.dirname(vault)

    def find(name):
        if vault == "/":
            return None
        for root, dirs, files in os.walk(vault):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            if name in files:
                return os.path.join(root, name)
        return None

    def embed(m):
        target = m.group(1).split("|")[0].strip()
        if re.search(r"\.(png|jpe?g|gif|webp|svg)$", target, re.I):
            p = find(os.path.basename(target))
            return f"![{target}](file://{p})" if p else f"*{target}*"
        return f"*{target}*"

    text = re.sub(r"!\[\[([^\]]+)\]\]", embed, text)
    text = re.sub(r"\[\[([^\]|#]+)(?:#[^\]|]*)?\|([^\]]+)\]\]", r"**\2**", text)
    text = re.sub(r"\[\[([^\]|]+)\]\]", lambda m: "**" + m.group(1).split("#")[0] + "**", text)
    return props + text


# -------------------------------------------------------------- archive
def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


def archive(path):
    out = subprocess.run(["bsdtar", "-tvf", path], capture_output=True, text=True, errors="replace").stdout
    files, dirs, total, rows = 0, 0, 0, []
    for line in out.splitlines():
        p = line.split(None, 8)
        if len(p) < 9:
            continue
        name, size = p[8], int(p[4]) if p[4].isdigit() else 0
        if line.startswith("d") or name.endswith("/"):
            dirs += 1
            continue
        files += 1
        total += size
        if len(rows) < 400:
            rows.append(f"<tr><td>{html.escape(name)}</td><td align='right'>{human(size)}</td></tr>")
    more = f"<p>… {files - len(rows)} more files</p>" if files > len(rows) else ""
    return (f"<p>{files} files, {dirs} folders, {human(total)} uncompressed</p>"
            f"<table border='0' cellspacing='0' cellpadding='3'>{''.join(rows)}</table>{more}")


def main():
    cmd, path = sys.argv[1], sys.argv[2]
    try:
        if cmd == "bbox":
            print(bbox(path))
        elif cmd == "table":
            print(table(path))
        elif cmd == "code":
            print(code(path))
        elif cmd == "epub":
            print(json.dumps(epub(path, sys.argv[3])))
        elif cmd == "note":
            print(note(path))
        elif cmd == "archive":
            print(archive(path))
    except Exception:
        sys.exit(1)


if __name__ == "__main__":
    main()
