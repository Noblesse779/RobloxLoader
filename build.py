#!/usr/bin/env python3
"""Build encoded copies of the scripts for the public repo.

Each .lua file is stripped of comments and indentation (line breaks are kept, so
error line numbers still match the source), XOR-encoded with a random key, and
wrapped in a small loader that decodes it and runs it with the same arguments.

    python3 build.py <out_dir>

This only stops casual copying: anyone who hooks loadstring in their executor
can still read the decoded script.
"""
import os
import random
import re
import sys

SKIP = {"build.py"}


def lex(src):
    """Yield (kind, text) tokens. kind is 'comment', 'string', 'space' or 'code'."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i + len(m.group(0)))
                j = n if j < 0 else j + len(close)
            else:
                j = src.find("\n", i)
                j = n if j < 0 else j
            yield "comment", src[i:j]
            i = j
        elif c in "\"'":
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == "\\":
                    j += 1
                    # \z skips following whitespace; it's still inside the string
                j += 1
            yield "string", src[i:j + 1]
            i = j + 1
        elif c == "`":
            # Luau interpolated string: keep as-is (no comments can start inside)
            j = i + 1
            while j < n and src[j] != "`":
                if src[j] == "\\":
                    j += 1
                j += 1
            yield "string", src[i:j + 1]
            i = j + 1
        elif c == "[" and re.match(r"\[=*\[", src[i:]):
            m = re.match(r"\[(=*)\[", src[i:])
            close = "]" + m.group(1) + "]"
            j = src.find(close, i + len(m.group(0)))
            j = n if j < 0 else j + len(close)
            yield "string", src[i:j]
            i = j
        elif c.isspace():
            j = i
            while j < n and src[j].isspace():
                j += 1
            yield "space", src[i:j]
            i = j
        else:
            j = i
            while j < n and not src[j].isspace() and src[j] not in "\"'`" \
                    and not src.startswith("--", j) and not (src[j] == "[" and re.match(r"\[=*\[", src[j:])):
                j += 1
            if j == i:
                j = i + 1
            yield "code", src[i:j]
            i = j


def strip(src):
    out = []
    for kind, text in lex(src):
        if kind == "comment":
            # keep the line breaks a block comment covered
            out.append("\n" * text.count("\n"))
        elif kind == "space":
            nl = text.count("\n")
            out.append("\n" * nl if nl else " ")
        else:
            out.append(text)
    lines = [line.strip() for line in "".join(out).split("\n")]
    return "\n".join(lines).strip() + "\n"


def encode(src, name):
    data = src.encode("utf-8")
    key = [random.randrange(256) for _ in range(23)]
    enc = bytes(b ^ key[i % len(key)] ^ ((i + 1) * 7 % 256) for i, b in enumerate(data))
    hexdata = enc.hex()
    keys = ",".join(str(k) for k in key)
    # bxor of three values: Luau bit32.bxor takes varargs
    return (
        "local D=\"" + hexdata + "\"\n"
        "local K={" + keys + "}\n"
        "local o,n,c,x,s=table.create and table.create(#D/2) or {},#K,0,bit32.bxor,string.char\n"
        "for i=1,#D,2 do c=c+1 o[c]=s(x(tonumber(string.sub(D,i,i+1),16),K[(c-1)%n+1],c*7%256)) end\n"
        "return assert(loadstring(table.concat(o),\"=" + name + "\"))(...)\n"
    )


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    for name in sorted(os.listdir(".")):
        if not name.endswith(".lua") or name in SKIP:
            continue
        with open(name, encoding="utf-8") as f:
            src = f.read()
        with open(os.path.join(out_dir, name), "w", encoding="utf-8") as f:
            f.write(encode(strip(src), name[:-4]))
        print(name)


if __name__ == "__main__":
    main()
