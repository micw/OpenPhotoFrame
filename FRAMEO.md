# Frameo device notes

Covers two frames: the Frameo 106K (retired, returned to Amazon) below, and the
Pexar Frame PX-110 that replaced it — see [Pexar Frame PX-110](#pexar-frame-px-110-mediatek-mt8167).

Device: Frameo 106K (10" photo frame)
SoC: Rockchip RK3326
Android: 11 (user build, `ro.debuggable=1`, SELinux permissive)
IP: 192.168.0.0
USB serial: `SERIAL_REDACTED`

## Rockchip RK3326 memtrack HAL crash loop

### What happens

The `android.hardware.memtrack@1.0-service` HAL crashes on every boot within the first 20 seconds. The crash is a `FORTIFY: readdir: null DIR*` abort inside `find_dir()` in `memtrack.rk3326.so` — a firmware bug in the Rockchip RK3326 vendor library.

Because the service has no `oneshot` flag in its RC file, Android init restarts it after each crash. Left unchecked, the crash loop consumes CPU, floods the crash log, and eventually destabilises the system (system_server dies, device becomes unresponsive).

The memtrack HAL only feeds diagnostic tools (memory profiling). Stopping it has no effect on normal operation.

### Automatic fix (app-based)

OpenPhotoFrame stops the service automatically on every boot. On `BOOT_COMPLETED`, `ScreenControlHandler.stopCrashingMemtrackService()` runs:

```kotlin
Runtime.getRuntime().exec(
    arrayOf("/system/xbin/su", "0", "/system/bin/stop", "vendor.memtrack-hal-1-0")
)
```

This works because:
- SELinux is permissive on this device — domain transitions are logged but not blocked
- The app process has `NoNewPrivs=0` and `Seccomp=0` — the setuid `su` binary gains root
- `stop` marks the service disabled in init; it will not restart until the next reboot

The fix only runs on Rockchip devices (detected via `Build.HARDWARE` containing `"rk"` or the presence of `/vendor/lib/hw/memtrack.rk3326.so`).

### Manual fallback

If the app hasn't launched yet or isn't installed, run the script with the USB cable plugged in:

```
./scripts/fix-frameo.sh
```

This stops the service via ADB root shell and re-enables WiFi ADB.

### Why a permanent firmware fix isn't possible

The RC file that needs `oneshot` added lives at `/vendor/etc/init/android.hardware.memtrack@1.0-service.rc`. The vendor partition is dm-verity protected:

- Direct writes to `/vendor` are blocked
- `adb disable-verity` fails (requires a userdebug build)
- `adb remount` sets up overlayfs, but the upper layer is a tmpfs at `/mnt/scratch` — not backed by persistent storage, so changes are lost on reboot
- There is no scratch partition in the partition table and no `/data/gsi/scratch.img`

Magisk would solve this (it injects scripts from `/data/adb/` before HAL services start) but requires flashing a custom boot image.

## OTA update reboots (adups FOTA)

### What happens

The device ships with `com.adups.fota` (Rockchip's firmware update service) and `android.rockchip.update.service`. Both register `RTC_WAKEUP` alarms and can trigger a clean `reboot` when they decide to check for or install firmware. The reboot leaves no crash trace — `sys.boot.reason` is simply `reboot` — making it look like a mystery crash.

Five services have been disabled for user 0:

```sh
adb shell pm disable-user --user 0 com.adups.fota
adb shell pm disable-user --user 0 android.rockchip.update.service
adb shell pm disable-user --user 0 net.frameo.frame
adb shell pm disable-user --user 0 com.cghs.stresstest
adb shell pm disable-user --user 0 com.DeviceTest
```

**Important — use `pm disable-user`, not `pm uninstall`.**

`pm uninstall -k --user 0` only removes the `/data/app/` update overlay. If the app ships in `/system/priv-app/` or `/system/app/`, Android silently reverts to that ROM copy, which then runs normally. `net.frameo.frame` lives at `/system/priv-app/Frameo.apk` — when the overlay was uninstalled, the ROM copy (v1.30.13) became active again, connected to Frameo's servers, downloaded an update, and triggered a clean `reboot` every 2–4 hours.

`pm disable-user --user 0` marks the package as `COMPONENT_ENABLED_STATE_DISABLED_USER` (enabled=3), which blocks both the ROM copy and any future updates from running.

`com.adups.fota` and `com.cghs.stresstest` are declared `android:persistent="true"`. Android's `ActivityManagerService` ignores `pm disable` for persistent apps — `pm disable` alone is not enough. `pm disable-user --user 0` still works because it marks the package as disabled for the user before ActivityManager evaluates persistence.

`com.cghs.stresstest` is a Rockchip factory stress-test tool that runs on a schedule and is designed to reboot the device as part of its test cycle. This was causing the ~3 hour reboot cycle observed after OTA services were removed.

If the device starts rebooting unexpectedly again, check `sys.boot.reason`. If it says `reboot` rather than `kernel_panic` or `watchdog`, an OTA service is likely responsible. Re-run the `pm uninstall` commands above.

## WiFi ADB

WiFi ADB (TCP mode) does not persist across reboots. To re-enable it after a reboot, plug in USB and run:

```
./scripts/fix-frameo.sh
```

Or manually:

```sh
adb -s SERIAL_REDACTED tcpip 5555
adb connect 192.168.0.0:5555
```

## eMMC failure and device retirement

### What happened

The Frameo 106K developed progressive eMMC (internal flash storage) failure over its life as a photo frame running OpenPhotoFrame.

**First crash (system partition):** Bad sectors appeared in the system partition (`mmcblk2p4`/`mmcblk2p6`), causing a kernel I/O error that brought down the device. The affected sectors mapped to system binaries (`statsd`, `audioserver`, `netd`, `wificond`, etc.).

**Mitigation — eMMC cache warming:** OpenPhotoFrame added a boot-time feature (toggleable in settings, off by default) that reads the affected system files into the page cache on startup. This prevents the kernel from needing to re-read those sectors from eMMC while daemons are running. Implemented in `ScreenControlHandler.warmEmmcFileCache()`.

**Second crash (userdata partition, ~1 hour later):** 13 new bad sectors appeared in `mmcblk2p15` (userdata, f2fs on `dm-6`). These mapped to:
- 4 JPEG photo files in OpenPhotoFrame's cache directory
- `IpMemoryStore.db` (network memory — not critical)
- f2fs node inode blocks (filesystem metadata — serious)

The node inode damage indicated the f2fs inode table itself was at risk, meaning the filesystem could become unmountable on the next crash.

### Diagnosis tools used

```sh
# Identify which partition a bad sector lives in
adb shell su 0 cat /proc/partitions
adb shell su 0 cat /sys/kernel/debug/mmc0/mmc0:0001/ext_csd   # eMMC health

# Map a bad sector to a file on f2fs
# (sector number from dmesg / Prometheus mmc_error_count metric)
# userdata starts at sector 6863612 on mmcblk2
# f2fs block = (bad_sector - partition_start) / 8
adb shell su 0 dump.f2fs -b <block> /dev/block/dm-6

# Find filename from inode number
adb shell su 0 find /data -inum <inode>
```

### Outcome

The eMMC failure region was spreading to new partitions. The device was beyond reliable software mitigation. Decision: factory reset and return to Amazon under hardware failure warranty.

eMMC failure is a documented failure mode for Frameo-brand devices. Community reports:
- https://forums.justuseapp.com/en/post/QERMOAEXL7/frameo-keeps-rebooting-over-and-over
- https://www.justanswer.com/electronics/tksy5-frameo-digital-photo-frame-stuck-rebooting.html
- https://www.devicepitfalls.com/frameo-stuck-on-startup-screen/

### Factory reset procedure

The recovery UI had only one physical button which activated the first menu item ("Reboot system now"), making menu navigation impossible. Factory reset was triggered via ADB:

```sh
# Write wipe command to recovery command file
adb -s SERIAL_REDACTED shell su 0 sh -c \
  'mkdir -p /cache/recovery && printf "--wipe_data\n" > /cache/recovery/command && sync'

# Reboot into recovery — it reads the command file and wipes automatically
adb -s SERIAL_REDACTED reboot recovery
```

After reset: `net.frameo.frame` (stock Frameo) present, `io.github.micw.openphotoframe` gone, `/data/media/0/frameo_files/media/` empty. Device verified clean and returned to Amazon.

## ADB quick reference

```sh
# USB
adb -s SERIAL_REDACTED shell

# WiFi (after enabling TCP mode)
adb -s 192.168.0.0:5555 shell

# Deploy APK
adb -s 192.168.0.0:5555 install -r build/app/outputs/flutter-apk/app-release.apk

# Check memtrack service status
adb -s 192.168.0.0:5555 shell getprop init.svc.vendor.memtrack-hal-1-0

# Stop memtrack manually (as root)
adb -s SERIAL_REDACTED shell stop vendor.memtrack-hal-1-0
```

# Pexar Frame PX-110 (MediaTek MT8167)

Replacement for the retired Frameo 106K. Different vendor and SoC, so none of the
Rockchip notes above apply — there is no memtrack HAL and no adups FOTA package.

Device: Pexar Frame, `ro.product.brand=Lexar`, `ro.product.device=dpf1106_mk_32`
SoC: MediaTek MT8167 (`ro.board.platform=mt8167`), 32-bit only (`armeabi-v7a`)
Android: 11 (user build, `ro.debuggable=0`, SELinux permissive)
RAM: 2 GB
USB serial: `FRAME_SERIAL_REDACTED`
IP: 192.168.0.0

Root works despite `ro.debuggable=0`: `/system/xbin/su` is setuid root and SELinux
is permissive.

```sh
adb shell /system/xbin/su 0 id   # uid=0(root) ... context=u:r:su:s0
```

## Build constraint: 32-bit only

`ro.product.cpu.abilist` is `armeabi-v7a,armeabi` — there is no arm64 slice. The
default `flutter build apk --release` fat APK works because it bundles
`armeabi-v7a` alongside `arm64-v8a` and `x86_64`. Building arm64-only
(`--target-platform android-arm64`) or picking the wrong split from
`--split-per-abi` produces an APK this frame cannot run. Check before deploying:

```sh
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep -o 'lib/[^/]*' | sort -u
# must include lib/armeabi-v7a
```

The two Rockchip-specific workarounds in the app are inert here, as intended:
`stopCrashingMemtrackService()` gates on `Build.HARDWARE` containing `"rk"`
(this device reports `mt8167`) and on `/vendor/lib/hw/memtrack.rk3326.so`, which
does not exist. The eMMC cache-warming feature is off by default and targets the
106K's failing sectors, so leave it off.

## Vendor install lock (`ro.vendor.custom_recover`)

### What happens

Out of the box every sideload fails, including as root:

```
Failure [INSTALL_FAILED_INVALID_APK: Package io.github.micw.openphotoframe is not allow to install. ]
```

The ROM patches `PackageManagerService.preparePackageLI` (in
`/system/framework/services.jar`) to gate installs on a property:

```java
if ("1".equals(SystemProperties.get("ro.vendor.custom_recover", "0"))) {
    if (!isSystemApp(pkg.getPackageName())) {
        throw new PrepareFailure(-2, "Package " + name + " is not allow to install. ");
    }
}
```

`MtkSystemUI` reads the same property from `CommandQueue.isRecoveryFirstBoot()`, and
`panelsEnabled()` returns false while it is `1`. So the flag is a kiosk lockdown
switch: it blocks sideloading *and* disables the notification shade.

### Where the value comes from

`/vendor/bin/nvram_daemon` publishes it. The relevant code (Thumb-2, at `0x2eb4`)
reads the 1024-byte product-info record, takes the byte at record offset `0x3FE`,
formats it, and calls `property_set("ro.vendor.custom_recover", <byte>)`.

That record is the head of the **`proinfo` partition**, not a file under
`/mnt/vendor/nvdata`. `proinfo` starts with the device serial, which is how to
confirm you have the right partition:

```sh
P=/dev/block/platform/soc/11120000.mmc/by-name/proinfo
adb shell "/system/xbin/su 0 dd if=$P bs=1 count=1024 2>/dev/null | od -A d -t x1"
# offset 0      serial "FRAME_SERIAL_REDACTED"
# offset 0x6e   Wi-Fi/BT MAC 84:5d:d7:0b:ce:85
# offset 0x3fe  the lock flag
```

### The fix

Clear byte 1022 and reboot. `proinfo` is a raw factory-data partition outside the
AVB chain, so this does not disturb verity.

```sh
P=/dev/block/platform/soc/11120000.mmc/by-name/proinfo
adb shell "/system/xbin/su 0 dd if=/dev/zero of=$P bs=1 seek=1022 count=1 conv=notrunc; sync"
adb reboot
adb shell getprop ro.vendor.custom_recover   # 0
```

Back the partition up first and diff afterwards — expect exactly one changed byte:

```sh
adb shell "/system/xbin/su 0 dd if=$P of=/data/local/tmp/proinfo.bak bs=4096"
adb pull /data/local/tmp/proinfo.bak backups/proinfo-FRAME_SERIAL_REDACTED.bak
```

A pre-change backup sits at `backups/proinfo-FRAME_SERIAL_REDACTED.bak`, untracked
(sha256 `2dbf2e37f726ce7e2a8417469c5ad00517f86113b248a1d22809d8ca62ed651e`). Keep it
somewhere safe — restoring it needs a frame that still boots.

Side effect, as expected from `panelsEnabled()`: the notification shade and quick
settings now pull down. Restoring the byte reverts both effects.

### Why not patch the system partition instead

`/` is dm-verity backed (`dm-3`) with `ro.boot.veritymode=enforcing` and
`ro.boot.vbmeta.device_state=locked`. `mount -o rw,remount /` succeeds at the VFS
layer, but writes fail against dm-verity and remounting back to `ro` returns an I/O
error (harmless — the flag resets at reboot). `adb disable-verity` and `adb remount`
both need a userdebug build. Installing the app into `/system/app` would therefore
risk an unbootable frame; the `proinfo` byte avoids verity entirely.

## Flaky USB

USB ADB re-enumerates constantly on this frame — the transport id climbed past 100
in one session, and commands die mid-run with `device not found`. It is not
rebooting; check `/proc/uptime` to confirm it keeps climbing. Switch to Wi-Fi ADB
and leave the cable out.

## Wi-Fi ADB

As on the old frame, TCP mode does not survive a reboot. Plug in USB and run:

```sh
adb -s FRAME_SERIAL_REDACTED tcpip 5555
adb connect 192.168.0.0:5555
```

## ADB quick reference

```sh
# USB
adb -s FRAME_SERIAL_REDACTED shell

# Wi-Fi
adb -s 192.168.0.0:5555 shell

# Deploy (needs the install lock cleared first)
adb -s 192.168.0.0:5555 install -r -g build/app/outputs/flutter-apk/app-release.apk

# Launch
adb -s 192.168.0.0:5555 shell monkey -p io.github.micw.openphotoframe \
  -c android.intent.category.LAUNCHER 1
```

## Stock service survey

Surveyed 2026-09-15. Three of the five packages disabled on the Frameo 106K are
present here; `com.cghs.stresstest` and `android.rockchip.update.service` are not.
Never `pm uninstall` these — see the reasoning under
[OTA update reboots](#ota-update-reboots-adups-fota). But **do not
`pm disable-user` a package marked `android:persistent="true"` on this ROM
either**: that caused a four-day outage, described in
[The 2026-09-19 respawn-loop outage](#the-2026-09-19-respawn-loop-outage). The
106K note claiming `disable-user` copes with persistent apps does not hold here.

`com.DeviceTest` and `net.frameo.frame` are not persistent, so disabling them
outright is safe:

```sh
adb shell /system/xbin/su 0 pm disable-user --user 0 com.DeviceTest
adb shell /system/xbin/su 0 pm disable-user --user 0 net.frameo.frame
```

`com.adups.fota` **is** persistent. Leave the package enabled and disable its
components instead, so ActivityManager's persistent process starts once and then
idles with nothing left to trigger it:

```sh
for c in .receiver.MyReceiver .service.FcmService .GoogleOtaClient \
         com.google.firebase.iid.FirebaseInstanceIdReceiver \
         com.google.firebase.messaging.FirebaseMessagingService .activity.GdprActivity; do
  adb shell /system/xbin/su 0 pm disable --user 0 "com.adups.fota/$c"
done
```

Afterwards `com.adups.fota` must report `enabled=0` or `enabled=1`
(default/enabled) — **not** `enabled=3`. Its `Application.onCreate` still
re-registers a daily `RTC_WAKEUP`, but that alarm's `PendingIntent` targets the
now-disabled `MyReceiver`, so it fires into nothing.

### com.adups.fota v5.30 — active reboot risk

At `/product/app/FotaApp/`. Same OTA updater that rebooted the 106K every 2–4 hours.
Flags `SYSTEM PERSISTENT`; holds `REBOOT`, `RECOVERY`, `SCHEDULE_EXACT_ALARM`,
`RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`. It had a daily `RTC_WAKEUP` queued
(`*walarm*:com.adups.fota.custom_service`).

Unlike the Rockchip build, this one also registers Firebase Cloud Messaging
(`.service.FcmService`, `FirebaseMessagingService`) alongside `.GoogleOtaClient`, so
an OTA can be pushed remotely at any time rather than only on the daily poll. Nothing
had downloaded yet — `/data/data/com.adups.fota/files` and `/data/ota_package` were
still at the factory date, and `/cache/recovery/command` was absent.

### com.DeviceTest — latent boot-loop

At `/system/app/HCNDeviceTest/`. Shares the **system UID** (`userId=1000`) and holds
`REBOOT`, `MASTER_CLEAR` and `DEVICE_POWER`. Starts on `BOOT_COMPLETED` via
`com.DeviceTest.BootReceiver`, which is the factory burn-in trigger:

```java
SharedPreferences sp = context.getSharedPreferences("AgingTest", 0);
if (!sp.getBoolean("istestend", true)) {          // default TRUE
    Intent i = new Intent(context, com.DeviceTest.AgingTest.class);
    i.setFlags(FLAG_ACTIVITY_NEW_TASK);
    i.putExtra("Reboot", "reboot");
    context.startActivity(i);
}
```

The default is `true`, so an absent flag leaves the soak test dormant — and
`/data/data/com.DeviceTest/shared_prefs/` was empty, so it had never armed. The risk
is latent: anything that runs the factory test and writes `istestend=false` would
launch `AgingTest` with a reboot extra on every subsequent boot. It also ships
`RecoveryTestService` and `TestService`.

This is the structural equivalent of `com.cghs.stresstest` on the 106K, which is
worth knowing if a future frame reboots on a fixed cycle: check the aging-test prefs
before assuming OTA.

### net.frameo.frame v1.26.26 — display conflict, not reboots

At `/system/system_ext/priv-app/Frameo/`, `PRIVILEGED`. Unlike the 106K copy it does
**not** hold `REBOOT`, so it is not a reboot vector here. It does hold `SET_TIME` and
had an `RTC_WAKEUP` for `.utils.StandbyBroadcastReceiver`, which manages the screen
and would fight OpenPhotoFrame for the display. It is also a self-update vector.

Disabling it is safe on this device because two other HOME activities remain:

```
com.android.launcher3/.uioverrides.QuickstepLauncher
io.github.micw.openphotoframe/.MainActivity      <- app declares itself HOME
com.android.settings/.FallbackHome
```

### Left enabled

- `com.debug.loggerui` + the `aee_aed` / `aee_aedv` / `mobile_log_d` daemons. Only
  boot-receiver capability, no reboot vector. Combined on-disk footprint was ~530 KB
  (`/data/debuglogger` 11K, `/data/aee_exp` 365K, `/data/anr` 3.5K,
  `/data/tombstones` 156K) with `/data` at 5% of 26 GB — no eMMC wear pressure, in
  contrast to the 106K. Worth re-checking with `du -sh` if storage creeps up.
- `com.mediatek.engineermode` — holds `MASTER_CLEAR` but only launches from the UI.
- `com.mediatek.miravision.ui`, `com.mediatek.callrecorder`,
  `com.mediatek.lbs.em2.ui`, `com.mediatek.capctrl.service` — no reboot vectors.

### Checking for a regression

```sh
adb shell dumpsys alarm | grep -c "RTC_WAKEUP #"          # expect 0
adb shell dumpsys package com.adups.fota | grep -m1 enabled=   # expect enabled=3
adb shell getprop sys.boot.reason
```

A `sys.boot.reason` of plain `reboot` (rather than `reboot,shell` from your own
`adb reboot`, or `kernel_panic` / `watchdog`) points at one of the above waking up.

## The 2026-09-19 respawn-loop outage

The frame wedged showing "process system isn't responding" with dead touch input.
Prometheus stopped scraping at 07:31; the device never rebooted (uptime ran
continuously through the whole event).

### Cause 1 — `pm disable-user` on a persistent package

`com.adups.fota` is `android:persistent="true"`. Disabling it with
`pm disable-user` on 2026-09-15 meant ActivityManager kept respawning the
persistent process, it died immediately because the package was disabled, and AMS
respawned it again — **17 times per minute, ~24,000 per day, for four days**:

```
I ActivityManager: Process com.adups.fota (pid 12559) has died: pers PER
I ActivityManager: Process com.adups.fota (pid 12744) has died: pers PER   # +3.5s
```

Re-enabling the package stops the loop immediately. Use the component-level
disable in [Stock service survey](#stock-service-survey) instead.

### Cause 2 — unbounded process-scan pile-up in the app

`WebServerService._refreshProcessStatus()` shelled out per metrics scrape with

```
su 0 sh -c "for f in /proc/[0-9]*/cmdline; do tr '\0' '\n' < $f | head -1; done"
```

which forks two processes per PID — about 520 per scan on this device. Worse, the
throttle timestamp was assigned *after* the `await` with no in-flight guard, so a
single slow scan meant every later scrape launched another 520-fork scan on top of
the stuck one. An orphaned `tr` was found spinning at 100% of a core.

Fixed by switching to one `su 0 ps -A -o NAME`, adding a 10s timeout, setting the
throttle before the await, and adding an in-flight guard.

### Why it presented as a system hang

Sustained ~90% system CPU starved everything. `system_server` ANR'd, and its ANR
handler then jammed: thread `AnrConsumer` blocked in `debuggerd_trigger_dump` →
`recvfrom` while holding MediaTek's `AnrManagerService$AnrDumpRecord` lock, so
every subsequent ANR queued behind it. Both `system_server` and the app showed
*idle* main threads (`epoll_wait` / `nativePollOnce`) — the hang was CPU
starvation plus a wedged ANR pipeline, not a deadlock.

### Diagnostic notes for next time

- **Load average is not a health signal here.** Six MTK kernel threads
  (`amms_task`, `GCPU`, `hang_detect`, `entropy_thread`, `display_esd_che`,
  `bat_thread_kthr`) sit permanently in `D` state and each counts toward load, so
  a baseline near 7 is normal. Use `top`'s idle/sys split instead.
- ADB and the app's web server stayed responsive throughout even while the UI was
  frozen — always try `adb connect` and `curl :8080/metrics` before power-cycling.
- ANR traces live in `/data/anr/` (`anr_*` for the report, `trace_*` for the dumped
  process). They rotate quickly; grab them early.
- Ruled out by metrics: memory (RSS 170 MB, JVM 4 MB of 805 MB, 1.2 GB free,
  `opf_android_low_memory=0`), eMMC (`opf_emmc_io_errors_total` flat at 0, clean
  dmesg), storage (25 GB free). Nothing resembling the 106K's hardware failure.

## Building

Flutter picks the JDK bundled with Android Studio first. That JBR is currently
OpenJDK 25, which Gradle 8.14 cannot parse — the build dies with a bare
`java.lang.IllegalArgumentException: 25.0.2`. Point Flutter at Temurin 21:

```sh
flutter config --jdk-dir "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home"
```

This is a machine-local Flutter setting, not repo state. Undo with
`flutter config --jdk-dir=`.

## Making the app the default launcher

With `net.frameo.frame` disabled there are still two HOME candidates
(`com.android.launcher3` and the app), and no default was set — so the frame risked
booting to a launcher chooser. Pin it:

```sh
adb shell /system/xbin/su 0 cmd package set-home-activity \
  io.github.micw.openphotoframe/.MainActivity
```

Verify with the MAIN action included; `-c HOME` alone reports "No activity found"
even when the default is set correctly:

```sh
adb shell cmd package resolve-activity \
  -a android.intent.action.MAIN -c android.intent.category.HOME --brief
```

The setting survives reboot. Combined with the app's `autostart_on_boot` and
`wifi_adb_enabled` config flags, a cold boot reaches photos in about 30 seconds and
brings Wi-Fi ADB back on its own — the app re-runs `setprop service.adb.tcp.port
5555` and restarts `adbd` (`ScreenControlHandler.kt`). That self-healing matters
because USB on this frame is unreliable.
