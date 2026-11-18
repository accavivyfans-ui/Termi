import UIKit
import SwiftTerm

/// Termius 스타일 키보드 위 보조키 바.
/// 왼쪽은 가로 스크롤 키들, 오른쪽 끝은 고정된 "키보드 내리기" 버튼 → 누르면 터미널이 화면 전체로 늘어남.
final class KeyBar: UIInputView, UIInputViewAudioFeedback {
    weak var terminal: TerminalView?
    var onHideKeyboard: (() -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var ctrlButton: UIButton?
    private var altButton: UIButton?
    private var repeatTimer: Timer?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private let barColor = UIColor(hex: 0x171A22)
    private let keyColor = UIColor(hex: 0x262A35)
    private let keyActive = UIColor(hex: 0x5B8CFF)

    var enableInputClicksWhenVisible: Bool { true }

    init(terminal: TerminalView) {
        self.terminal = terminal
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 48), inputViewStyle: .default)
        allowsSelfSizing = true
        autoresizingMask = [.flexibleWidth]
        backgroundColor = barColor
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(modifierReset),
                                               name: .terminalViewControlModifierReset, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(modifierReset),
                                               name: .terminalViewMetaModifierReset, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 48) }

    // MARK: - Layout

    private func build() {
        let top = UIView()
        top.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        top.translatesAutoresizingMaskIntoConstraints = false
        addSubview(top)

        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.delaysContentTouches = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let hide = makeKey(icon: "keyboard.chevron.compact.down", accent: true) { [weak self] in
            self?.onHideKeyboard?()
        }
        hide.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hide)

        let sep = UIView()
        sep.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor),
            top.leadingAnchor.constraint(equalTo: leadingAnchor),
            top.trailingAnchor.constraint(equalTo: trailingAnchor),
            top.heightAnchor.constraint(equalToConstant: 0.5),

            hide.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            hide.centerYAnchor.constraint(equalTo: centerYAnchor),
            hide.widthAnchor.constraint(equalToConstant: 48),
            hide.heightAnchor.constraint(equalToConstant: 34),

            sep.trailingAnchor.constraint(equalTo: hide.leadingAnchor, constant: -6),
            sep.centerYAnchor.constraint(equalTo: centerYAnchor),
            sep.widthAnchor.constraint(equalToConstant: 1),
            sep.heightAnchor.constraint(equalToConstant: 24),

            scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sep.leadingAnchor, constant: -2),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 34),
        ])

        add(text: "esc") { [weak self] in self?.send([0x1b]) }
        let ctrl = add(text: "ctrl") { [weak self] in self?.toggleCtrl() }
        ctrlButton = ctrl
        let alt = add(text: "alt") { [weak self] in self?.toggleAlt() }
        altButton = alt
        add(text: "tab") { [weak self] in self?.send([0x09]) }
        addRepeat(icon: "arrow.up") { [weak self] in self?.terminal?.sendKeyUp() }
        addRepeat(icon: "arrow.down") { [weak self] in self?.terminal?.sendKeyDown() }
        addRepeat(icon: "arrow.left") { [weak self] in self?.terminal?.sendKeyLeft() }
        addRepeat(icon: "arrow.right") { [weak self] in self?.terminal?.sendKeyRight() }
        for s in ["~", "/", "|", "-", "_", ":", "*", "&", "$", "\"", "'", "`", "{", "}", "[", "]", "<", ">", "\\"] {
            add(text: s, mono: true) { [weak self] in self?.terminal?.send(txt: s) }
        }
        add(text: "^C") { [weak self] in self?.send([0x03]) }
        add(text: "^D") { [weak self] in self?.send([0x04]) }
        add(text: "^Z") { [weak self] in self?.send([0x1a]) }
        add(text: "^L") { [weak self] in self?.send([0x0c]) }
        add(text: "home") { [weak self] in self?.terminal?.sendKeyHome() }
        add(text: "end") { [weak self] in self?.terminal?.sendKeyEnd() }
        add(text: "pgup") { [weak self] in self?.send([0x1b, 0x5b, 0x35, 0x7e]) }
        add(text: "pgdn") { [weak self] in self?.send([0x1b, 0x5b, 0x36, 0x7e]) }
    }

    // MARK: - Buttons

    private final class Key: UIButton {
        var action: (() -> Void)?
        var onDown: (() -> Void)?
        var onUp: (() -> Void)?
        override var isHighlighted: Bool {
            didSet { alpha = isHighlighted ? 0.55 : 1 }
        }
    }

    private func makeKey(text: String? = nil, icon: String? = nil, mono: Bool = false, accent: Bool = false,
                         action: @escaping () -> Void) -> Key {
        let b = Key(type: .custom)
        b.action = action
        b.backgroundColor = accent ? UIColor(hex: 0x2A3350) : keyColor
        b.layer.cornerRadius = 8
        b.layer.cornerCurve = .continuous
        b.tintColor = accent ? keyActive : .white
        if let icon {
            let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            b.setImage(UIImage(systemName: icon, withConfiguration: cfg), for: .normal)
        }
        if let text {
            b.setTitle(text, for: .normal)
            b.setTitleColor(UIColor(white: 0.93, alpha: 1), for: .normal)
            b.titleLabel?.font = mono
                ? .monospacedSystemFont(ofSize: 16, weight: .medium)
                : .systemFont(ofSize: 14, weight: .semibold)
        }
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
        return b
    }

    @discardableResult
    private func add(text: String? = nil, icon: String? = nil, mono: Bool = false,
                     action: @escaping () -> Void) -> Key {
        let b = makeKey(text: text, icon: icon, mono: mono, action: action)
        b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        stack.addArrangedSubview(b)
        return b
    }

    private func addRepeat(icon: String, action: @escaping () -> Void) {
        let b = Key(type: .custom)
        b.backgroundColor = keyColor
        b.layer.cornerRadius = 8
        b.layer.cornerCurve = .continuous
        b.tintColor = .white
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        b.setImage(UIImage(systemName: icon, withConfiguration: cfg), for: .normal)
        b.onDown = action
        b.addTarget(self, action: #selector(repeatDown(_:)), for: .touchDown)
        b.addTarget(self, action: #selector(repeatUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        b.widthAnchor.constraint(equalToConstant: 42).isActive = true
        stack.addArrangedSubview(b)
    }

    @objc private func tapped(_ sender: Key) {
        click()
        sender.action?()
    }

    @objc private func repeatDown(_ sender: Key) {
        click()
        sender.onDown?()
        repeatTimer?.invalidate()
        let action = sender.onDown
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in action?() }
        }
    }

    @objc private func repeatUp() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    private func click() {
        UIDevice.current.playInputClick()
        haptic.impactOccurred()
    }

    private func send(_ bytes: [UInt8]) { terminal?.send(bytes) }

    // MARK: - Modifiers

    private func toggleCtrl() {
        guard let t = terminal else { return }
        t.controlModifier.toggle()
        refreshModifiers()
    }

    private func toggleAlt() {
        guard let t = terminal else { return }
        t.metaModifier.toggle()
        refreshModifiers()
    }

    @objc private func modifierReset() {
        DispatchQueue.main.async { self.refreshModifiers() }
    }

    private func refreshModifiers() {
        let ctrlOn = terminal?.controlModifier ?? false
        let altOn = terminal?.metaModifier ?? false
        ctrlButton?.backgroundColor = ctrlOn ? keyActive : keyColor
        altButton?.backgroundColor = altOn ? keyActive : keyColor
    }
}
