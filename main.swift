import Cocoa
import AVFoundation
import MediaPlayer

// Official Public Radio Tulsa streams, published at publicradiotulsa.org/listen-live.
// Each channel is offered in two formats, giving eight feeds in all.
struct Channel {
    let name: String
    let program: String
    let mount: String
    func url(for format: Format) -> URL {
        URL(string: "https://utulsa.streamguys1.com/\(mount)-\(format.suffix)")!
    }
}
struct Format {
    let name: String
    let suffix: String
}
let channels = [
    Channel(name: "Public Radio 89.5 HD1", program: "NPR News", mount: "KWGSHD1"),
    Channel(name: "Classical 88.7 HD1",    program: "Classical Music", mount: "KWTUHD1"),
    Channel(name: "Jazz 89.5 HD2",         program: "Jazz", mount: "KWGSHD2"),
    Channel(name: "BBC 89.5 HD3",          program: "BBC World Service", mount: "KWGSHD3"),
]
let formats = [
    Format(name: "Stereo (AAC)", suffix: "AAC"),
    Format(name: "Mono (MP3)",   suffix: "MP3"),
]
let stationTitle = "Public Radio Tulsa"

// Minimizing sends the player to the menu bar icon rather than the Dock
final class PlayerWindow: NSWindow {
    var onMinimize: (() -> Void)?
    override func miniaturize(_ sender: Any?) {
        if let onMinimize { onMinimize() } else { super.miniaturize(sender) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: PlayerWindow!
    var statusItem: NSStatusItem!
    let statusToggleItem = NSMenuItem(title: "Play", action: #selector(togglePlay(_:)), keyEquivalent: "")
    let player = AVPlayer()
    var channelIndex = UserDefaults.standard.integer(forKey: "channelIndex")
    // Kept under the original key so an existing quality choice carries over
    var formatIndex = UserDefaults.standard.integer(forKey: "streamIndex")
    var wantsPlayback = false
    var triedFallback = false
    var observers: [NSKeyValueObservation] = []
    var itemObserver: NSKeyValueObservation?
    var failObserver: NSObjectProtocol?

    let titleLabel = NSTextField(labelWithString: stationTitle)
    let statusLabel = NSTextField(labelWithString: "Stopped")
    let playButton = NSButton()
    let volumeSlider = NSSlider(value: 0.8, minValue: 0, maxValue: 1, target: nil, action: nil)
    let channelPopup = NSPopUpButton()
    let qualityPopup = NSPopUpButton()
    var channelMenuItems: [NSMenuItem] = []

    var channel: Channel { channels[channelIndex] }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if channelIndex >= channels.count { channelIndex = 0 }
        if formatIndex >= formats.count { formatIndex = 0 }
        buildWindow()
        buildMenu()
        buildStatusItem()
        updateChannelUI()
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

    // Quit on close explicitly. applicationShouldTerminateAfterLastWindowClosed would
    // also fire when the window is hidden to the menu bar, quitting mid-stream.
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }

    // MARK: Playback

    func load(format index: Int) {
        formatIndex = index
        UserDefaults.standard.set(index, forKey: "streamIndex")
        qualityPopup.selectItem(at: index)

        let item = AVPlayerItem(url: channel.url(for: formats[index]))
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
        load(format: formatIndex)
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
        // Fall back to the channel's other format once before giving up
        if !triedFallback {
            triedFallback = true
            let other = (formatIndex + 1) % formats.count
            statusLabel.stringValue = "Retrying with \(formats[other].name)…"
            load(format: other)
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
            statusLabel.stringValue = "Live · \(formats[formatIndex].name)"
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
        statusToggleItem.title = wantsPlayback ? "Stop" : "Play"
        statusItem?.button?.image = menuBarImage()
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
        formatIndex = sender.indexOfSelectedItem
        UserDefaults.standard.set(formatIndex, forKey: "streamIndex")
        if wantsPlayback { play() }
    }

    @objc func channelChanged(_ sender: NSPopUpButton) {
        selectChannel(sender.indexOfSelectedItem)
    }

    @objc func channelMenuChosen(_ sender: NSMenuItem) {
        selectChannel(sender.tag)
    }

    @objc func showPlayer(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideToMenuBar() {
        window.orderOut(nil)
        // Accessory apps have no Dock icon; the menu bar item is the way back
        NSApp.setActivationPolicy(.accessory)
    }

    func selectChannel(_ index: Int) {
        channelIndex = index
        UserDefaults.standard.set(index, forKey: "channelIndex")
        updateChannelUI()
        // Switching channels always starts playback, like changing stations on a radio
        play()
    }

    func updateChannelUI() {
        titleLabel.stringValue = channel.name
        channelPopup.selectItem(at: channelIndex)
        statusItem?.button?.toolTip = "\(channel.name) · \(channel.program)"
        for item in channelMenuItems { item.state = item.tag == channelIndex ? .on : .off }
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
            MPMediaItemPropertyTitle: channel.program,
            MPMediaItemPropertyArtist: "\(channel.name) · \(stationTitle)",
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

        channelPopup.addItems(withTitles: channels.map { "\($0.name) · \($0.program)" })
        channelPopup.target = self
        channelPopup.action = #selector(channelChanged(_:))

        qualityPopup.addItems(withTitles: formats.map { $0.name })
        qualityPopup.selectItem(at: formatIndex)
        qualityPopup.target = self
        qualityPopup.action = #selector(qualityChanged(_:))
        qualityPopup.controlSize = .small
        qualityPopup.font = .systemFont(ofSize: 11)

        let bottom = NSStackView(views: [speaker, volumeSlider, qualityPopup])
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        bottom.spacing = 8

        let root = NSStackView(views: [top, channelPopup, bottom])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        top.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36).isActive = true
        channelPopup.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36).isActive = true
        bottom.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36).isActive = true

        window = PlayerWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "KWGS Radio"
        window.contentView = root
        window.delegate = self
        window.onMinimize = { [weak self] in self?.hideToMenuBar() }
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
        controls.addItem(.separator())
        // ⌘1–⌘4 switch channels
        for (i, c) in channels.enumerated() {
            let item = NSMenuItem(title: "\(c.name) · \(c.program)", action: #selector(channelMenuChosen(_:)), keyEquivalent: "\(i + 1)")
            item.target = self
            item.tag = i
            controls.addItem(item)
            channelMenuItems.append(item)
        }
        controlsItem.submenu = controls
        main.addItem(controlsItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize to Menu Bar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    func menuBarImage() -> NSImage? {
        let image = NSImage(systemSymbolName: wantsPlayback ? "radio.fill" : "radio", accessibilityDescription: "KWGS Radio")
        image?.isTemplate = true
        return image
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = menuBarImage()

        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Player", action: #selector(showPlayer(_:)), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        statusToggleItem.target = self
        menu.addItem(statusToggleItem)
        menu.addItem(.separator())
        for (i, c) in channels.enumerated() {
            let item = NSMenuItem(title: "\(c.name) · \(c.program)", action: #selector(channelMenuChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            menu.addItem(item)
            channelMenuItems.append(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit KWGS Radio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
