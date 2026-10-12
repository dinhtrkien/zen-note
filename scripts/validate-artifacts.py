"""Standard-library checks for generated transfer files; not an iPad UI test."""
from pathlib import Path
import re
import zipfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
archive = root / "artifacts" / "ZenNote-iPad.zip"
with zipfile.ZipFile(archive) as bundle:
    assert bundle.testzip() is None, "ZIP CRC failure"
    names = set(bundle.namelist())
    assert "START-HERE.txt" in names
    assert "ZenNote.swiftpm/AppInfo.plist" in names
    assert not any(".build/" in name or "/Tests/" in name or ".." in name.split("/") for name in names)
    manifest = bundle.read("ZenNote.swiftpm/Package.swift").decode()
    assert ".testTarget" not in manifest, "Transfer manifest references omitted tests"
    assert "AppleProductTypes" in manifest and ".iOSApplication(" in manifest
    assert "supportedInterfaceOrientations: [.landscapeLeft, .landscapeRight]" in manifest
    assert 'additionalInfoPlistContentFilePath: "AppInfo.plist"' in manifest
    plist = ET.fromstring(bundle.read("ZenNote.swiftpm/AppInfo.plist"))
    assert plist.find("dict/key").text == "UIRequiresFullScreen"
    assert plist.find("dict/true") is not None
    source_paths = list((root / "ZenNote.swiftpm" / "Sources").rglob("*.swift"))
    for source in source_paths:
        name = source.relative_to(root).as_posix()
        assert name in names, f"Missing source: {name}"
        assert bundle.read(name) == source.read_bytes(), f"Source differs: {name}"
print(f"ZIP passed: CRCs, {len(source_paths)} unmodified Swift sources, landscape manifest, no build/test artifacts")

pdf = (root / "artifacts" / "Practice-Textbook.pdf").read_bytes()
assert pdf.startswith(b"%PDF-1.4\n") and pdf.endswith(b"%%EOF\n")
xref_position = int(re.search(rb"startxref\n(\d+)\n%%EOF", pdf).group(1))
assert pdf[xref_position:].startswith(b"xref\n")
lines = pdf[xref_position:].splitlines()
object_count = int(lines[1].split()[1])
for object_id in range(1, object_count):
    offset = int(lines[2 + object_id].split()[0])
    assert pdf[offset:].startswith(f"{object_id} 0 obj\n".encode()), f"Bad xref for object {object_id}"
page_count = int(re.search(rb"/Type /Pages /Count (\d+)", pdf).group(1))
assert len(re.findall(rb"/Type /Page /Parent", pdf)) == page_count
if page_count >= 50:
    assert b"/Rotate 90" in pdf
if page_count >= 25:
    assert b"/CropBox [20 20 592 772]" in pdf
print(f"PDF passed: {page_count} pages, valid object offsets, rotated and cropped test pages")
