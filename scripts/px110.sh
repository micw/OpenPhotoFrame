#!/usr/bin/env bash
# Setup and health check for the Pexar Frame PX-110 (MediaTek MT8167).
#
# Idempotent — safe to re-run. Connects over Wi-Fi (falling back to USB and
# re-enabling TCP mode), repairs the stock-service configuration, pins the app as
# the default launcher, and prints a health summary.
#
# Usage:
#   ./scripts/px110.sh              # connect, repair config, report health
#   ./scripts/px110.sh --health     # report only, change nothing
#   ./scripts/px110.sh --install    # also install the release APK
#
# Override the defaults with env vars, e.g. FRAME_IP=192.168.0.0 ./scripts/px110.sh
#
# See FRAMEO.md for why each step exists.

set -uo pipefail

ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
SERIAL="${FRAME_SERIAL:-FRAME_SERIAL_REDACTED}"
IP="${FRAME_IP:-192.168.0.0}"
PORT=5555
PKG=io.github.micw.openphotoframe
APK="build/app/outputs/flutter-apk/app-release.apk"
PROINFO=/dev/block/platform/soc/11120000.mmc/by-name/proinfo

# com.adups.fota is android:persistent="true". Disabling the *package* makes
# ActivityManager respawn it ~17x/minute forever — see the outage notes in
# FRAMEO.md. Disable these components instead and leave the package enabled.
ADUPS_COMPONENTS=(
  .receiver.MyReceiver
  .service.FcmService
  .GoogleOtaClient
  com.google.firebase.iid.FirebaseInstanceIdReceiver
  com.google.firebase.messaging.FirebaseMessagingService
  .activity.GdprActivity
)
# Not persistent, so disabling the whole package is safe.
DISABLE_PACKAGES=(com.DeviceTest net.frameo.frame)

HEALTH_ONLY=0
DO_INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --health)  HEALTH_ONLY=1 ;;
    --install) DO_INSTALL=1 ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

DEV=""
ok()   { printf '    \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '    \033[31m✗\033[0m %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }

sh_() { "${ADB}" -s "${DEV}" shell "$@" 2>/dev/null | tr -d '\r'; }
su_() { "${ADB}" -s "${DEV}" shell "/system/xbin/su 0 $*" 2>/dev/null | tr -d '\r'; }

# --- connect ----------------------------------------------------------------

step "Connecting"
"${ADB}" connect "${IP}:${PORT}" >/dev/null 2>&1
if "${ADB}" -s "${IP}:${PORT}" shell true >/dev/null 2>&1; then
  DEV="${IP}:${PORT}"
  ok "Wi-Fi ADB at ${DEV}"
elif "${ADB}" -s "${SERIAL}" shell true >/dev/null 2>&1; then
  DEV="${SERIAL}"
  warn "Wi-Fi unavailable; using USB. Re-enabling TCP mode..."
  "${ADB}" -s "${SERIAL}" tcpip "${PORT}" >/dev/null 2>&1
  sleep 4
  conn=$("${ADB}" connect "${IP}:${PORT}" 2>&1)
  if [ "${conn#*connected}" != "${conn}" ]; then
    DEV="${IP}:${PORT}"
    ok "Wi-Fi ADB re-enabled at ${DEV} — you can unplug USB"
  else
    warn "Still on USB (${SERIAL}); USB on this frame is unreliable"
  fi
else
  bad "No device. Plug in USB, or check the frame is on the network at ${IP}."
  exit 1
fi

if [ "$(su_ id -u)" != "0" ]; then
  bad "Root unavailable via /system/xbin/su — cannot continue"
  exit 1
fi
ok "root via /system/xbin/su"

# --- repair -----------------------------------------------------------------

if [ "${HEALTH_ONLY}" -eq 0 ]; then
  step "Stock services"

  state=$(sh_ "dumpsys package com.adups.fota" | grep -m1 -oE "enabled=[0-9]+" | cut -d= -f2)
  if [ "${state}" = "3" ]; then
    warn "com.adups.fota is disabled-user — this causes the respawn loop. Re-enabling."
    su_ pm enable com.adups.fota >/dev/null
    ok "com.adups.fota re-enabled"
  else
    ok "com.adups.fota package enabled (state ${state:-?}) — no respawn loop"
  fi

  for c in "${ADUPS_COMPONENTS[@]}"; do
    su_ "pm disable --user 0 com.adups.fota/${c}" >/dev/null
  done
  # Count the indented identifier lines that follow the disabledComponents header,
  # stopping at the first line that is not one.
  n=$(sh_ "dumpsys package com.adups.fota" \
      | awk '/disabledComponents:/{f=1;next} f && /^ +[A-Za-z0-9_.$]+$/{c++;next} f{exit} END{print c+0}')
  ok "adups components disabled (${n} listed)"

  for p in "${DISABLE_PACKAGES[@]}"; do
    su_ "pm disable-user --user 0 ${p}" >/dev/null
    su_ "am force-stop ${p}" >/dev/null
    ok "${p} disabled"
  done

  step "Default launcher"
  su_ "cmd package set-home-activity ${PKG}/.MainActivity" >/dev/null
  home=$(sh_ "cmd package resolve-activity -a android.intent.action.MAIN \
    -c android.intent.category.HOME --brief" | grep "/" | tail -1 | tr -d ' ')
  case "${home}" in
    ${PKG}/*) ok "HOME is ${home}" ;;
    *)        warn "HOME resolves to '${home:-nothing}' — expected ${PKG}" ;;
  esac
fi

# --- install ----------------------------------------------------------------

if [ "${DO_INSTALL}" -eq 1 ]; then
  step "Installing ${APK}"
  if [ ! -f "${APK}" ]; then
    bad "Not found. Build first: flutter build apk --release"
    exit 1
  fi
  abis=$(unzip -l "${APK}" | grep -o 'lib/[^/]*' | sort -u)
  if [ "${abis#*armeabi-v7a}" = "${abis}" ]; then
    bad "APK has no armeabi-v7a slice — this frame is 32-bit only and cannot run it"
    bad "found: $(echo "${abis}" | tr '\n' ' ')"
    exit 1
  fi
  ok "armeabi-v7a slice present"
  out=$("${ADB}" -s "${DEV}" install -r -g "${APK}" 2>&1)
  if [ "${out#*Success}" != "${out}" ]; then
    ok "installed"
    sh_ "monkey -p ${PKG} -c android.intent.category.LAUNCHER 1" >/dev/null
    # On startup the app re-runs enableWifiAdb(), which does `stop adbd; start
    # adbd` — that drops this very session. Wait for adbd to come back, or the
    # health checks below all read as empty failures.
    if [ "${DEV}" = "${IP}:${PORT}" ]; then
      sleep 10
      for _ in 1 2 3 4 5 6; do
        "${ADB}" connect "${IP}:${PORT}" >/dev/null 2>&1
        "${ADB}" -s "${DEV}" shell true >/dev/null 2>&1 && break
        sleep 5
      done
    fi
    ok "reconnected after adbd restart"
  else
    bad "install failed — check ro.vendor.custom_recover (see FRAMEO.md)"
    exit 1
  fi
fi

# --- health -----------------------------------------------------------------

step "Health"

lock=$(sh_ getprop ro.vendor.custom_recover)
[ "${lock}" = "0" ] && ok "install lock clear (ro.vendor.custom_recover=0)" \
                    || bad "install lock ON (=${lock}) — sideloading blocked, see FRAMEO.md"

up=$(sh_ "cut -d. -f1 /proc/uptime")
printf '    device uptime %ss, boot reason: %s\n' "${up}" "$(sh_ getprop sys.boot.reason)"

appup=$(curl -s -m 8 "http://${IP}:8080/metrics" 2>/dev/null | awk '/^opf_uptime_seconds /{print $2}')
if [ -n "${appup}" ]; then
  ok "app serving metrics, uptime ${appup}s"
else
  bad "app web server not responding on ${IP}:8080"
fi

focus=$(sh_ "dumpsys window" | grep -m1 mCurrentFocus)
case "${focus}" in
  *${PKG}*) ok "app in foreground" ;;
  *)        warn "foreground: ${focus:-unknown}" ;;
esac

# The respawn loop is the thing most likely to come back. Zero is the only good answer.
deaths=$(su_ "logcat -d" | grep -c "com.adups.fota.*has died")
[ "${deaths}" -eq 0 ] && ok "no adups respawns in the log buffer" \
                      || bad "${deaths} adups respawns in buffer — respawn loop is back"

# Orphaned helpers from the old /proc-walk bug; should be none.
orph=$(su_ 'sh -c "ps -A -o NAME | grep -cE \"^(tr|head)$\""')
[ "${orph:-0}" -eq 0 ] && ok "no orphaned scan helpers" \
                       || warn "${orph} orphaned tr/head processes"

# Load average is meaningless here (~6 MTK kernel threads sit permanently in D
# state and each counts toward it). Use the idle/sys split instead.
sh_ "top -n 1 -b" | sed -n '/%cpu/p' | head -1 | sed 's/^/    /'
sh_ "cat /sys/class/thermal/thermal_zone0/temp" | awk '{printf "    cpu temp %.1fC\n", $1/1000}'

alarms=$(sh_ "dumpsys alarm" | grep -ciE "adups|net\.frameo")
[ "${alarms}" -eq 0 ] && ok "no wakeup alarms from disabled packages" \
                      || warn "${alarms} alarm lines from adups/frameo (harmless if receivers are disabled)"

printf '\nDone. Shell: %s -s %s shell\n' "${ADB}" "${DEV}"
