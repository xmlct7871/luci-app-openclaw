#!/usr/bin/env python3
"""
verify_apk.py — 验证 build_apk.sh 产出的 apk 是否符合 Alpine apk v2 规范

不依赖 apk-tools-static (Windows 跑不了 Linux ELF), 用 Python 解 tar + 算 hash.
"""
import gzip
import hashlib
import sys
import tarfile
from pathlib import PurePosixPath


def fail(msg):
    print(f"  [FAIL] {msg}", file=sys.stderr)
    sys.exit(1)


def ok(msg):
    print(f"  [OK]   {msg}")


def main(path):
    print(f"==> 验证 {path}\n")

    # 1. 单 gz 流: 必须能用 gzip 完整解压
    with open(path, "rb") as f:
        raw = f.read()
    try:
        decompressed = gzip.decompress(raw)
    except Exception as e:
        fail(f"gzip 解压失败: {e}")
    ok(f"gzip 解压通过 (compressed={len(raw)}, decompressed={len(decompressed)})")

    # 2. tar 头部合法, PAX 格式
    import io
    try:
        tf = tarfile.open(fileobj=io.BytesIO(decompressed), mode="r:")
    except Exception as e:
        fail(f"tarfile.open 失败: {e}")
    members = tf.getmembers()
    ok(f"tar 解析通过 (entries={len(members)})")

    # 3. 找 .PKGINFO
    pkginfo_member = None
    for m in members:
        if m.name == ".PKGINFO":
            pkginfo_member = m
            break
    if pkginfo_member is None:
        fail("tar 内无 .PKGINFO")
    ok(".PKGINFO 存在")

    # 4. 解析 .PKGINFO
    pkginfo_text = tf.extractfile(pkginfo_member).read().decode("utf-8", "replace")
    pkginfo = {}
    for line in pkginfo_text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if " = " in line:
            k, v = line.split(" = ", 1)
            pkginfo[k.strip()] = v.strip()
    ok(f".PKGINFO 字段: {sorted(pkginfo.keys())}")

    # 必填字段
    for required in ["pkgname", "pkgver", "size", "datahash"]:
        if required not in pkginfo:
            fail(f".PKGINFO 缺字段: {required}")

    # 5. 按 tar 顺序拼接所有数据文件 (排除 .PKGINFO), 算 sha256 对比 datahash
    declared_size = int(pkginfo["size"])
    declared_hash = pkginfo["datahash"]
    actual_hash = hashlib.sha256()
    actual_size = 0
    count = 0
    for m in members:
        if m.name == ".PKGINFO":
            continue
        # 取的是数据 (脚本内容或文件)
        if not m.isfile():
            # 目录条目没有数据
            continue
        data = tf.extractfile(m).read()
        actual_hash.update(data)
        actual_size += len(data)
        count += 1

    print()
    print(f"  声明 size = {declared_size}")
    print(f"  实际 size = {actual_size} (data 文件 {count} 个)")
    if declared_size != actual_size:
        fail(f"size 不匹配! 差 {actual_size - declared_size} bytes")
    ok("size 匹配")
    print()

    print(f"  声明 datahash = {declared_hash}")
    print(f"  实际 datahash = {actual_hash.hexdigest()}")
    if declared_hash != actual_hash.hexdigest():
        fail("datahash 不匹配!")
    ok("datahash 匹配")
    print()

    # 6. 列 scriptlet 与核心条目
    print("==> 关键条目")
    scriptlets = [".pre-install", ".post-install",
                  ".pre-deinstall", ".post-deinstall"]
    for s in scriptlets:
        present = any(m.name == s for m in members)
        flag = "[OK]   " if present else "[FAIL] "
        print(f"  {flag}{s}")
        if not present:
            fail(f"缺 scriptlet: {s}")

    # 7. 文件类型分布
    print("\n==> 文件类型分布")
    type_counts = {}
    for m in members:
        type_counts[m.type] = type_counts.get(m.type, 0) + 1
    type_names = {b"0": "regular", b"5": "dir", b"g": "pax global",
                  b"x": "pax extended", b"L": "long name"}
    for t, c in sorted(type_counts.items()):
        tn = type_names.get(t, t.decode("ascii", "replace"))
        print(f"  type {t.decode('ascii', 'replace') or '?'} ({tn}): {c}")

    print("\nAll checks passed.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: verify_apk.py <file.apk>", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1])
