"""
สร้างไฟล์ HauntedEscape.rbxlx จากโฟลเดอร์ src/ (ไม่ต้องติดตั้ง Rojo)
วิธีใช้:  python3 build_place.py
"""
import os
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "src")
OUT = os.path.join(ROOT, "HauntedEscape.rbxlx")

ref_counter = [0]


def ref():
    ref_counter[0] += 1
    return "RBX%08d" % ref_counter[0]


def item(cls, name, children="", source=None, extra=""):
    props = '<string name="Name">%s</string>' % escape(name) + extra
    if source is not None:
        assert "]]>" not in source
        props += '<ProtectedString name="Source"><![CDATA[%s]]></ProtectedString>' % source
    return '<Item class="%s" referent="%s"><Properties>%s</Properties>%s</Item>\n' % (cls, ref(), props, children)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def script_class(filename):
    if filename.endswith(".server.lua"):
        return "Script", filename[: -len(".server.lua")]
    if filename.endswith(".client.lua"):
        return "LocalScript", filename[: -len(".client.lua")]
    return "ModuleScript", filename[: -len(".lua")]


def build_dir(path, name):
    """โฟลเดอร์แบบ Rojo: ถ้ามี init.*.lua จะกลายเป็นสคริปต์ที่มีลูก ไม่งั้นเป็น Folder"""
    files = sorted(os.listdir(path))
    init = next((f for f in files if f.startswith("init.") and f.endswith(".lua")), None)
    children = ""
    for f in files:
        full = os.path.join(path, f)
        if f == init:
            continue
        if os.path.isdir(full):
            children += build_dir(full, f)
        elif f.endswith(".lua"):
            cls, n = script_class(f)
            children += item(cls, n, source=read(full))
    if init:
        cls, _ = script_class(init.replace("init", "x", 1))
        return item(cls, name, children, source=read(os.path.join(path, init)))
    return item("Folder", name, children)


def main():
    rs = item("ReplicatedStorage", "ReplicatedStorage",
              build_dir(os.path.join(SRC, "ReplicatedStorage", "HorrorShared"), "HorrorShared"))
    sss = item("ServerScriptService", "ServerScriptService",
               build_dir(os.path.join(SRC, "ServerScriptService", "HorrorServer"), "HorrorServer"))
    client_path = os.path.join(SRC, "StarterPlayer", "StarterPlayerScripts", "HorrorClient.client.lua")
    sps = item("StarterPlayerScripts", "StarterPlayerScripts",
               item("LocalScript", "HorrorClient", source=read(client_path)))
    sp = item("StarterPlayer", "StarterPlayer", sps)
    # แสงแบบ Future = เงาจริงจากไฟฉาย/โคมไฟ (สคริปต์ตั้งค่านี้เองไม่ได้ ต้องฝังในไฟล์เพลส)
    lighting = item("Lighting", "Lighting", extra=(
        '<token name="Technology">4</token>'
        '<bool name="GlobalShadows">true</bool>'
        '<float name="EnvironmentDiffuseScale">1</float>'
        '<float name="EnvironmentSpecularScale">1</float>'
        '<float name="ClockTime">0</float>'
    ))
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
           + lighting + rs + sss + sp + "</roblox>\n")
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(xml)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
