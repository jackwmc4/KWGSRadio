# KWGS Radio

A minimal native macOS player for Public Radio Tulsa.

It plays the station's official live streams directly with AVPlayer. Four channels are available, each in stereo AAC or mono MP3:

| Channel | Program | Stereo (AAC) | Mono (MP3) |
|---|---|---|---|
| Public Radio 89.5 HD1 | NPR News | https://utulsa.streamguys1.com/KWGSHD1-AAC | https://utulsa.streamguys1.com/KWGSHD1-MP3 |
| Classical 88.7 HD1 | Classical Music | https://utulsa.streamguys1.com/KWTUHD1-AAC | https://utulsa.streamguys1.com/KWTUHD1-MP3 |
| Jazz 89.5 HD2 | Jazz | https://utulsa.streamguys1.com/KWGSHD2-AAC | https://utulsa.streamguys1.com/KWGSHD2-MP3 |
| BBC 89.5 HD3 | BBC World Service | https://utulsa.streamguys1.com/KWGSHD3-AAC | https://utulsa.streamguys1.com/KWGSHD3-MP3 |

## Build

1. Install the Command Line Tools if needed: `xcode-select --install`
2. In Terminal, from this folder: `chmod +x build.sh && ./build.sh`
3. Open `KWGS Radio.app` (or drag it into /Applications).

## Use

- Playback starts on launch. Space or Cmd-P toggles play and stop.
- Keyboard media keys and Control Center's Now Playing controls work too.
- The channel menu in the window, or Cmd-1 to Cmd-4, switches channels.
- The quality menu switches between AAC and MP3. If one stream fails to connect, the app tries the other automatically.
- Stopping and restarting reconnects at the live point rather than resuming from where you paused.
- Volume, channel and quality are remembered between launches.

## Icon

`icon.png` in this folder becomes the app icon at build time. To use a different image, replace it with any square PNG (1024x1024 works best) and run `./build.sh` again. If Finder still shows the old icon, run `killall Dock`.

## Notes

- macOS 12 or later.
- The app is ad-hoc signed for local use only. Because you built it yourself, Gatekeeper will not block it.
