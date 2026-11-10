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
    # Android 13+: needed to show message notifications.
    '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
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
    # flutter_webrtc's AndroidX dependencies require compiling against API 34+.
    t = re.sub(r"compileSdk(Version)?\s*=?\s*(flutter\.compileSdkVersion|\d+)", "compileSdk = 36", t)
    open(gradle, "w", encoding="utf-8").write(t)

print("Android project patched")

# Firebase Cloud Messaging on Android needs the google-services Gradle plugin.
SETTINGS = "android/settings.gradle.kts"
APP_GRADLE = "android/app/build.gradle.kts"
try:
    st = open(SETTINGS, encoding="utf-8").read()
    if "com.google.gms.google-services" not in st:
        st = re.sub(
            r'(\s*id\("com\.android\.application"\)[^\n]*\n)',
            r'\1    id("com.google.gms.google-services") version "4.4.2" apply false\n',
            st, count=1)
        open(SETTINGS, "w", encoding="utf-8").write(st)
    ag = open(APP_GRADLE, encoding="utf-8").read()
    if "com.google.gms.google-services" not in ag:
        ag = re.sub(
            r'(\s*id\("com\.android\.application"\)[^\n]*\n)',
            r'\1    id("com.google.gms.google-services")\n',
            ag, count=1)
        open(APP_GRADLE, "w", encoding="utf-8").write(ag)
    print("google-services plugin added")
except FileNotFoundError as e:
    print("skipped google-services patch:", e)
