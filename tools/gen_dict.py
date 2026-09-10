#!/usr/bin/env python3
"""生成 data/pinyin.zsh。

离线跑一次即可，用户机器上不需要 Python。

    pip install pypinyin
    python3 tools/gen_dict.py

输出是一句 zsh 关联数组赋值，key 是汉字本身（不是码点——省掉运行时
的字符转码），value 是该字的读音，多音字用 | 分隔。
"""
import sys
from pathlib import Path

try:
    from pypinyin import pinyin, lazy_pinyin, Style
except ImportError:
    sys.exit("需要 pypinyin：pip install pypinyin")

# CJK 统一汉字基本区。扩展区 B 及以后的字出现在目录名里的概率
# 低到不值得为它多背几百 KB。
START, END = 0x4E00, 0x9FA5
MAX_READINGS = 3

TRANS = str.maketrans({"ü": "v", "ê": "e", "ń": "n", "ň": "n", "ǹ": "n", "ḿ": "m"})


def clean(s: str) -> str:
    s = s.lower().translate(TRANS)
    return "".join(c for c in s if "a" <= c <= "z")


def readings_of(ch: str):
    """返回去重后的读音列表，最常用的排在第一个。"""
    out = []
    first = clean(lazy_pinyin(ch, style=Style.NORMAL, errors="ignore")[0]
                  if lazy_pinyin(ch, style=Style.NORMAL, errors="ignore") else "")
    if first:
        out.append(first)
    for group in pinyin(ch, style=Style.NORMAL, heteronym=True, errors="ignore"):
        for r in group:
            r = clean(r)
            if r and r not in out:
                out.append(r)
    return out[:MAX_READINGS]


def main():
    root = Path(__file__).resolve().parent.parent
    dest = root / "data" / "pinyin.zsh"
    lines = []
    n_chars = n_hetero = 0
    for cp in range(START, END + 1):
        ch = chr(cp)
        rs = readings_of(ch)
        if not rs:
            continue
        n_chars += 1
        if len(rs) > 1:
            n_hetero += 1
        lines.append(f"{ch} '{'|'.join(rs)}'")

    with dest.open("w", encoding="utf-8") as f:
        f.write("# 由 tools/gen_dict.py 生成，请勿手工编辑。\n")
        f.write(f"# 覆盖 U+{START:04X}-U+{END:04X}，共 {n_chars} 字"
                f"（其中 {n_hetero} 个多音字）。\n")
        f.write("typeset -gA _zpt_dict=(\n")
        f.write("\n".join(lines))
        f.write("\n)\n")

    size = dest.stat().st_size
    print(f"{dest}: {n_chars} 字, {n_hetero} 多音字, {size/1024:.0f} KB")


if __name__ == "__main__":
    main()
