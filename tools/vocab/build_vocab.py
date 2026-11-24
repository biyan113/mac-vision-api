#!/usr/bin/env python3
"""把 English Vocabulary Vault 词库（https://github.com/lilinji/English）里的 Excel 词表
合并去重，生成一个可随 App 分发的 SQLite 数据库。

用法：
    pip install openpyxl
    git clone --depth 1 https://github.com/lilinji/English
    python3 tools/vocab/build_vocab.py English vocab.sqlite

词库数据采用 CC BY-NC-SA 4.0 许可：不可商用、需署名、衍生数据须以相同许可分发。
生成的数据库同样受该许可约束，因此本仓库只包含脚本，不包含数据。

输出的表：
    words(id, word, phonetic_uk, phonetic_us, definition)   每个单词一行，不区分大小写去重
    books(id, category, name, path, word_count)             每本词书一行
    book_words(book_id, word_id)                             词书与单词的对应关系
    meta(key, value)                                         来源、许可、统计信息
"""

from __future__ import annotations

import argparse
import collections
import re
import sqlite3
import sys
import warnings
from pathlib import Path

try:
    import openpyxl
except ImportError:  # pragma: no cover
    sys.exit("缺少依赖：pip install openpyxl")

HEADER_WORD = "单词"
EMPTY_DEFINITIONS = {"", "无", "none", "null"}
SOURCE_URL = "https://github.com/lilinji/English"
LICENSE = "CC BY-NC-SA 4.0"


def clean(value) -> str:
    if value is None:
        return ""
    return re.sub(r"[ \t ]+", " ", str(value)).strip()


def clean_definition(value) -> str:
    text = "\n".join(line.strip() for line in clean(value).splitlines() if line.strip())
    return "" if text.lower() in EMPTY_DEFINITIONS else text


def category_of(path: Path, root: Path) -> str:
    top = path.relative_to(root).parts[0]
    return re.sub(r"^\d+\.", "", top)


def read_book(path: Path):
    """返回 [(word, uk, us, definition)]。兼容两种格式：
    带表头的四列（单词/英音/美音/释义），以及没有表头的两列（单词/释义）。"""
    workbook = openpyxl.load_workbook(path, read_only=True)
    try:
        rows = workbook.worksheets[0].iter_rows(values_only=True)
        first = next(rows, None)
        if first is None:
            return []

        entries = []
        has_header = clean(first[0]) == HEADER_WORD
        four_columns = has_header and len(first) >= 4

        def parse(row):
            if not row or not clean(row[0]):
                return None
            word = clean(row[0])
            if four_columns:
                cells = list(row) + [None] * 4
                return word, clean(cells[1]), clean(cells[2]), clean_definition(cells[3])
            definition = clean_definition(row[1]) if len(row) > 1 else ""
            return word, "", "", definition

        if not has_header:
            entry = parse(first)
            if entry:
                entries.append(entry)
        for row in rows:
            entry = parse(row)
            if entry:
                entries.append(entry)
        return entries
    finally:
        workbook.close()


def build(source: Path, output: Path) -> dict:
    files = sorted(source.rglob("*.xlsx"))
    if not files:
        sys.exit(f"在 {source} 下没有找到 .xlsx 词表")

    display = {}                                        # key -> 首次出现的写法
    phonetic_uk = {}
    phonetic_us = {}
    definitions = collections.defaultdict(collections.Counter)
    books = []                                          # (category, name, path, [keys])
    skipped = []

    for path in files:
        try:
            entries = read_book(path)
        except Exception as error:  # noqa: BLE001 - 单个文件损坏不应中断整体构建
            skipped.append((str(path.relative_to(source)), str(error)))
            continue

        keys = []
        seen = set()
        for word, uk, us, definition in entries:
            key = word.lower()
            display.setdefault(key, word)
            if uk and key not in phonetic_uk:
                phonetic_uk[key] = uk
            if us and key not in phonetic_us:
                phonetic_us[key] = us
            if definition:
                definitions[key][definition] += 1
            if key not in seen:
                seen.add(key)
                keys.append(key)
        if keys:
            books.append((category_of(path, source), path.stem, str(path.relative_to(source)), keys))

    def best_definition(key: str) -> str:
        counter = definitions.get(key)
        if not counter:
            return ""
        # 出现次数最多的释义；并列时取较长的那个
        return max(counter.items(), key=lambda item: (item[1], len(item[0])))[0]

    if output.exists():
        output.unlink()
    connection = sqlite3.connect(output)
    connection.executescript(
        """
        CREATE TABLE words (
            id INTEGER PRIMARY KEY,
            word TEXT NOT NULL UNIQUE COLLATE NOCASE,
            phonetic_uk TEXT NOT NULL DEFAULT '',
            phonetic_us TEXT NOT NULL DEFAULT '',
            definition TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE books (
            id INTEGER PRIMARY KEY,
            category TEXT NOT NULL,
            name TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            word_count INTEGER NOT NULL
        );
        CREATE TABLE book_words (
            book_id INTEGER NOT NULL REFERENCES books(id),
            word_id INTEGER NOT NULL REFERENCES words(id),
            PRIMARY KEY (book_id, word_id)
        ) WITHOUT ROWID;
        CREATE INDEX book_words_by_word ON book_words(word_id);
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """
    )

    word_ids = {}
    for index, key in enumerate(sorted(display), start=1):
        word_ids[key] = index
        connection.execute(
            "INSERT INTO words VALUES (?, ?, ?, ?, ?)",
            (index, display[key], phonetic_uk.get(key, ""), phonetic_us.get(key, ""), best_definition(key)),
        )

    for book_id, (category, name, path, keys) in enumerate(books, start=1):
        connection.execute("INSERT INTO books VALUES (?, ?, ?, ?, ?)", (book_id, category, name, path, len(keys)))
        connection.executemany(
            "INSERT INTO book_words VALUES (?, ?)", [(book_id, word_ids[key]) for key in keys]
        )

    stats = {
        "source": SOURCE_URL,
        "license": LICENSE,
        "books": len(books),
        "words": len(display),
        "words_with_definition": sum(1 for key in display if definitions.get(key)),
        "words_with_phonetic": sum(1 for key in display if key in phonetic_uk or key in phonetic_us),
        "book_word_links": sum(len(keys) for *_, keys in books),
        "skipped_files": len(skipped),
    }
    connection.executemany("INSERT INTO meta VALUES (?, ?)", [(key, str(value)) for key, value in stats.items()])
    connection.commit()
    connection.execute("VACUUM")
    connection.close()

    stats["skipped"] = skipped
    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description="把 English Vocabulary Vault 的词表合并成 SQLite 数据库")
    parser.add_argument("source", type=Path, help="词库仓库的本地目录")
    parser.add_argument("output", type=Path, help="输出的 SQLite 文件路径")
    arguments = parser.parse_args()

    warnings.filterwarnings("ignore", module="openpyxl")
    stats = build(arguments.source, arguments.output)

    size = arguments.output.stat().st_size / 1024 / 1024
    print(f"词书       {stats['books']}")
    print(f"单词       {stats['words']}")
    print(f"  有释义   {stats['words_with_definition']}")
    print(f"  有音标   {stats['words_with_phonetic']}")
    print(f"词书-单词  {stats['book_word_links']}")
    print(f"数据库     {size:.1f} MB -> {arguments.output}")
    if stats["skipped"]:
        print(f"跳过 {len(stats['skipped'])} 个无法读取的文件：")
        for path, error in stats["skipped"]:
            print(f"  {path}: {error}")


if __name__ == "__main__":
    main()
