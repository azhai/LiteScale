# LiteScale

<p>
  <a href="https://flutter.dev"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white"></a>
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white">
  <img alt="Version" src="https://img.shields.io/badge/version-1.1.1-0E7C6B">
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Android%20%C2%B7%20macOS%20%C2%B7%20iOS%20%C2%B7%20Windows%20%C2%B7%20Linux-4C6EF5">
</p>

**English** · [简体中文](README.zh-CN.md)

A weight tracker for **OKOK / Chipsea BLE scales** — no vendor app, no account, no cloud
unless you want one. It reads the scale's advertisement packets directly, keeps everything
local, and can sync to a self-hosted server written in Odin.

| Measure | History | Devices | Settings |
|:--:|:--:|:--:|:--:|
| <img src="docs/screenshots/ui-measure.png" width="180"> | <img src="docs/screenshots/ui-history.png" width="180"> | <img src="docs/screenshots/ui-devices.png" width="180"> | <img src="docs/screenshots/ui-settings.png" width="180"> |

<sub>Screenshots are rendered from the real widget tree by `scripts/screenshots.sh`
(2×, iPhone 13 metrics), so they cannot drift from the UI without a test run noticing.</sub>

## What it does

* **Advertisement-only reading.** No GATT handshake, no pairing: the scale broadcasts the
  weight in its BLE advertisement and the app decodes it — so a reading lands while the
  scale is still showing the number.
* **Household members.** Each member has their own avatar, height, gender, birth month and
  any number of dated goals (target date + target weight).
* **History with four filters.** Time range (7 d / 30 d / 90 d / all), member, device, plus
  per-record reassignment and a 7-day moving average on the chart.
* **Transport-agnostic.** A `ScaleSource` registry keeps the UI independent of BLE, so new
  sources can be added without touching pages.
* **CSV in and out.** Same column schema as the server, so exports round-trip cleanly.
* **Optional self-hosted sync.** Opt-in in Settings, exactly-once via content hashes.
* **A WeChat mini program** with the same protocol, data model and CSV format.

## Repository layout

```
lib/                     Flutter app
  model/                 Member, WeightRecord, goals, avatars
  source/                ScaleSource interface + BLE advertisement decoder
  service/               AppController (state), uploader, CSV, units, file saver
  view/                  theme.dart, four pages, shared widgets
  i18n/strings.dart      hand-rolled zh/en strings (no flutter_localizations)
server/                  Odin sync server (opus + oboe HTTP, SQLite)
miniprogram/             WeChat mini program (vanilla JS, canvas chart)
scripts/                 build, packaging, icon and screenshot tooling
test/                    widget, CSV, avatar and upload tests
docs/screenshots/        images used by this README
```

## Getting started

Requirements: Flutter 3.x, a device with BLE (Android 6+, iOS 11+, or a desktop), and an
OKOK / Chipsea-compatible scale.

```bash
git clone https://git.home504.io/ryan/LiteScale.git
cd LiteScale
flutter pub get
flutter run
```

The app scans on the Measure tab; step on the scale while it scans and the reading appears.
Every scale that produced a reading is remembered on the Devices tab.

**Android permissions** (already declared in `android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

## Build and release

`version:` in `pubspec.yaml` is the single source of truth (`1.1.1+10` today). Every script
sources `scripts/common.sh`, which derives names from the project instead of hard-coded
strings:

| value | source |
|---|---|
| package id (`litescale`) | `name:` in `pubspec.yaml` |
| display / artefact name (`LiteScale`) | `PRODUCT_NAME` in `macos/Runner/Configs/AppInfo.xcconfig` (override with `APP_NAME=...`) |
| version / build number | `version:` in `pubspec.yaml` |

Artefacts land in `dist/` as `LiteScale-<version>-<target>`:

```bash
./scripts/build_android.sh      # dist/LiteScale-1.1.1-android-arm64-v8a.apk
./scripts/build_ios.sh          # dist/LiteScale-1.1.1-ios-arm64-unsigned.ipa  (macOS + Xcode)
./scripts/build_macos.sh arm64  # dist/LiteScale-1.1.1-macos-arm64.dmg        (macOS only)
./scripts/build_macos.sh x64    # dist/LiteScale-1.1.1-macos-x64.dmg          (macOS only)
./scripts/build_windows.sh      # dist/LiteScale-1.1.1-windows-x64.zip        (Windows + MSVC only)
./scripts/build_server.sh       # dist/litescale-server-1.1.1-<os>-<arch>     (Odin, native host)
./scripts/build_server_linux.sh # dist/litescale-server-1.1.1-linux-x64       (any host with zig)
./scripts/build_all.sh          # every target possible on this host
```

Notes worth knowing before you ship:

* **App identity** — `top.xi-yun.litescale` on macOS/iOS/Linux, `top.xi_yun.litescale` on
  Android (Java package names reject `-`). These are OS-level identities: changing them
  makes every platform treat the app as brand new, with empty local data.
* **Android** is built with `--split-per-abi --target-platform android-arm64`, so the APK
  carries only `arm64-v8a`. Flutter rewrites `versionCode` per split
  (`abiCode * 1000 + buildNumber`), so build `9` reports `2009` — expected.
* **macOS** writes `macos/Runner/Configs/Arch.xcconfig` per build, because the Flutter CLI
  cannot pass `ARCHS` to xcodebuild. Builds are ad-hoc signed and not notarised: Gatekeeper
  needs right-click → Open. For public distribution use a Developer ID plus `notarytool`.
* **iOS** — `./scripts/build_ios.sh unsigned`, or
  `IOS_TEAM_ID=XXXXXXXXXX ./scripts/build_ios.sh ipa` (set
  `EXPORT_METHOD=ad-hoc|app-store`). Both need the iOS platform component
  (`xcodebuild -downloadPlatform iOS`).
* **Windows** cannot be cross-compiled — run `build_windows.sh` on Windows with Visual
  Studio (Desktop development with C++).
* **Linux server** is cross-compiled anywhere: Odin emits a `linux_amd64` object, zig links
  it against musl with statically built sqlite3 + zlib, giving one dependency-free static
  ELF. `LINUX_TARGET=aarch64-linux-musl LINUX_ARCH=arm64` switches architecture.
* Release APKs are signed with the debug key (`android/app/build.gradle.kts` →
  `signingConfigs.getByName("debug")`). Configure a real keystore before publishing.

## Server sync (optional)

Settings ▸ Server upload pushes members (height, gender, birth month), dated goals and
measurements to a self-hosted server. The server is Odin on top of `opus` + `oboe`, with
SQLite as the system of record — see [`server/README.md`](server/README.md) (Chinese) for
wire format, integrity checks, admin console and deployment.

```bash
make -C server build && make -C server run   # http://127.0.0.1:9429/admin/
```

* Upload is **opt-in and off by default**; nothing leaves the device until enabled.
* Default endpoint is `https://sc.xi-yun.top/`; change it in Settings.
* Every batch carries `X-Body-Sha256` and a body-derived `X-Idempotency-Key`, so retries are
  exactly-once; measurements also get a content-derived server-side UID.
* Upload is append-only: clearing history locally does not delete server data. Remove a
  client and its data from the admin console.

## WeChat mini program

`miniprogram/` is a standalone WeChat Mini Program: same advertisement-only protocol, same
data model, canvas chart, same CSV columns.

* Four tabs mirroring the app: Measure / History / Devices / Settings.
* Records are stored as `{t, kg, m, d}`; single-member data from older versions is migrated
  on launch (`utils/store.js` ▸ `migrate`).
* CSV export writes `<USER_DATA_PATH>/litescale-YYYY-MM-DD.csv` and opens the share sheet
  (`wx.shareFileMessage`); DevTools falls back to the clipboard. Import uses
  `wx.chooseMessageFile`.
* Set your own `appid` in `miniprogram/project.config.json` (placeholder is
  `touristappid`), then import the folder in WeChat DevTools.
* BLE scanning only works on a real device, not in the simulator.
* Protocol changes must be applied twice: `miniprogram/utils/protocol.js`
  (`parseAdvertisement`) **and** `lib/source/ble_adv_source.dart`.

## Data model and CSV

```csv
ts,client_id,device_id,device_name,member_id,member_name,kg
1793000000.123,c-macos-1a2b3c4d,C0:FF:EE:12:34:56,OKOK S3,m-1,我,68.4
```

* `ts` is Unix epoch seconds with exactly three decimals; `kg` is always kilograms.
* `client_id` is this install's uploader id (created on first sync); blank when the export
  came from an installation that never enabled upload.
* Import maps columns by header name first (so a server export imports as-is), ignores extra
  columns, and skips rows without a valid timestamp or weight. Unknown member names are
  created automatically; device names are remembered.
* Compatibility last: old headers (`ts_ms`, `timestamp`, `weight_kg`…), integer millisecond
  timestamps, ISO-8601 and header-less files still import.
* Export is UTF-8 **with BOM** so Excel opens it directly.
* Avatars, height, gender, birth month and goals are local preferences and deliberately
  excluded from CSV.
* Units: kilograms are the storage unit; display supports kg / 斤 (jin) / lb / st:lb.

## Measurement model

The scale broadcasts weight and an undocumented impedance byte — nothing else. So the app
shows weight, BMI and goal progress only; body fat, water, muscle and BMR were removed
because those numbers would be invented rather than measured.

## Design

Material 3 with a hand-tuned lake-green (湖绿) palette — `lib/view/theme.dart`:

* `Brand` holds the four brand colours; `Insets` / `Radii` the layout rhythm.
* `buildAppTheme()` derives every component theme from one text theme, so swapping
  `fontFamily` propagates everywhere — that is how the screenshot harness injects fonts.
* Shared pieces live in `lib/view/widgets/app_widgets.dart`: `AppCard`, `SectionHeader`,
  `StatTile`, `StatusPill`, `ChoicePill`, `EmptyState`, `WeightRing`.
* Controls are intrinsic-width (buttons, segmented controls, 104 px numeric fields) rather
  than full-bleed, so short labels never stretch across the screen.
* Avatars are illustrated PNGs under `assets/avatars/` (DiceBear *avataaars*, see
  `assets/avatars/ATTRIBUTION.md`); legacy emoji avatars map to a stable id on load.

## App icon

<img src="docs/icon-preview-256.png" width="88" align="right">

`scripts/icon_from_logo.py` turns `app-logo.png` into `app-icon-1024.png` plus the two
Android adaptive layers (gradient backdrop, scale plate), then `flutter_launcher_icons`
writes every platform size:

```bash
python3 scripts/icon_from_logo.py && flutter pub run flutter_launcher_icons
```

## Tests

```bash
flutter test             # widget, CSV, avatar and upload-gate tests
./scripts/screenshots.sh # regenerate docs/screenshots/*.png
```

The screenshot harness (`tool/screenshots/screens_test.dart`) seeds a two-member household,
fakes the BLE source, loads real fonts (Flutter's test runner ships none) and rasterises the
shell at 2× — the images above come from the same widgets users see.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `ANDROID_SPECIFIC_ERROR`, `Timed out` | The scale wants a specific connect sequence; retry and inspect the advertisement with nRF Connect. |
| Nothing found on Android 12+ | `BLUETOOTH_SCAN` not granted, or location services off. |
| macOS build: `module cache path …` | The project directory was renamed — `flutter clean`, delete `macos/Pods` and `Podfile.lock`. |
| `pod install` fails with `curl 56 … unexpected eof` | A proxy is breaking git clones of git-sourced pods: `git config --global http.version HTTP/1.1`. |
| `flutter test` dies with `Invalid WebSocket upgrade` | A local proxy is set; run with `env -u HTTP_PROXY -u HTTPS_PROXY …`. |
| Gradle: `Could not read workspace metadata … metadata.bin` | Cache was deleted under a running daemon: `./gradlew --stop`, then remove `~/.gradle/caches`. |

## Protocol references

* OKOK protocol notes: <https://github.com/oliexdev/openScale/files/5224454/OKOK.Protocol.pdf>
* Chipsea-based scale discussion: <https://github.com/oliexdev/openScale/issues/496>
* BLE inspection tool: [nRF Connect](https://www.nordicsemi.com/Products/Software-Tools/nRF-Connect-for-mobile)
* [`flutter_blue_plus`](https://pub.dev/packages/flutter_blue_plus)
