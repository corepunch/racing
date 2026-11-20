import UIKit

/// The garage: swipe through your cars, buy performance upgrades, fit body parts and paint
/// (self-built cars), or sell.
final class TuneViewController: ScreenController {
    private let profile = Profile.shared
    private let showroom = ShowroomView()
    private let badge = ClassBadge()
    private let carName = UI.label("", UI.font(22, .black))
    private let stats = StatBars(compact: true)
    private var rows: [UpgradeRow] = []
    private let body = GlowButton("BODY & PAINT", size: 12)
    private let sell = GlowButton("SELL", tint: UI.magenta, size: 12)
    private var shown: [OwnedCar] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        addHeader("GARAGE")
        buildLayout()
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: Profile.didChange, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        showroom.isPlaying = true
        refresh()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        showroom.isPlaying = false
    }

    private func buildLayout() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = true

        badge.setContentHuggingPriority(.required, for: .horizontal)
        let head = UI.stack([badge, carName], axis: .horizontal, spacing: 10, alignment: .center)
        rows = UpgradeKind.allCases.map { kind in
            let row = UpgradeRow(kind: kind)
            row.onBuy = { [weak self] in self?.buy(kind) }
            row.onPreview = { [weak self] on in self?.preview(on ? kind : nil) }
            return row
        }
        body.onTap = { [weak self] in self?.openBody() }
        sell.onTap = { [weak self] in self?.confirmSell() }
        let actions = UI.stack([body, sell], axis: .horizontal, spacing: 10)
        actions.distribution = .fillEqually
        actions.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let upgradesTitle = UI.caps("PERFORMANCE", 10)
        let content = UI.stack([head, stats, upgradesTitle] + rows + [actions], spacing: 10)
        content.setCustomSpacing(14, after: head)
        content.setCustomSpacing(22, after: stats)
        content.setCustomSpacing(16, after: rows.last!)
        scroll.addSubview(content)

        showroom.onIndexChange = { [weak self] i in self?.show(i) }
        showroom.onSettle = { [weak self] i in
            guard let self, self.shown.indices.contains(i) else { return }
            self.profile.select(self.shown[i].id)
        }
        [showroom, scroll].forEach(view.addSubview)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            showroom.topAnchor.constraint(equalTo: safe.topAnchor, constant: 50),
            showroom.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            showroom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            showroom.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.27),
            scroll.topAnchor.constraint(equalTo: showroom.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 6),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: UI.gutter),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -UI.gutter),
        ])
    }

    @objc private func changed() {
        guard viewIfLoaded?.window != nil else { return }
        refresh()
    }

    private func refresh() {
        let cars = profile.cars
        if cars.map(\.id) != shown.map(\.id) {
            showroom.setCars(cars.map(\.design), selected: profile.selectedIndex)
        } else {
            for (i, car) in cars.enumerated() where car != shown[i] { showroom.update(car.design, at: i) }
        }
        shown = cars
        show(showroom.index)
    }

    private var current: OwnedCar? { shown.indices.contains(showroom.index) ? shown[showroom.index] : nil }

    private func show(_ i: Int) {
        guard shown.indices.contains(i) else { return }
        let car = shown[i]
        let design = car.design
        carName.text = design.name
        badge.set(design.spec)
        stats.set(design.spec.ratings, tint: UI.color(design.primary), animated: true)
        for row in rows { row.set(level: car.loadout.level(row.kind), credits: profile.credits) }
        body.isHidden = car.loadout.build == nil
        sell.isEnabled = shown.count > 1
        sell.setTitleText(shown.count > 1 ? "SELL  ·  \(Economy.credits(car.loadout.resale))" : "LAST CAR")
    }

    /// Ghost bars show what the next level would do while a buy button is held.
    private func preview(_ kind: UpgradeKind?) {
        guard let car = current else { return }
        var next = car.loadout
        if let kind, next.level(kind) < UpgradeKind.maxLevel {
            while next.upgrades.count < 4 { next.upgrades.append(0) }
            next.upgrades[kind.rawValue] += 1
        }
        stats.set(car.design.spec.ratings, preview: next.design.spec.ratings, animated: true)
    }

    private func buy(_ kind: UpgradeKind) {
        guard let car = current else { return }
        if profile.upgrade(car.id, kind) {
            UI.haptic(.medium)
            Toast.show("\(kind.title) LEVEL \(car.loadout.level(kind) + 1) FITTED", in: view, color: UI.green)
            let before = car.design.spec.carClass
            if let after = profile.cars.first(where: { $0.id == car.id })?.design.spec.carClass, after != before {
                Toast.show("NOW CLASS \(after.letter)", in: view, color: UI.color(after.color))
            }
        } else {
            Toast.show("NOT ENOUGH CREDITS", in: view, color: UI.magenta)
        }
    }

    private func openBody() {
        guard let car = current, let build = car.loadout.build else { return }
        let garage = GarageViewController(build: build) { [weak self] build in
            guard let self else { return }
            if !self.profile.apply(build, to: car.id) { Toast.show("NOT ENOUGH CREDITS", in: self.view, color: UI.magenta) }
        }
        present(garage, animated: true)
    }

    private func confirmSell() {
        guard let car = current, shown.count > 1 else { return }
        let sheet = SheetController.confirm(
            title: "SELL \(car.design.name)?",
            message: "The dealer pays \(Economy.credits(car.loadout.resale)), including part of what went into upgrades. This can't be undone.",
            confirm: "SELL FOR \(Economy.credits(car.loadout.resale))", tint: UI.magenta) { [weak self] in
            guard let self, let value = self.profile.sell(car.id) else { return }
            Toast.show("SOLD FOR \(Economy.credits(value))", in: self.view, color: UI.amber)
        }
        present(sheet, animated: true)
    }
}

/// Icon, name, five pips for the level, and the price of the next one.
private final class UpgradeRow: CardView {
    let kind: UpgradeKind
    var onBuy: (() -> Void)?
    var onPreview: ((Bool) -> Void)?
    private var pips: [UIView] = []
    private let price = GlowButton("", tint: UI.amber, size: 12)

    init(kind: UpgradeKind) {
        self.kind = kind
        super.init(raised: false)
        let icon = UIImageView(image: UI.symbol(kind.symbol, 17))
        icon.tintColor = UI.cyan
        icon.contentMode = .center
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        let title = UI.label(kind.title, UI.font(13, .black))
        let detail = UI.label(kind.detail, UIFont.systemFont(ofSize: 11, weight: .medium), UI.faint)
        let pipRow = UI.stack([], axis: .horizontal, spacing: 4)
        for _ in 0..<UpgradeKind.maxLevel {
            let pip = UIView()
            pip.layer.cornerRadius = 2
            pip.widthAnchor.constraint(equalToConstant: 18).isActive = true
            pip.heightAnchor.constraint(equalToConstant: 4).isActive = true
            pips.append(pip)
            pipRow.addArrangedSubview(pip)
        }
        let text = UI.stack([title, detail, pipRow], spacing: 4, alignment: .leading)
        text.setCustomSpacing(8, after: detail)
        price.widthAnchor.constraint(equalToConstant: 92).isActive = true
        price.heightAnchor.constraint(equalToConstant: 40).isActive = true
        price.onTap = { [weak self] in self?.onBuy?() }
        price.addAction(UIAction { [weak self] _ in self?.onPreview?(true) }, for: .touchDown)
        price.addAction(UIAction { [weak self] _ in self?.onPreview?(false) },
                        for: [.touchUpInside, .touchUpOutside, .touchCancel])
        let row = UI.stack([icon, text, price], axis: .horizontal, spacing: 12, alignment: .center)
        fill(with: row, inset: 12)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(level: Int, credits: Int) {
        for (i, pip) in pips.enumerated() { pip.backgroundColor = i < level ? UI.cyan : UIColor(white: 1, alpha: 0.12) }
        if level >= UpgradeKind.maxLevel {
            price.setTitleText("MAX")
            price.isEnabled = false
            price.accessibilityLabel = "\(kind.title) at maximum level"
        } else {
            let cost = kind.price(from: level)
            price.setTitleText(Economy.credits(cost))
            price.isEnabled = cost <= credits
            price.accessibilityLabel = "Buy \(kind.title) level \(level + 1) for \(cost) credits"
        }
    }
}

/// Every car for sale on its own podium.
final class DealerViewController: ScreenController {
    private let profile = Profile.shared
    private let showroom = ShowroomView()
    private let badge = ClassBadge()
    private let carName = UI.label("", UI.font(24, .black))
    private let carLine = UI.caps("", 10, UI.cyan)
    private let stats = StatBars()
    private let dots = PageDots()
    private let buy = GlowButton("", tint: UI.amber, filled: true, size: 17)
    private let catalog = Dealer.catalog

    override func viewDidLoad() {
        super.viewDidLoad()
        addHeader("DEALER")
        badge.setContentHuggingPriority(.required, for: .horizontal)
        let head = UI.stack([badge, carName], axis: .horizontal, spacing: 10, alignment: .center)
        let info = UI.stack([carLine, head, stats, buy], spacing: 8)
        info.setCustomSpacing(16, after: head)
        info.setCustomSpacing(22, after: stats)
        buy.heightAnchor.constraint(equalToConstant: 60).isActive = true
        buy.onTap = { [weak self] in self?.confirmBuy() }
        showroom.onIndexChange = { [weak self] i in self?.show(i) }
        [showroom, dots, info].forEach(view.addSubview)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            showroom.topAnchor.constraint(equalTo: safe.topAnchor, constant: 50),
            showroom.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            showroom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            showroom.bottomAnchor.constraint(equalTo: dots.topAnchor, constant: -8),
            dots.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dots.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dots.bottomAnchor.constraint(equalTo: info.topAnchor, constant: -20),
            info.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: UI.gutter),
            info.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -UI.gutter),
            info.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
        ])
        showroom.setCars(catalog.map(\.design), selected: 0)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: Profile.didChange, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        showroom.isPlaying = true
        show(showroom.index)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        showroom.isPlaying = false
    }

    @objc private func changed() { show(showroom.index) }

    private func show(_ i: Int) {
        let car = catalog[i]
        let design = car.design
        carName.text = design.name
        carLine.attributedText = NSAttributedString(string: design.className, attributes: [.kern: 1.4])
        carLine.textColor = UI.color(design.glow)
        badge.set(design.spec)
        stats.set(design.spec.ratings, tint: UI.color(design.primary), animated: true)
        dots.set(count: catalog.count, current: i)
        if profile.owns(car.blueprint) {
            buy.setTitleText("IN YOUR GARAGE")
            buy.restyle(tint: UI.green, filled: false)
            buy.isEnabled = false
        } else {
            buy.setTitleText("BUY  ·  \(Economy.credits(car.price))")
            buy.restyle(tint: UI.amber, filled: true)
            buy.isEnabled = profile.credits >= car.price
        }
    }

    private func confirmBuy() {
        let car = catalog[showroom.index]
        let sheet = SheetController.confirm(
            title: "BUY \(car.design.name)?",
            message: "Class \(car.design.spec.carClass.letter), performance \(car.design.spec.index). "
                + "\(Economy.credits(car.price)) leaves you \(Economy.credits(profile.credits - car.price)). It goes straight to your garage.",
            confirm: "BUY FOR \(Economy.credits(car.price))", tint: UI.amber) { [weak self] in
            guard let self else { return }
            if self.profile.buy(car) {
                UI.haptic(.heavy)
                Toast.show("\(car.design.name) IS YOURS", in: self.view, color: UI.green)
            }
        }
        present(sheet, animated: true)
    }
}

/// Driver name, assists, haptics, and starting over.
final class SettingsViewController: ScreenController, UITextFieldDelegate {
    private let profile = Profile.shared
    private let nameField = UITextField()

    override init(nibName: String?, bundle: Bundle?) {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        sheetPresentationController?.detents = [.large()]
        sheetPresentationController?.prefersGrabberVisible = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let title = UI.label("SETTINGS", UI.font(22, .black))
        title.accessibilityTraits = .header
        let close = CircleButton(symbol: "xmark", size: 36)
        close.accessibilityLabel = "Close"
        close.onTap = { [weak self] in self?.dismiss(animated: true) }
        let header = UI.stack([title, close], axis: .horizontal, alignment: .center)

        nameField.text = profile.driver
        nameField.font = UI.font(17, .black)
        nameField.textColor = .white
        nameField.autocapitalizationType = .allCharacters
        nameField.autocorrectionType = .no
        nameField.returnKeyType = .done
        nameField.delegate = self
        nameField.accessibilityLabel = "Driver name"
        nameField.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let nameCard = CardView()
        nameCard.fill(with: UI.stack([UI.caps("DRIVER NAME", 9), nameField], spacing: 6), inset: 14)

        let assist = toggleRow("DRIVER ASSIST", "Lifts for corners taken too fast and nudges you off barriers. Never steers for you.",
                               on: profile.assist) { [weak self] in self?.profile.assist = $0 }
        let haptics = toggleRow("HAPTICS", "Taps for the countdown, hits and menus.", on: profile.haptics) { [weak self] in
            self?.profile.haptics = $0
        }

        let record = CardView()
        let lines = [("RACES", "\(profile.races)"), ("WINS", "\(profile.wins)"), ("EARNINGS", Economy.credits(profile.earnings)),
                     ("CARS", "\(profile.cars.count)")].map { name, value -> UIView in
            let l = UI.caps(name, 10, UI.dim)
            let v = UI.label(value, UI.digits(15, .bold), .white, align: .right)
            return UI.stack([l, v], axis: .horizontal, alignment: .center)
        }
        record.fill(with: UI.stack([UI.caps("CAREER", 9)] + lines, spacing: 8), inset: 14)

        let reset = GlowButton("RESET CAREER", tint: UI.magenta, size: 13)
        reset.heightAnchor.constraint(equalToConstant: 48).isActive = true
        reset.onTap = { [weak self] in self?.confirmReset() }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let footer = UI.caps("ARCLINE \(version)", 9)
        footer.textAlignment = .center

        let stack = UI.stack([header, nameCard, assist, haptics, record, reset, footer], spacing: 12)
        stack.setCustomSpacing(20, after: header)
        stack.setCustomSpacing(24, after: record)
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safe.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: UI.gutter),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -UI.gutter),
        ])
    }

    private func toggleRow(_ title: String, _ detail: String, on: Bool, change: @escaping (Bool) -> Void) -> UIView {
        let card = CardView()
        let toggle = UISwitch()
        toggle.isOn = on
        toggle.onTintColor = UI.cyan
        toggle.accessibilityLabel = title.capitalized
        toggle.addAction(UIAction { _ in change(toggle.isOn) }, for: .valueChanged)
        let text = UI.stack([UI.label(title, UI.font(13, .black)), UI.body(detail, 12, UI.faint)], spacing: 4)
        card.fill(with: UI.stack([text, toggle], axis: .horizontal, spacing: 12, alignment: .center), inset: 14)
        return card
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        let name = (textField.text ?? "").trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { profile.driver = name }
        textField.text = profile.driver
    }

    private func confirmReset() {
        let sheet = SheetController.confirm(title: "RESET CAREER?",
                                            message: "Cars, upgrades, parts, credits and wins go back to the start. This can't be undone.",
                                            confirm: "RESET EVERYTHING", tint: UI.magenta) { [weak self] in
            self?.profile.reset()
            self?.dismiss(animated: true)
        }
        present(sheet, animated: true)
    }
}
