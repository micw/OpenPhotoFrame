#!/bin/bash
# Reconnects to the Frameo after a reboot and stops the buggy Rockchip RK3326
# memtrack HAL service. Run this with the USB cable plugged into the Frameo.
#
# The app (OpenPhotoFrame) does this automatically on every boot via su, so
# this script is only needed if the app isn't installed or hasn't launched yet.
#
# Usage: ./scripts/fix-frameo.sh

set -uo pipefail

ADB="${HOME}/Library/Android/sdk/platform-tools/adb"
SERIAL="SERIAL_REDACTED"
FRAMEO_IP="192.168.0.0"

echo "==> Waiting for Frameo USB ADB connection..."
"${ADB}" -s "${SERIAL}" wait-for-device

echo "==> Stopping buggy memtrack HAL (Rockchip RK3326 firmware bug)..."
"${ADB}" -s "${SERIAL}" shell stop vendor.memtrack-hal-1-0
STATUS=$("${ADB}" -s "${SERIAL}" shell getprop init.svc.vendor.memtrack-hal-1-0)
echo "    vendor.memtrack-hal-1-0: ${STATUS}"

echo "==> Removing unwanted system apps (idempotent — safe to re-run)..."
# com.adups.fota has android:persistent="true" so pm disable is ignored — use uninstall instead.
# net.frameo.frame ships in /system/priv-app/Frameo.apk; pm uninstall only strips the data-layer
# overlay and falls back to the ROM copy, which then self-updates and reboots the device.
# pm disable-user fully disables the package for user 0, blocking both the ROM copy and any update.
disable_pkg() {
  local result
  result=$("${ADB}" -s "${SERIAL}" shell pm disable-user --user 0 "$1" 2>&1)
  case "${result}" in
    *disabled*) echo "    $1: disabled" ;;
    *) echo "    $1: ${result}" ;;
  esac
  # Also uninstall the data-layer overlay if present
  "${ADB}" -s "${SERIAL}" shell pm uninstall -k --user 0 "$1" >/dev/null 2>&1 || true
}
disable_pkg com.adups.fota          # OTA updater, android:persistent="true"
disable_pkg android.rockchip.update.service  # Rockchip OTA
disable_pkg net.frameo.frame        # Frameo photo app — has ROM copy that self-updates and reboots
disable_pkg com.cghs.stresstest     # Rockchip factory stress test, android:persistent="true", triggers reboots
disable_pkg com.DeviceTest          # Rockchip factory device test
"${ADB}" -s "${SERIAL}" shell am force-stop com.adups.fota 2>/dev/null || true
"${ADB}" -s "${SERIAL}" shell am force-stop android.rockchip.update.service 2>/dev/null || true
"${ADB}" -s "${SERIAL}" shell am force-stop net.frameo.frame 2>/dev/null || true

echo "==> Enabling WiFi ADB on port 5555..."
"${ADB}" -s "${SERIAL}" tcpip 5555
sleep 2

echo "==> Connecting via WiFi..."
"${ADB}" connect "${FRAMEO_IP}:5555"
echo ""
echo "Done. You can unplug the USB cable."
echo "WiFi ADB: ${ADB} -s ${FRAMEO_IP}:5555 shell"
