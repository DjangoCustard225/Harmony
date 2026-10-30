#!/usr/bin/env python3
"""Verify the unsigned native build before uploading it."""

import hashlib
import plistlib
import sys
import zipfile
from pathlib import Path

ipa = Path(sys.argv[1])
assert ipa.name == "Harmony.ipa", "Unexpected IPA filename"
expected = plistlib.loads(Path("Harmony/Info.plist").read_bytes())
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None, "Damaged IPA"
    names = set(archive.namelist())
    app = "Payload/Harmony.app/"
    info = plistlib.loads(archive.read(app + "Info.plist"))
    assert info["CFBundleIdentifier"] == "app.harmony.music"
    for key in ("CFBundleDisplayName", "CFBundleShortVersionString", "CFBundleVersion"):
        assert info[key] == expected[key], f"Unexpected {key}"
    assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Not a device build"
    icon = info["CFBundleIcons"]["CFBundlePrimaryIcon"]
    if icon.get("CFBundleIconName") == "HarmonyIcon":
        assert app + "Assets.car" in names, "Compiled icon catalog missing"
        icon_kind = "native icon"
    else:
        assert icon.get("CFBundleIconFiles") == ["AppIcon"], "Unexpected PNG icon selection"
        assert archive.read(app + "AppIcon.png") == Path("AppIcon.png").read_bytes(), "Unexpected PNG icon"
        assert archive.read(app + "HarmonyMark.png") == Path("Harmony/Assets.xcassets/HarmonyMark.imageset/HarmonyMark.png").read_bytes(), "Unexpected in-app brand mark"
        icon_kind = "PNG icon"
    assert info["MinimumOSVersion"] == "27.0", "Unexpected minimum iOS version"
    assert info.get("UIBackgroundModes") == ["audio"], "Background playback missing"
    assert info.get("UIFileSharingEnabled") is True, "Files access missing"
    assert info.get("LSSupportsOpeningDocumentsInPlace") is True, "Document access missing"
    assert any("public.audio" in document.get("LSItemContentTypes", [])
               for document in info.get("CFBundleDocumentTypes", [])), "Audio file association missing"
    assert app + "PrivacyInfo.xcprivacy" in names, "Privacy manifest missing"
    assert "NSAppTransportSecurity" not in info, "Unexpected network transport exception"
    assert not any("/_CodeSignature/" in name or name.endswith("embedded.mobileprovision") for name in names), "IPA must be unsigned"
    executable = archive.read(app + info["CFBundleExecutable"])
    assert executable[:4] == b"\xcf\xfa\xed\xfe", "Expected a 64-bit Mach-O executable"
    assert int.from_bytes(executable[4:8], "little") == 0x0100000C, "Expected arm64"
print(f"Verified {ipa.name}: version {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), {icon_kind}, arm64, unsigned")
print(f"SHA256 {hashlib.sha256(ipa.read_bytes()).hexdigest()}")
