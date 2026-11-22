---
name: local-apk-builds
description: "User previews tourist/owner apps as locally built release APKs (Android Studio JBR + adb), not EAS cloud or Expo Go; android/ folders are gitignored and regenerated"
metadata:
  node_type: memory
  type: project
  originSessionId: 162d81f4-6f65-46ef-a6c4-be85b2293c7c
  modified: 2026-11-15T17:40:07.787Z
---

Since 2026-09-17 the user installs standalone release APKs on their phone instead of EAS builds (30–40 min queue) or Expo Go (needs laptop running).

Command per app, phone on USB: `JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"` then `npx expo run:android --variant release --no-bundler`. Default `java` is JDK 25 (too new); JBR is JDK 17.

**Why:** user wanted Flutter-like local builds; hates EAS wait. `android/` folders are gitignored — if a build fails with `hermes-compiler`/null getAbsolutePath, run `npx expo prebuild --clean --platform android --no-install` first (stale template).
Version bumps: app.json version/versionCode do NOT reach an existing android/ folder. Also edit android/app/build.gradle (versionCode, versionName) or prebuild --clean, then confirm with `adb shell dumpsys package com.ipilgo.tourist | grep versionName`. (2026-11-16: first 1.8.0 build installed as 1.7.2.)
**How to apply:** offer "rebuild tourist/owner" after code changes; never suggest EAS build for previews. Local signing key now installed on phone, so no more uninstall needed.

Release folder layout (user preference, 2026-10-11): every version gets its own subfolder in THESIS_IPILGO/release-files (v1.0.0/, v1.1.0/, v1.1.1/ …), each holding IpilGo-Tourist.apk + IpilGo-Owner.apk. Never leave APKs loose at the top level; the newest folder is the one to upload.
