import Cocoa
import AVFoundation
import MediaPlayer

// Official KWGS 89.5 HD1 (NPR News) streams, published at publicradiotulsa.org/listen-live
struct Stream {
    let name: String
    let url: URL
}
let streams = [
    Stream(name: "Stereo (AAC)", url: URL(string: "https://utulsa.streamguys1.com/KWGSHD1-AAC")!),
    Stream(name: "Mono (MP3)",   url: URL(string: "https://utulsa.streamguys1.com/KWGSHD1-MP3")!),
]
let stationTitle = "KWGS 89.5 Public Radio Tulsa"

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let player = AVPlayer()
    var streamIndex = UserDefaults.standard.integer(forKey: "streamIndex")
    var wantsPlayback = false
    var triedFallback = false
    var observers: [NSKeyValueObservation] = []
    var itemObserver: NSKeyValueObservation?
    var failObserver: NSObjectProtocol?

    let titleLabel = NSTextField(labelWithString: stationTitle)
    let statusLabel = NSTextField(labelWithString: "Stopped")
    let playButton = NSButton()
    let volumeSlider = NSSlider(value: 0.8, minValue: 0, maxValue: 1, target: nil, action: nil)
    let qualityPopup = NSPopUpButton()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if streamIndex >= streams.count { streamIndex = 0 }
        buildWindow()
        buildMenu()
        setupRemoteCommands()

        player.automaticallyWaitsToMinimizeStalling = true
        if let v = UserDefaults.standard.object(forKey: "volume") as? Float { volumeSlider.floatValue = v }
        player.volume = volumeSlider.floatValue

        observers.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshStatus() }
        })

        play()  // start playing on launch
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Playback

    func load(_ index: Int) {
        streamIndex = index
        UserDefaults.standard.set(index, forKey: "streamIndex")
        qualityPopup.selectItem(at: index)

        let item = AVPlayerItem(url: streams[index].url)
        // Live radio: keep a small buffer so playback starts quickly
        item.preferredForwardBufferDuration = 5

        itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.status == .failed { self?.handleFailure(item.error) }
                self?.refreshStatus()
            }
        }
        if let f = failObserver { NotificationCenter.default.removeObserver(f) }
        failObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] note in
            self?.handleFailure(note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
        }
        player.replaceCurrentItem(with: item)
    }

    func play() {
        wantsPlayback = true
        triedFallback = false
        // Always reconnect so a paused live stream resumes at the live edge, not minutes behind
        load(streamIndex)
        player.play()
        refreshStatus()
    }

    func stop() {
        wantsPlayback = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        refreshStatus()
    }

    func handleFailure(_ error: Error?) {
        guard wantsPlayback else { return }
        // Fall back to the other stream once before giving up
        if !triedFallback {
            triedFallback = true
            let other = (streamIndex + 1) % streams.count
            statusLabel.stringValue = "Retrying with \(streams[other].name)…"
            load(other)
            player.play()
            return
        }
        wantsPlayback = false
        statusLabel.stringValue = "Can't connect: \(error?.localizedDescription ?? "unknown error")"
        updateButton()
    }

    func refreshStatus() {
        updateButton()
        updateNowPlaying()
        guard wantsPlayback else {
            if !statusLabel.stringValue.hasPrefix("Can't connect") { statusLabel.stringValue = "Stopped" }
            return
        }
        switch player.timeControlStatus {
        case .playing:
            statusLabel.stringValue = "Live · \(streams[streamIndex].name)"
        case .waitingToPlayAtSpecifiedRate:
            statusLabel.stringValue = "Connecting…"
        case .paused:
            break
        @unknown default:
            break
        }
    }

    func updateButton() {
        let symbol = wantsPlayback ? "stop.fill" : "play.fill"
        playButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: wantsPlayback ? "Stop" : "Play")
    }

    // MARK: Actions

    @objc func togglePlay(_ sender: Any?) {
        wantsPlayback ? stop() : play()
    }

    @objc func volumeChanged(_ sender: NSSlider) {
        player.volume = sender.floatValue
        UserDefaults.standard.set(sender.floatValue, forKey: "volume")
    }

    @objc func qualityChanged(_ sender: NSPopUpButton) {
        streamIndex = sender.indexOfSelectedItem
        UserDefaults.standard.set(streamIndex, forKey: "streamIndex")
        if wantsPlayback { play() }
    }

    // MARK: Media keys and Control Center

    func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.stop(); return .success }
        center.stopCommand.addTarget { [weak self] _ in self?.stop(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlay(nil); return .success }
    }

    func updateNowPlaying() {
        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "NPR News",
            MPMediaItemPropertyArtist: stationTitle,
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
        info.playbackState = wantsPlayback ? .playing : .stopped
    }

    // MARK: UI

    func buildWindow() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        playButton.bezelStyle = .regularSquare
        playButton.isBordered = false
        playButton.imageScaling = .scaleProportionallyUpOrDown
        playButton.target = self
        playButton.action = #selector(togglePlay(_:))
        playButton.keyEquivalent = " "
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        playButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        updateButton()

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let text = NSStackView(views: [titleLabel, statusLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let top = NSStackView(views: [icon, text, playButton])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 12
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)

        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged(_:))
        let speaker = NSImageView(image: NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Volume")!)
        speaker.contentTintColor = .secondaryLabelColor

        qualityPopup.addItems(withTitles: streams.map { $0.name })
        qualityPopup.selectItem(at: streamIndex)
        qualityPopup.target = self
        qualityPopup.action = #selector(qualityChanged(_:))
        qualityPopup.controlSize = .small
        qualityPopup.font = .systemFont(ofSize: 11)

        let bottom = NSStackView(views: [speaker, volumeSlider, qualityPopup])
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        bottom.spacing = 8

        let root = NSStackView(views: [top, bottom])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        top.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36).isActive = true
        bottom.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36).isActive = true

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 140),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "KWGS Radio"
        window.contentView = root
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("KWGSPlayerWindow")
        window.makeKeyAndOrderFront(nil)
    }

    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide KWGS Radio", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit KWGS Radio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let controlsItem = NSMenuItem()
        let controls = NSMenu(title: "Controls")
        let toggle = NSMenuItem(title: "Play / Stop", action: #selector(togglePlay(_:)), keyEquivalent: "p")
        toggle.target = self
        controls.addItem(toggle)
        controlsItem.submenu = controls
        main.addItem(controlsItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
