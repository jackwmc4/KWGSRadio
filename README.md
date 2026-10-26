# KWGS Radio

A minimal native macOS player for KWGS 89.5 Public Radio Tulsa (NPR News, HD1).

It plays the station's official live streams directly with AVPlayer:

- Stereo (AAC): https://utulsa.streamguys1.com/KWGSHD1-AAC
- Mono (MP3): https://utulsa.streamguys1.com/KWGSHD1-MP3

## Build

1. Install the Command Line Tools if needed: `xcode-select --install`
2. In Terminal, from this folder: `chmod +x build.sh && ./build.sh`
3. Open `KWGS Radio.app` (or drag it into /Applications).

## Use

- Playback starts on launch. Space or Cmd-P toggles play and stop.
- Keyboard media keys and Control Center's Now Playing controls work too.
- The quality menu switches between AAC and MP3. If one stream fails to connect, the app tries the other automatically.
- Stopping and restarting reconnects at the live point rather than resuming from where you paused.
- Volume and stream choice are remembered between launches.

## Icon

`icon.png` in this folder becomes the app icon at build time. To use a different image, replace it with any square PNG (1024x1024 works best) and run `./build.sh` again. If Finder still shows the old icon, run `killall Dock`.

## Notes

- macOS 12 or later.
- The app is ad-hoc signed for local use only. Because you built it yourself, Gatekeeper will not block it.
