import Cocoa
import AVFoundation

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var floatingPanel: FloatingPanel!
    var statusItem: NSStatusItem!
    var audioPlayer: AVAudioPlayer?
    var isMusicPlaying = false
    var cornerIndex = 0 // cycle counterclockwise: BR→TR→TL→BL→BR
    var musicMenuItem: NSMenuItem!
    var cornerMenuItem: NSMenuItem!
    var statusIcon: NSImage?
    var currentSizeScale: Float = 1.0 // relative to 120px default

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        floatingPanel = FloatingPanel()
        floatingPanel.show()
        loadStatusIcons()
        setupStatusBar()
        prepareAudio()
    }

    func loadStatusIcons() {
        guard let gifPath = Bundle.main.url(forResource: "cat", withExtension: "GIF"),
              let gifData = try? Data(contentsOf: gifPath),
              let gifImage = NSImage(data: gifData) else { return }

        let barHeight = NSStatusBar.system.thickness
        let size = NSSize(width: barHeight - 2, height: barHeight - 2)

        let icon = NSImage(size: size)
        icon.lockFocus()
        gifImage.draw(in: NSRect(origin: .zero, size: size),
                      from: NSRect(origin: .zero, size: gifImage.size),
                      operation: .copy, fraction: 1.0)
        icon.unlockFocus()
        icon.isTemplate = false
        statusIcon = icon
    }

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = statusIcon
            button.imageScaling = .scaleProportionallyUpOrDown
            button.toolTip = "月薪喵 - Desktop Companion"
        }

        let menu = NSMenu()

        musicMenuItem = NSMenuItem(title: "🎵 Play Music", action: #selector(toggleMusic), keyEquivalent: "m")
        menu.addItem(musicMenuItem)

        menu.addItem(NSMenuItem.separator())

        cornerMenuItem = NSMenuItem(title: "📍 Switch Corner", action: #selector(moveToCorner), keyEquivalent: "")
        menu.addItem(cornerMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Size slider
        let sliderItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let sliderView = SizeSliderView(currentScale: currentSizeScale) { [weak self] scale in
            self?.currentSizeScale = scale
            self?.floatingPanel.resize(toScale: CGFloat(scale))
        }
        sliderItem.view = sliderView
        menu.addItem(sliderItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About 月薪喵", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func prepareAudio() {
        guard let musicURL = Bundle.main.url(forResource: "music", withExtension: "mp3") else {
            print("Music file not found")
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: musicURL)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = 0.5
        } catch {
            print("Failed to load audio: \(error)")
        }
    }

    @objc func toggleMusic() {
        guard let player = audioPlayer else { return }
        if isMusicPlaying {
            player.pause()
            isMusicPlaying = false
            musicMenuItem.title = "🎵 Play Music"
        } else {
            player.play()
            isMusicPlaying = true
            musicMenuItem.title = "⏸ Pause Music"
        }
    }

    @objc func moveToCorner() {
        guard let screen = floatingPanel.window.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        let wf = floatingPanel.window.frame
        let padX: CGFloat = 20
        let padY: CGFloat = 40

        let origins: [NSPoint] = [
            NSPoint(x: vf.maxX - wf.width - padX, y: vf.minY + padY),       // Bottom-Right
            NSPoint(x: vf.maxX - wf.width - padX, y: vf.maxY - wf.height - padY), // Top-Right
            NSPoint(x: vf.minX + padX, y: vf.maxY - wf.height - padY),           // Top-Left
            NSPoint(x: vf.minX + padX, y: vf.minY + padY),                       // Bottom-Left
        ]

        floatingPanel.window.setFrameOrigin(origins[cornerIndex])
        cornerIndex = (cornerIndex + 1) % 4
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "🐱 月薪喵 Desktop Companion"
        alert.informativeText = """
        A floating salary cat companion for your desktop.

        • Drag to move anywhere on screen
        • Status bar menu for controls
        • Move to Corner cycles counterclockwise

        祝月薪翻倍！💰
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func quitApp() {
        audioPlayer?.stop()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Size Slider View

class SizeSliderView: NSView {
    let slider: NSSlider
    let label: NSTextField
    var onSizeChange: ((Float) -> Void)?

    init(currentScale: Float, onChange: @escaping (Float) -> Void) {
        // Label: "Size"
        let titleLabel = NSTextField(labelWithString: "Size")
        titleLabel.font = NSFont.menuFont(ofSize: 12)
        titleLabel.alignment = .left
        titleLabel.frame = NSRect(x: 10, y: 22, width: 200, height: 16)

        // Scale label: "1.0×"
        label = NSTextField(labelWithString: String(format: "%.1f×", currentScale))
        label.font = NSFont.menuFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.frame = NSRect(x: 170, y: 22, width: 50, height: 16)

        // Slider: 0.25 to 8.0
        slider = NSSlider(value: Double(currentScale),
                          minValue: 0.25, maxValue: 4.0,
                          target: nil, action: nil)
        slider.frame = NSRect(x: 10, y: 4, width: 210, height: 18)
        slider.controlSize = .small
        slider.numberOfTickMarks = 8
        slider.allowsTickMarkValuesOnly = false

        onSizeChange = onChange

        let height: CGFloat = 40
        super.init(frame: NSRect(x: 0, y: 0, width: 230, height: height))

        addSubview(titleLabel)
        addSubview(label)
        addSubview(slider)

        slider.target = self
        slider.action = #selector(sliderChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    @objc func sliderChanged(_ sender: NSSlider) {
        let raw = sender.floatValue
        let val = round(raw * 4) / 4 // snap to 0.25 steps
        sender.floatValue = val
        label.stringValue = String(format: "%.1f×", val)
        onSizeChange?(val)
    }
}

// MARK: - Draggable Overlay View

class DraggableView: NSView {
    var isDragging = false
    var dragStartPoint: NSPoint = .zero
    var windowStartPoint: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        isDragging = true
        dragStartPoint = window.convertPoint(toScreen: event.locationInWindow)
        windowStartPoint = window.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window = self.window else { return }
        let currentPoint = window.convertPoint(toScreen: event.locationInWindow)
        let deltaX = currentPoint.x - dragStartPoint.x
        let deltaY = currentPoint.y - dragStartPoint.y
        var newOrigin = windowStartPoint
        newOrigin.x += deltaX
        newOrigin.y += deltaY
        // Gentle clamp to keep at least 30px visible on any screen edge
        let allScreens = NSScreen.screens
        let unionVF: NSRect = allScreens.reduce(NSRect.zero) { $0.union($1.visibleFrame) }
        let w = window.frame.width, h = window.frame.height
        newOrigin.x = max(unionVF.minX - w + 30, min(newOrigin.x, unionVF.maxX - 30))
        newOrigin.y = max(unionVF.minY - h + 30, min(newOrigin.y, unionVF.maxY - 30))
        window.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }
}

// MARK: - Floating Panel

class FloatingPanel {
    let window: NSWindow
    let gifView: NSImageView
    let overlayView: DraggableView
    let baseImageSize: CGFloat  // original GIF pixel size (240)
    let referenceSize: CGFloat = 120  // default display size at scale 1.0

    init() {
        // Load GIF from bundle with proper animation support
        guard let gifPath = Bundle.main.url(forResource: "cat", withExtension: "GIF"),
              let gifData = try? Data(contentsOf: gifPath),
              let gifImage = NSImage(data: gifData) else {
            fatalError("Cannot load cat.GIF")
        }

        // Scale to 1/4 area (120x120 from 240x240)
        let gifSize = gifImage.representations.first?.pixelsWide ?? 240
        baseImageSize = CGFloat(gifSize)
        let defaultScale: CGFloat = 0.5
        let windowSize = NSSize(width: baseImageSize * defaultScale, height: baseImageSize * defaultScale)

        // Create GIF view
        gifView = NSImageView(image: gifImage)
        gifView.imageScaling = .scaleProportionallyUpOrDown
        gifView.animates = true
        gifView.frame = NSRect(origin: .zero, size: windowSize)

        // Overlay view that captures mouse events for dragging
        overlayView = DraggableView(frame: NSRect(origin: .zero, size: windowSize))
        overlayView.addSubview(gifView)

        // Create borderless transparent window
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.contentView = overlayView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false

        // Position at bottom-right of screen
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let origin = NSPoint(
                x: visibleFrame.maxX - windowSize.width - 30,
                y: visibleFrame.minY + 60
            )
            window.setFrameOrigin(origin)
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func resize(toScale scale: CGFloat) {
        let wasAnimating = gifView.animates
        gifView.animates = false

        let size = referenceSize * scale
        var newFrame = window.frame
        let centerX = newFrame.midX
        let centerY = newFrame.midY
        newFrame.size = NSSize(width: size, height: size)
        newFrame.origin = NSPoint(x: centerX - size / 2, y: centerY - size / 2)

        let allScreens = NSScreen.screens
        let unionVF: NSRect = allScreens.reduce(NSRect.zero) { $0.union($1.visibleFrame) }
        newFrame.origin.x = max(unionVF.minX - size + 30, min(newFrame.origin.x, unionVF.maxX - 30))
        newFrame.origin.y = max(unionVF.minY - size + 30, min(newFrame.origin.y, unionVF.maxY - 30))

        window.setFrame(newFrame, display: true, animate: false)
        overlayView.setFrameSize(NSSize(width: size, height: size))
        gifView.setFrameSize(NSSize(width: size, height: size))

        gifView.animates = wasAnimating
    }
}

// MARK: - Main Entry

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
