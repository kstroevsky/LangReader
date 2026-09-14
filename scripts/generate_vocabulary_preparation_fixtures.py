#!/usr/bin/env python3
"""Generate deterministic English/German PDF, EPUB, and DOCX fixtures."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import tempfile
import unicodedata
import zipfile
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = ROOT / "Tests" / "Fixtures" / "VocabularyPreparation"
SOURCE_ROOT = FIXTURE_ROOT / "sources"
GENERATED_ROOT = FIXTURE_ROOT / "generated"
MANIFEST_PATH = FIXTURE_ROOT / "manifest.json"
ZIP_TIMESTAMP = (2020, 1, 1, 0, 0, 0)
TOKEN_PATTERN = re.compile(r"[^\W\d_]+(?:['’\-][^\W\d_]+)*", re.UNICODE)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_blocks(language: str) -> list[str]:
    text = (SOURCE_ROOT / f"{language}.txt").read_text(encoding="utf-8")
    normalized = unicodedata.normalize("NFC", text).replace("\r\n", "\n").strip()
    blocks = [block.strip() for block in re.split(r"\n\s*\n", normalized) if block.strip()]
    if len(blocks) < 3:
        raise ValueError(f"{language}.txt needs a title, introduction, and body paragraphs")
    return blocks


def lexical_inventory(blocks: list[str]) -> dict[str, object]:
    counts = Counter(match.group(0).lower() for match in TOKEN_PATTERN.finditer("\n\n".join(blocks)))
    return {
        "token_count": sum(counts.values()),
        "unique_token_count": len(counts),
        "occurrences": dict(sorted(counts.items())),
    }


def wrapped_lines(blocks: list[str], width: int = 88) -> list[tuple[str, int, int]]:
    lines: list[tuple[str, int, int]] = [(blocks[0], 18, 24), ("", 10, 8)]
    for block in blocks[1:]:
        words = block.replace("\n", " ").split()
        current = ""
        for word in words:
            candidate = word if not current else f"{current} {word}"
            if len(candidate) <= width:
                current = candidate
            else:
                lines.append((current, 10, 13))
                current = word
        if current:
            lines.append((current, 10, 13))
        lines.append(("", 10, 7))
    return lines


def pdf_hex(text: str) -> str:
    return text.encode("cp1252").hex().upper()


def build_pdf(blocks: list[str]) -> bytes:
    pages: list[list[tuple[str, int, int]]] = []
    page: list[tuple[str, int, int]] = []
    remaining = 650
    for line in wrapped_lines(blocks):
        needed = line[2]
        if page and remaining < needed:
            pages.append(page)
            page = []
            remaining = 650
        page.append(line)
        remaining -= needed
    if page:
        pages.append(page)

    objects: dict[int, bytes] = {}
    objects[1] = b"<< /Type /Catalog /Pages 2 0 R >>"
    objects[3] = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
    page_ids: list[int] = []
    for index, page_lines in enumerate(pages):
        page_id = 4 + index * 2
        content_id = page_id + 1
        page_ids.append(page_id)
        y = 742
        commands = [b"BT"]
        for value, size, leading in page_lines:
            if value:
                commands.append(f"/F1 {size} Tf 1 0 0 1 72 {y} Tm <{pdf_hex(value)}> Tj".encode("ascii"))
            y -= leading
        commands.append(b"ET")
        content = b"\n".join(commands) + b"\n"
        objects[page_id] = (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            f"/Resources << /Font << /F1 3 0 R >> >> /Contents {content_id} 0 R >>"
        ).encode("ascii")
        objects[content_id] = f"<< /Length {len(content)} >>\nstream\n".encode("ascii") + content + b"endstream"
    kids = " ".join(f"{page_id} 0 R" for page_id in page_ids)
    objects[2] = f"<< /Type /Pages /Kids [{kids}] /Count {len(page_ids)} >>".encode("ascii")

    result = bytearray(b"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n")
    offsets = [0] * (max(objects) + 1)
    for object_id in sorted(objects):
        offsets[object_id] = len(result)
        result.extend(f"{object_id} 0 obj\n".encode("ascii"))
        result.extend(objects[object_id])
        result.extend(b"\nendobj\n")
    xref = len(result)
    result.extend(f"xref\n0 {len(offsets)}\n".encode("ascii"))
    result.extend(b"0000000000 65535 f\n")
    for offset in offsets[1:]:
        result.extend(f"{offset:010d} 00000 n\n".encode("ascii"))
    result.extend(
        f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode("ascii")
    )
    return bytes(result)


def zip_bytes(entries: list[tuple[str, bytes, int]]) -> bytes:
    with tempfile.NamedTemporaryFile(suffix=".zip") as temporary:
        with zipfile.ZipFile(temporary.name, "w") as archive:
            for name, data, compression in entries:
                info = zipfile.ZipInfo(name, ZIP_TIMESTAMP)
                info.compress_type = compression
                info.create_system = 0
                info.external_attr = 0
                archive.writestr(info, data)
        return Path(temporary.name).read_bytes()


def build_epub(language: str, blocks: list[str]) -> bytes:
    title = html.escape(blocks[0])
    paragraphs = "\n".join(f"<p>{html.escape(block)}</p>" for block in blocks[1:])
    content = f"""<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="{language}" lang="{language}">
<head><title></title><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body><main><h1>{title}</h1>{paragraphs}</main></body></html>
""".encode("utf-8")
    container = b"""<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
"""
    package = f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">leafreader-vocabulary-{language}-v1</dc:identifier><dc:title>{title}</dc:title><dc:language>{language}</dc:language></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="content" href="content.xhtml" media-type="application/xhtml+xml"/><item id="style" href="style.css" media-type="text/css"/></manifest>
<spine><itemref idref="content"/></spine></package>
""".encode("utf-8")
    navigation = f"""<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="{language}"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="content.xhtml">{title}</a></li></ol></nav></body></html>
""".encode("utf-8")
    css = b"body{font-family:serif;line-height:1.55;margin:7%;}main{max-width:44rem;margin:auto;}h1{font-size:1.8rem;line-height:1.2;margin-bottom:1.4rem;}p{margin:0 0 1rem;}"
    return zip_bytes([
        ("mimetype", b"application/epub+zip", zipfile.ZIP_STORED),
        ("META-INF/container.xml", container, zipfile.ZIP_DEFLATED),
        ("OEBPS/content.opf", package, zipfile.ZIP_DEFLATED),
        ("OEBPS/nav.xhtml", navigation, zipfile.ZIP_DEFLATED),
        ("OEBPS/content.xhtml", content, zipfile.ZIP_DEFLATED),
        ("OEBPS/style.css", css, zipfile.ZIP_DEFLATED),
    ])


def word_paragraph(text: str, style: str | None = None) -> str:
    style_xml = f'<w:pPr><w:pStyle w:val="{style}"/></w:pPr>' if style else ""
    return f'<w:p>{style_xml}<w:r><w:t xml:space="preserve">{html.escape(text)}</w:t></w:r></w:p>'


def build_docx(language: str, blocks: list[str]) -> bytes:
    paragraphs = [word_paragraph(blocks[0], "Title")]
    paragraphs.extend(word_paragraph(block) for block in blocks[1:])
    document = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>{''.join(paragraphs)}<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>
""".encode("utf-8")
    styles = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Aptos" w:hAnsi="Aptos"/><w:sz w:val="22"/><w:lang w:val="{language}"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="180" w:line="300" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="0" w:after="360"/><w:keepNext/></w:pPr><w:rPr><w:color w:val="000000"/><w:b/><w:sz w:val="36"/></w:rPr></w:style>
</w:styles>
""".encode("utf-8")
    content_types = b"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
"""
    relationships = b"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
"""
    document_relationships = b"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
"""
    return zip_bytes([
        ("[Content_Types].xml", content_types, zipfile.ZIP_DEFLATED),
        ("_rels/.rels", relationships, zipfile.ZIP_DEFLATED),
        ("word/document.xml", document, zipfile.ZIP_DEFLATED),
        ("word/_rels/document.xml.rels", document_relationships, zipfile.ZIP_DEFLATED),
        ("word/styles.xml", styles, zipfile.ZIP_DEFLATED),
    ])


def generated_payloads() -> tuple[dict[str, bytes], dict[str, object]]:
    payloads: dict[str, bytes] = {}
    languages: dict[str, object] = {}
    fixtures: list[dict[str, object]] = []
    for language in ("en", "de"):
        blocks = source_blocks(language)
        source_data = (SOURCE_ROOT / f"{language}.txt").read_bytes()
        languages[language] = {
            "source": f"sources/{language}.txt",
            "source_sha256": sha256(source_data),
            "expected_inventory": lexical_inventory(blocks),
        }
        builders = {"pdf": build_pdf, "epub": lambda value, lang=language: build_epub(lang, value), "docx": lambda value, lang=language: build_docx(lang, value)}
        for format_name in ("pdf", "epub", "docx"):
            relative_path = f"generated/{language}.{format_name}"
            data = builders[format_name](blocks)
            payloads[relative_path] = data
            fixtures.append({
                "language": language,
                "format": format_name,
                "alias": f"supplement-{language}-{format_name}",
                "path": relative_path,
                "sha256": sha256(data),
                "byte_count": len(data),
            })
    manifest = {
        "schema_version": 1,
        "fixture_set": "vocabulary-preparation-cross-format-supplement-v1",
        "source_license": "CC0-1.0",
        "generator": {
            "version": 1,
            "command": "python3 scripts/generate_vocabulary_preparation_fixtures.py",
            "pinned_runtime": "CPython 3.12.14",
            "dependencies": "Python standard library only",
        },
        "languages": languages,
        "fixtures": fixtures,
    }
    return payloads, manifest


def write_generated(destination: Path) -> None:
    payloads, manifest = generated_payloads()
    for relative_path, data in payloads.items():
        path = destination / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    (destination / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def check_generated() -> None:
    with tempfile.TemporaryDirectory(prefix="leafreader-vocabulary-fixtures-") as temporary:
        candidate = Path(temporary)
        write_generated(candidate)
        expected = sorted(path.relative_to(candidate) for path in candidate.rglob("*") if path.is_file())
        for relative_path in expected:
            committed = FIXTURE_ROOT / relative_path
            if not committed.is_file() or committed.read_bytes() != (candidate / relative_path).read_bytes():
                raise SystemExit(f"stale vocabulary preparation fixture: {relative_path}")
    print("vocabulary preparation cross-format fixtures are reproducible")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    if arguments.check:
        check_generated()
        return
    GENERATED_ROOT.mkdir(parents=True, exist_ok=True)
    write_generated(FIXTURE_ROOT)
    print(f"generated fixtures and manifest under {FIXTURE_ROOT}")


if __name__ == "__main__":
    main()
