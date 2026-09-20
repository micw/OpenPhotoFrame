# Setting up a new photo frame

## 1. Find the device

```bash
adb devices -l
```

Note the device serial reported by `adb devices`. Use `-s <serial>` in all commands below if multiple devices are connected.

## 2. Install the APK

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## 3. Disable the stock frame app (if any)

```bash
adb shell pm list packages -s   # find the stock app package name
adb shell pm disable-user --user 0 net.frameo.frame   # replace with actual package
```

## 4. Set Open Photo Frame as default home (auto-starts on boot)

```bash
adb shell cmd package set-home-activity io.github.micw.openphotoframe/.MainActivity
```

## 5. Launch now

```bash
adb shell am start -n io.github.micw.openphotoframe/.MainActivity
```

## Build the APK

```bash
cd android && ./gradlew assembleRelease
```

Output: `build/app/outputs/flutter-apk/app-release.apk`
