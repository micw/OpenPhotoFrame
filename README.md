# OpenPhotoFrame

**Turn your old Android tablet into a beautiful digital photo frame.**

OpenPhotoFrame is a free, open-source slideshow app that syncs photos from your private cloud (Nextcloud) or local storage. No ads, no subscriptions, no nag screens – just your photos.

## ✨ Features

- **🖼️ Beautiful Slideshow** – Smooth crossfade transitions between your photos
- **☁️ Nextcloud Sync** – Sync photos from a Nextcloud public share link (WebDAV)
- **📁 Local First** – Works offline, photos are cached locally
- **⚙️ Simple Settings** – Configure slide duration, transition speed, and sync interval
- **🌙 Always On** – Designed to run 24/7 as a dedicated photo frame
- **🔒 Privacy First** – Your photos stay on your server, no third-party cloud required

## 🚀 Why OpenPhotoFrame?

Existing apps like *Fotoo* or *PhotoCloud Frame Slideshow* are either:
- Riddled with **ads and nag screens**
- Require **paid subscriptions** for basic features
- Force you to use **public cloud services** (Google Photos, etc.)

OpenPhotoFrame is different:
- ✅ **100% Free & Open Source** (GPLv3)
- ✅ **No ads, no in-app purchases, no tracking**
- ✅ **Works with your self-hosted Nextcloud**
- ✅ **Simple & focused** – does one thing well (KISS principle)

## 📦 Installation

### Android
*Coming soon to F-Droid*

For now, build from source (see Development section).

### Linux (for Development/Testing)
```bash
flutter run -d linux
```

## 🛠️ Development

### Requirements
- Flutter SDK (3.x)
- Dart SDK

### Build & Run
```bash
# Clone the repository
git clone https://github.com/micw/OpenPhotoFrame.git
cd OpenPhotoFrame

# Get dependencies
flutter pub get

# Run on Linux (fast iteration)
flutter run -d linux

# Run on connected Android device
flutter run -d <device-id>
```

### Architecture
The app follows a **Local First** architecture with clean separation of concerns:

- **Player (UI)** – Displays photos from a local directory with smooth transitions
- **Syncer (Service)** – Downloads photos from cloud sources in the background
- **Repository Pattern** – Abstracts storage access
- **Strategy Pattern** – Swappable playlist algorithms (random, weighted freshness)

## ⚙️ Configuration

Tap the center of the screen during slideshow to open settings:

| Setting | Description |
|---------|-------------|
| Slide Duration | How long each photo is shown (1-15 min) |
| Transition Duration | Crossfade animation speed (0.5-5 sec) |
| Sync Source | None or Nextcloud public share link |
| Sync Interval | Auto-sync frequency (disabled, or 5-60 min) |
| Delete Orphaned Files | Remove local photos deleted from server |

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a pull request.

## 📄 License

This project is licensed under the **GNU General Public License v3.0**.

See the [LICENSE](LICENSE) file for details.
