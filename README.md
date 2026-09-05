# 🌳 Arbor

Arbor is a native music player for Apple devices.

I built this originally to easily pitch-shift, adjust speed, and add reverb on the go, but it can be used as an alternative to a music streaming service.

Arbor's core app is built in Swift, but it uniquely ships an embedded version of the Python runtime. This enables Arbor to use battle-tested libraries like [yt-dlp](https://github.com/yt-dlp/yt-dlp) directly on device.

It also features:
- **iCloud Sync**, so you can share your library across your Apple devices.
- **Last.fm support** for scrobbling your listens
- **Lyrics**, including romanization and translation (powered by a webview extracting strings from Google Translate)
- **A Python dependency manager** with `pip` so you can update dependencies without having to rebuild the app
- **Privacy**: Arbor is a fully client-side app with no centralized server nor analytics

## Local Setup

1. Download Python.xcframework to the root of the repository

```
curl -L -O https://github.com/beeware/Python-Apple-support/releases/download/3.14-b8/Python-3.14-iOS-support.b8.tar.gz
echo "c00c95c6f53878f70fcd60013249af4f8d23a0d6d5d428fd5b273c1a7114cdc4  Python-3.14-iOS-support.b8.tar.gz" | shasum -a 256 -c
tar -xzf Python-3.14-iOS-support.b8.tar.gz Python.xcframework
rm Python-3.14-iOS-support.b8.tar.gz
```

2. Install Python dependencies using your global installation of pip

```
pip3 install --platform=any --only-binary=:all: --target=./python_modules -r requirements.txt
```

3. Open the project in Xcode (`xed Arbor.xcodeproj`) and run

## FAQ

Q. **Will Arbor be published to the App Store?**

- No -- at least not in its current state. Apple prevents apps that download YouTube videos from being published to the App Store as this explicitly violates [Guideline 5.2.3 of Apple's App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#5.2.3). Note that the issue is _not_ because we're embedding the Python runtime, which is allowed.

Q. **Where did the name come from?**

- I started working on this while I was visiting the city of [Ann Arbor](https://www.google.com/search?q=ann+arbor+michigan).
