# Photo frame device notes

Current device: **Pexar Frame PX-110**. The Frameo 106K it replaced died of eMMC
failure and went back to Amazon; what still transfers is kept at the
[end](#previous-device-frameo-106k-retired).

## Pexar Frame PX-110 (MediaTek MT8167)

| | |
|---|---|
| Model | Pexar Frame (`ro.product.brand=Lexar`, `ro.product.device=dpf1106_mk_32`) |
| SoC | MediaTek MT8167, **32-bit only** (`armeabi-v7a`) |
| Android | 11, user build, `ro.debuggable=0`, SELinux **permissive** |
| RAM / storage | 2 GB / 26 GB `/data` |
| USB serial | in `scripts/frame.env` (gitignored) |
| IP | in `scripts/frame.env` (gitignored); it moves on DHCP, so check before assuming |

Root works despite `ro.debuggable=0`, because `/system/xbin/su` is setuid root and
SELinux is permissive:

```sh
adb shell /system/xbin/su 0 id   # uid=0(root) ... context=u:r:su:s0
```

Setup and health checks are scripted — see [scripts/px110.sh](scripts/px110.sh).

### Build constraint: 32-bit only

`ro.product.cpu.abilist` is `armeabi-v7a,armeabi`. The default fat APK from
`flutter build apk --release` works because it bundles `armeabi-v7a`, but an
arm64-only build or the wrong `--split-per-abi` artifact produces an APK this frame
cannot run:

```sh
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep -o 'lib/[^/]*' | sort -u
# must include lib/armeabi-v7a
```

Flutter also picks the JDK bundled with Android Studio first. That JBR is currently
OpenJDK 25, which Gradle 8.14 cannot parse — the build dies with a bare
`java.lang.IllegalArgumentException: 25.0.2`. Point Flutter at Temurin 21:

```sh
flutter config --jdk-dir "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home"
```

That is a machine-local setting, not repo state. Undo with `flutter config --jdk-dir=`.

### Vendor install lock (`ro.vendor.custom_recover`)

Out of the box every sideload fails, including as root:

```
Failure [INSTALL_FAILED_INVALID_APK: Package io.github.micw.openphotoframe is not allow to install. ]
```

The ROM patches `PackageManagerService.preparePackageLI` in
`/system/framework/services.jar`:

```java
if ("1".equals(SystemProperties.get("ro.vendor.custom_recover", "0"))) {
    if (!isSystemApp(pkg.getPackageName())) {
        throw new PrepareFailure(-2, "Package " + name + " is not allow to install. ");
    }
}
```

`MtkSystemUI` reads the same property via `CommandQueue.isRecoveryFirstBoot()`, and
`panelsEnabled()` returns false while it is `1` — so the flag is a kiosk lockdown
switch that blocks sideloading *and* disables the notification shade.

`/vendor/bin/nvram_daemon` publishes the value. Its code at `0x2eb4` (Thumb-2) reads
the 1024-byte product-info record, takes the byte at offset `0x3FE`, and calls
`property_set`. That record is the head of the **`proinfo` partition**, not a file
under `/mnt/vendor/nvdata`. `proinfo` starts with the device serial, which is how to
confirm the right partition:

```sh
P=/dev/block/platform/soc/11120000.mmc/by-name/proinfo
adb shell "/system/xbin/su 0 dd if=$P bs=1 count=1024 2>/dev/null | od -A d -t x1"
# offset 0      serial
# offset 0x6e   Wi-Fi/BT MAC
# offset 0x3fe  the lock flag
```

**The fix** — clear byte 1022 and reboot. `proinfo` is a raw factory-data partition
outside the AVB chain, so this does not disturb verity:

```sh
adb shell "/system/xbin/su 0 dd if=/dev/zero of=$P bs=1 seek=1022 count=1 conv=notrunc; sync"
adb reboot
adb shell getprop ro.vendor.custom_recover   # 0
```

Back the partition up first and diff afterwards — expect exactly one changed byte.
The pre-change backup is in `backups/`, which is gitignored because the dump
contains the serial and MAC.

Side effect, as predicted by `panelsEnabled()`: the notification shade now pulls
down. Restoring the byte reverts both effects.

**Why not patch `/system` instead.** It is dm-verity backed (`dm-3`) with
`ro.boot.veritymode=enforcing` and `ro.boot.vbmeta.device_state=locked`.
`mount -o rw,remount /` succeeds at the VFS layer but writes fail against dm-verity,
and remounting back to `ro` returns a harmless I/O error (the flag resets at reboot).
`adb disable-verity` and `adb remount` both need a userdebug build. Installing into
`/system/app` would therefore risk an unbootable frame; the `proinfo` byte avoids
verity entirely.

### Stock services

Surveyed 2026-09-15. Never `pm uninstall` these — Android falls back to the ROM copy,
which then runs and self-updates.

**Do not `pm disable-user` a package marked `android:persistent="true"` on this
ROM.** ActivityManager respawns the persistent process, it dies instantly because the
package is disabled, and AMS respawns it again — see
[the outage](#the-2026-09-19-respawn-loop-outage).

`com.DeviceTest` and `net.frameo.frame` are not persistent, so disabling them
outright is safe:

```sh
adb shell /system/xbin/su 0 pm disable-user --user 0 com.DeviceTest
adb shell /system/xbin/su 0 pm disable-user --user 0 net.frameo.frame
```

`com.adups.fota` **is** persistent. Leave the package enabled and disable its
components, so the persistent process starts once and idles with nothing to trigger:

```sh
for c in .receiver.MyReceiver .service.FcmService .GoogleOtaClient \
         com.google.firebase.iid.FirebaseInstanceIdReceiver \
         com.google.firebase.messaging.FirebaseMessagingService .activity.GdprActivity; do
  adb shell /system/xbin/su 0 pm disable --user 0 "com.adups.fota/$c"
done
```

Afterwards `com.adups.fota` must report `enabled=0` or `enabled=1` — **never
`enabled=3`**. Its `Application.onCreate` still re-registers a daily `RTC_WAKEUP`,
but the alarm's `PendingIntent` targets the now-disabled `MyReceiver`, so it fires
into nothing.

Why each one matters:

- **`com.adups.fota` v5.30** (`/product/app/FotaApp/`) — OTA updater holding
  `REBOOT`, `RECOVERY` and `SCHEDULE_EXACT_ALARM`. Beyond the daily alarm it
  registers Firebase Cloud Messaging (`.service.FcmService`) alongside
  `.GoogleOtaClient`, so an update can be pushed remotely at any time.
- **`com.DeviceTest`** (`/system/app/HCNDeviceTest/`) — shares the **system UID** and
  holds `REBOOT`, `MASTER_CLEAR`, `DEVICE_POWER`. Its `BootReceiver` is a factory
  burn-in trigger:

  ```java
  if (!sp.getBoolean("istestend", true)) {          // default TRUE
      Intent i = new Intent(context, com.DeviceTest.AgingTest.class);
      i.putExtra("Reboot", "reboot");
      context.startActivity(i);
  }
  ```

  The default is `true` and `shared_prefs/` was empty, so it never armed. The risk is
  latent: anything writing `istestend=false` gives a reboot on every boot. If a
  future frame reboots on a fixed cycle, check the aging-test prefs before assuming
  OTA.
- **`net.frameo.frame` v1.26.26** — no `REBOOT` here, so not a reboot vector, but it
  holds `SET_TIME`, had a `StandbyBroadcastReceiver` wakeup that fights for the
  screen, and is a self-update vector.

Left enabled: `com.debug.loggerui` with the `aee_aed` / `aee_aedv` / `mobile_log_d`
daemons (~530 KB written, no wear pressure), `com.mediatek.engineermode`
(`MASTER_CLEAR` but UI-only), MiraVision, CallRecorderService, LocationEM2,
MtkCapCtrl.

### Default launcher

With `net.frameo.frame` disabled there are still two HOME candidates
(`com.android.launcher3` and the app) and no default, so the frame can boot to a
launcher chooser. Pin it:

```sh
adb shell /system/xbin/su 0 cmd package set-home-activity \
  io.github.micw.openphotoframe/.MainActivity
```

Verify with the MAIN action included — `-c HOME` alone reports "No activity found"
even when the default is set correctly:

```sh
adb shell cmd package resolve-activity \
  -a android.intent.action.MAIN -c android.intent.category.HOME --brief
```

### Web UI password

The settings server binds `0.0.0.0:8080` with `Access-Control-Allow-Origin: *`
and shipped with no authentication, so anyone on the LAN could read
`/api/config` and `/api/log` — both of which disclose the iCloud shared-album
token, which is enough to open the album.

Set a password in the web UI (Android section) or in the on-device settings
screen. Empty disables authentication. It is HTTP Basic, any username, checked
against `web_ui_password` in the app config:

```sh
curl -u admin:PASSWORD http://$FRAME_IP:8080/api/config
```

`/metrics` is deliberately **left open** so Prometheus keeps scraping without
credentials — it exposes only counters and gauges, no album URLs, tokens or log
lines. If you want it protected too, add `basic_auth` to the Prometheus scrape
config and remove the `path != '/metrics'` exemption in `_route`.

Forgotten password: clear it in the on-device settings screen, or over ADB —

```sh
adb shell "/system/xbin/su 0 sed -i 's/\"web_ui_password\":[^,}]*/\"web_ui_password\":\"\"/' \
  /data/data/io.github.micw.openphotoframe/app_flutter/config.json"
```

Note the token is still written to the app log in plaintext, so it remains
visible to anyone who can authenticate or read the log another way.

### Wi-Fi ADB and flaky USB

USB on this frame re-enumerates constantly — transport ids climbed past 300 in one
session, with commands dying mid-run as `device not found`. That is not the frame
crashing; check that `/proc/uptime` keeps climbing. Work over Wi-Fi.

TCP mode does not survive a reboot by itself, but the app restores it: with
`autostart_on_boot` and `wifi_adb_enabled` set in its config, `ScreenControlHandler`
re-runs `setprop service.adb.tcp.port 5555` and restarts `adbd` at boot. A cold boot
reaches photos in about 30 seconds with Wi-Fi ADB already back. Manual setup:

```sh
adb -s "$FRAME_SERIAL" tcpip 5555
adb connect "$FRAME_IP:5555"
```

### ADB quick reference

```sh
# Wi-Fi (preferred — USB is unreliable)
adb -s "$FRAME_IP:5555" shell

# Deploy (needs the install lock cleared first)
adb -s "$FRAME_IP:5555" install -r -g build/app/outputs/flutter-apk/app-release.apk

# Metrics without adb
curl -s http://$FRAME_IP:8080/metrics | grep ^opf_uptime_seconds
```

### The 2026-09-19 respawn-loop outage

The frame wedged showing "process system isn't responding" with dead touch.
Prometheus stopped scraping at 07:31 and the device never rebooted — uptime ran
continuously through the whole event.

**Cause 1 — `pm disable-user` on a persistent package.** Disabling `com.adups.fota`
that way on 2026-09-15 produced an AMS respawn loop of **17 per minute, ~24,000 per
day, for four days**:

```
I ActivityManager: Process com.adups.fota (pid 12559) has died: pers PER
I ActivityManager: Process com.adups.fota (pid 12744) has died: pers PER   # +3.5s
```

Re-enabling the package stops it immediately.

**Cause 2 — unbounded process-scan pile-up in the app.**
`WebServerService._refreshProcessStatus()` shelled out per metrics scrape with a
`/proc/[0-9]*/cmdline` walk that forked two processes per PID (~520 per scan), and
assigned its throttle timestamp *after* the `await` with no in-flight guard. One slow
scan therefore let every later scrape launch another 520-fork scan on top of the
stuck one; an orphaned `tr` was found spinning at 100% of a core. Fixed with a single
`su 0 ps -A -o NAME`, a 10s timeout, the throttle set up front, and an in-flight
guard.

**Why it looked like a system hang.** Sustained ~90% system CPU starved everything.
`system_server` ANR'd and its handler then jammed: thread `AnrConsumer` blocked in
`debuggerd_trigger_dump` → `recvfrom` while holding MediaTek's
`AnrManagerService$AnrDumpRecord` lock, so every later ANR queued behind it. Both
`system_server` and the app showed *idle* main threads (`epoll_wait` /
`nativePollOnce`) — CPU starvation plus a wedged ANR pipeline, not a deadlock.

Diagnostic notes for next time:

- **Load average is not a health signal here.** Six MTK kernel threads
  (`amms_task`, `GCPU`, `hang_detect`, `entropy_thread`, `display_esd_che`,
  `bat_thread_kthr`) sit permanently in `D` state and each counts toward load, so a
  baseline near 7 is normal. Use `top`'s idle/sys split instead.
- ADB and the app's web server stayed responsive while the UI was frozen. Always try
  `adb connect` and `curl :8080/metrics` before power-cycling.
- ANR traces are in `/data/anr/` (`anr_*` reports, `trace_*` dumped processes). They
  rotate fast, so grab them early.
- Ruled out by metrics: memory (RSS 170 MB, JVM 4 MB of 805 MB, 1.2 GB free,
  `opf_android_low_memory=0`), eMMC (`opf_emmc_io_errors_total` flat at 0, clean
  dmesg), storage (25 GB free).

## Previous device: Frameo 106K (retired)

Rockchip RK3326, Android 11. Returned to Amazon after
progressive eMMC failure. Kept for the parts that transfer.

**eMMC failure is a known failure mode for these frames.** Bad sectors appeared first
in the system partition (killing `statsd`, `audioserver`, `netd`, `wificond`), then
about an hour later 13 more in userdata — including f2fs node inode blocks, meaning
the filesystem itself was at risk. Community reports:
[1](https://forums.justuseapp.com/en/post/QERMOAEXL7/frameo-keeps-rebooting-over-and-over),
[2](https://www.justanswer.com/electronics/tksy5-frameo-digital-photo-frame-stuck-rebooting.html),
[3](https://www.devicepitfalls.com/frameo-stuck-on-startup-screen/).

Mapping a bad sector to a file, if it happens again:

```sh
adb shell su 0 cat /sys/kernel/debug/mmc0/mmc0:0001/ext_csd   # eMMC health
# f2fs block = (bad_sector - partition_start) / 8
adb shell su 0 dump.f2fs -b <block> /dev/block/dm-6
adb shell su 0 find /data -inum <inode>
```

**Factory reset without a usable recovery UI.** The frame had one physical button,
which only selected "Reboot system now". Reset via ADB instead:

```sh
adb shell su 0 sh -c 'mkdir -p /cache/recovery && printf -- "--wipe_data\n" > /cache/recovery/command && sync'
adb reboot recovery
```

**Rockchip-only app workarounds.** Both are inert on the PX-110 and remain in the
codebase only for a possible future Rockchip device:

- `ScreenControlHandler.stopCrashingMemtrackService()` — the RK3326
  `android.hardware.memtrack@1.0-service` HAL aborts on boot inside
  `memtrack.rk3326.so` and init restarts it forever. Gated on `Build.HARDWARE`
  containing `"rk"` (the PX-110 reports `mt8167`) and on
  `/vendor/lib/hw/memtrack.rk3326.so`, which does not exist here.
- `ScreenControlHandler.warmEmmcFileCache()` — reads the 106K's failing system files
  into the page cache at boot. Off by default; leave it off.

Its `/vendor` was also dm-verity protected, with `adb remount`'s overlay landing on a
tmpfs at `/mnt/scratch` and no scratch partition, so no permanent firmware fix was
possible there either.
