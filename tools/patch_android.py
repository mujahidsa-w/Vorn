"""Patch the Flutter-generated Android project for Vexo (run in CI after `flutter create`)."""
import glob
import re

MANIFEST = "android/app/src/main/AndroidManifest.xml"
PERMS = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.RECORD_AUDIO"/>',
    '<uses-permission android:name="android.permission.CAMERA"/>',
    '<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>',
    '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>',
]

s = open(MANIFEST, encoding="utf-8").read()
for perm in PERMS:
    if perm not in s:
        s = re.sub(r"(<manifest[^>]*>)", r"\1\n    " + perm, s, count=1)
open(MANIFEST, "w", encoding="utf-8").write(s)

# Firebase and the record plugin need minSdk 23+.
for gradle in glob.glob("android/app/build.gradle*"):
    t = open(gradle, encoding="utf-8").read()
    t = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdk = 23", t)
    open(gradle, "w", encoding="utf-8").write(t)

print("Android project patched")
