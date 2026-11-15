# NVIDIA Shield Netflix Button Neutralizer

> **DISCLAIMER:** This software and documentation are provided **"AS IS"**, without warranty of any kind, express or implied. You are solely responsible for any modifications made to your device. The authors and contributors are not responsible for any device issues, app incompatibilities, account problems, or unintended behavior resulting from the use of this project. Proceed at your own risk.

Builds and sideloads a zero-permission, zero-daemon dummy `com.netflix.ninja` APK that intercepts the Shield remote's Netflix button at the Android package-resolution layer. Instead of opening Netflix or redirecting to the Google Play Store, the button launches an invisible activity that terminates immediately (`Theme.NoDisplay` + `finish()`), leaving your current video or game uninterrupted.

## How It Works (Under the Hood)

When you press the physical Netflix button on the Shield remote, the firmware does not hardcode a direct jump to the Play Store. Instead, Shield OS runs a standard Android package launch sequence:

1. **Keycode to Package Mapping:** The remote sends a hardware keycode (`KEYCODE_BUTTON_12` on the 2019 Shield remote). Shield OS's `PhoneWindowManager` intercepts this keycode at the system level before any foreground app sees it and looks up the launch intent for package `com.netflix.ninja` via `PackageManager.getLaunchIntentForPackage("com.netflix.ninja")`.
2. **Manifest Intent Resolution:** Android's `PackageManager` inspects the installed `com.netflix.ninja` package's `AndroidManifest.xml` for an exported `<activity>` declaring `android.intent.action.MAIN` with category `LAUNCHER` or `LEANBACK_LAUNCHER`.
   * **If no matching package is installed (or it is disabled):** Shield OS falls back to firing an implicit `market://details?id=com.netflix.ninja` intent, which opens the Google Play Store install page.
   * **If this dummy APK is installed:** `PackageManager` resolves the intent to `.MainActivity` inside our stub package, and Android's `ActivityManager` starts that activity.
3. **Zero-UI Execution & Immediate Teardown:**
   * `AndroidManifest.xml` applies `android:theme="@android:style/Theme.NoDisplay"` along with `excludeFromRecents="true"` and `noHistory="true"`. Because of `Theme.NoDisplay`, Android never allocates a window surface, draws a frame, or steals visual focus from your active media player or game.
   * Inside `MainActivity.onCreate()`, the app executes a single call (`finish()`) and returns immediately. Android destroys the activity before `onResume()` or window rendering ever occurs, leaving zero background services or lingering processes in memory.


```mermaid
    A[Physical Netflix Button Press<br/>e.g. KEYCODE_BUTTON_12] --> B["Input Driver & Keylayout<br/>(/system/usr/keylayout/*.kl)"]
    B -->|"[3] Root Keylayout Edit<br/>Remaps or drops keycode"| C[Shield OS PhoneWindowManager]
    C -->|"[2] Accessibility Service<br/>Intercepts key event in daemon"| D["PackageManager Lookup<br/>getLaunchIntentForPackage('com.netflix.ninja')"]
    D --> E{Is com.netflix.ninja<br/>installed & enabled?}
    E -->|"[4] THIS DUMMY APK<br/>Manifest MAIN/LEANBACK_LAUNCHER<br/>NoDisplay Activity calls finish() in onCreate()"| F[Immediate Activity Teardown<br/>No window drawn, playback uninterrupted]
    E -->|No / Disabled| G[Play Store Fallback Intent<br/>market://details?id=com.netflix.ninja]
    G -->|"[1] Disable Play Store<br/>Breaks updates & licensing"| H[Google Play Store<br/>Netflix Install Page]
```


## Why This Approach? (Motivation & Alternatives)

Accidentally brushing the prominent Netflix button on the Shield remote immediately suspends active playback or gaming and, if Netflix is uninstalled, opens the Google Play Store to the Netflix install page. Existing workarounds each carry heavy trade-offs:

1. **Disabling the Google Play Store (`pm disable-user com.android.vending`):** Blocks the Play Store redirect, but breaks automatic app updates, Play Services licensing checks, and the ability to install or update other Android TV apps.
2. **Accessibility Service Key Remappers (e.g., Button Mapper, tvQuickActions):**
   * **Principle of Least Privilege (PoLP) violation:** Enabling `BIND_ACCESSIBILITY_SERVICE` grants a third-party app global visibility into UI events, window state changes, and keystrokes across the entire OS just to ignore a single hardware button.
   * **Runtime overhead:** Requires a persistent background daemon that consumes memory and can introduce input latency or D-pad focus quirks in Leanback/Android TV interfaces.
3. **Root / Keylayout Edits (`/system/usr/keylayout/`):** Requires unlocking the bootloader, wiping user data, breaking Widevine L1 DRM (degrading 4K HDR streaming in other apps), and re-applying edits after every Shield Experience OTA update.
4. **This Dummy APK (`com.netflix.ninja` Stub):** Satisfies the OS launch intent natively at the package-resolution layer. It requires no root, keeps the Google Play Store fully functional, adheres strictly to the Principle of Least Privilege with zero requested permissions, leaves no background daemon running (`Theme.NoDisplay` + immediate `finish()`), and uses `versionCode=999999` so Play Store auto-updates never overwrite it.

## Tested & Expected Targets

### Verified Test Environment

* **Device:** NVIDIA Shield TV Pro (2019) (`SHIELD Android TV`, board codename `mdarcy`)
* **Firmware:** Android 11 (API 30), Build `RQ1A.210105.003.7825230_4387.0822` (Shield Experience 9.x)
* **Remote:** NVIDIA Shield Remote (2019 triangular backlit remote with dedicated Netflix button, `KEYCODE_BUTTON_12` / keycode `199`)
* **Host Build Environment:** Ubuntu Linux (`x86_64`) with OpenJDK + `google-android-build-tools-35.0.1`

### Expected Compatible Targets

Because the dummy APK responds to the `com.netflix.ninja` package launch intent rather than listening for a specific hardware keycode, it works on any non-rooted Android TV / Google TV setup where:

1. The OS routes the remote's Netflix button press (regardless of remote model or keycode) to launch `com.netflix.ninja` (falling back to `market://details?id=com.netflix.ninja` when missing or disabled).
2. `com.netflix.ninja` is preloaded as a user-uninstallable app rather than baked into a read-only system partition.

*(Note: The same pattern works for any other hardcoded partner button that the OS routes to a user-replaceable package, though adapting the package name in `AndroidManifest.xml`, `MainActivity.java`, and `scripts/common.sh` is out of scope for this repository.)*

Expected compatible hardware includes:

* **NVIDIA Shield TV Pro (2019, `mdarcy`)** and **NVIDIA Shield TV (2019 Tube, `sif`)** on Shield Experience 8.x to 9.x (Android 9 to 11).
* **NVIDIA Shield TV (2015 `foster` / 2017 `darcy`)** on Shield Experience 8.x to 9.x when used with a 2019 Shield Remote or any third-party remote whose Netflix button is mapped by Shield OS to `com.netflix.ninja`.
* **Other Android TV / Google TV streamers** (such as Chromecast with Google TV or Walmart Onn 4K boxes) where Netflix can be uninstalled from **Settings -> Apps** without root.

### Known Limitations (Incompatible Firmware Builds)

* **System-partition Netflix preloads:** Older Shield Experience images (pre-9.0 on certain regional SKUs) or locked-down OEM TVs that bake `com.netflix.ninja` into read-only `/system`, `/vendor`, or `/product` partitions signed with Netflix's production certificate cannot install this stub (`adb install` will fail with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`). On those builds, disable the system package instead (`adb shell pm disable-user --user 0 com.netflix.ninja`) or use an Accessibility key remapper.
* **Host OS:** `make deps` targets Debian/Ubuntu (`apt`). macOS and other Linux distributions are supported if `adb`, `javac` (JDK 8+), `d8`, `aapt2`, `zipalign`, `keytool`, and `apksigner` are available in `PATH`.

## Verify Your Device Is Supported

With `SHIELD_IP` configured in `config.env` and **Network debugging** temporarily enabled on your Shield, run the automated pre-flight check:

```bash
make check
```

> **Watch your TV screen:** The first time your host connects over ADB, Android TV displays an **"Allow network debugging?"** RSA key confirmation dialog on the TV. Look at your TV screen and select **Allow** (or **Always allow from this computer**) with the Shield remote, otherwise the ADB connection will stay in `unauthorized` state or time out.

Or run the raw ADB check manually:

```bash
adb connect <SHIELD_IP>:5555 && \
adb -s <SHIELD_IP>:5555 shell getprop | grep -E "ro\.product\.(model|device)|ro\.build\.version\.(release|sdk)" && \
adb -s <SHIELD_IP>:5555 shell pm path com.netflix.ninja
```

Check the `pm path com.netflix.ninja` output:

* **No output** (not installed) or **`package:/data/app/...`** (user-space app): **Supported.** Proceed with Quick Start below.
* **`package:/system/...`**, **`package:/vendor/...`**, or **`package:/product/...`**: **Unsupported for APK replacement.** Netflix is baked into a read-only system partition; run `adb shell pm disable-user --user 0 com.netflix.ninja` instead.

## Quick Start

1. **Install build dependencies (Ubuntu/Debian):**

   ```bash
   make deps
   ```

2. **Configure your Shield IP:**

   ```bash
   cp config.env.example config.env
   # Edit SHIELD_IP in config.env
   ```

3. **Enable Network Debugging on the Shield:**

   * Go to **Settings -> Device Preferences -> About** and click **Build** 7 times.
   * Go to **Settings -> Device Preferences -> Developer options** and enable **Network debugging**.

4. **Build, install, and audit:**

   ```bash
   make all
   ```

   **Watch your TV screen** and approve the **"Allow network debugging?"** prompt with your remote when it appears (if not already authorized during `make check`), then follow the interactive security prompt in your terminal to switch **Network debugging** and **Developer options** **Off** once installation completes.

## Reverting to Official Netflix

If you want to restore the official Netflix app later:

1. **Uninstall the dummy app:**
   * **On the Shield UI:** Go to **Settings -> Apps -> See all apps -> Netflix Dummy** and select **Uninstall**, **or**
   * **Via ADB** (with Network debugging temporarily enabled):
     ```bash
     adb connect <SHIELD_IP>:5555
     adb -s <SHIELD_IP>:5555 uninstall com.netflix.ninja
     ```
     Remember to turn **Network debugging** and **Developer options** back **Off** afterward.
2. **Reinstall Netflix from the Google Play Store:**
   * Open the **Google Play Store** on the Shield (or simply press the physical Netflix button on the remote to open its Play Store listing) and select **Install**.
3. **First-launch compatibility notice:**
   * On the first launch after reinstalling, Netflix may display a notice stating that the device is not optimized for Netflix. Dismiss/confirm the prompt (it may appear once or twice), after which Netflix loads and operates normally.

## Make Targets

* `make all`: Builds, signs, installs, audits the dummy APK, and verifies port `5555` is closed.
* `make build`: Compiles and signs `dist/netflix-dummy.apk` (caches `build/framework-res.apk`).
* `make check`: Verifies target device model/codename, confirms `com.netflix.ninja` is not locked on a system partition, and checks port `5555` lockdown.
* `make install`: Sideloads `dist/netflix-dummy.apk`, audits permissions/PID, and verifies port `5555` is closed.
* `make audit`: Verifies package signature, `versionCode`, zero permissions, zero background PID, and port `5555` lockdown.
* `make clean`: Removes `build/` and `dist/` artifacts (preserves `keystore/`).

## Security & Resource Footprint

* **Zero Permissions:** `AndroidManifest.xml` declares no `<uses-permission>` entries.
* **Zero Background Overhead:** `MainActivity` uses `@android:style/Theme.NoDisplay` and invokes `finish()` inside `onCreate()`, leaving no running process or background service in memory.
* **OTA Update Protection:** Packaged with `versionCode=999999` so Google Play Store never attempts to overwrite the stub with an update.

## References & Prior Art

* **XDA Developers Forums (`yani2000`, Dec 2020):** [[APP][NOROOT/NOADS][AndroidTV][5.0+] Prime Video / Netflix / Spotify / orthers Button Mapper](https://xdaforums.com/t/app-noroot-noads-androidtv-5-0-prime-video-netflix-spotify-orthers-button-mapper.4203823/) — Early community implementation demonstrating no-root Android TV remote button interception via package-name substitution (`com.netflix.ninja`) without Accessibility services.
* **Android Developers Documentation:** [Activity Lifecycle](https://developer.android.com/guide/components/activities/activity-lifecycle) and [Manifest Activity Styles](https://developer.android.com/reference/android/R.style#Theme_NoDisplay) (`Theme.NoDisplay`).
