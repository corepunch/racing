import UIKit
import SceneKit

/// Home: your cars on their podiums, the wallet, and the way into everything else.
final class MenuViewController: ScreenController {

    private let profile = Profile.shared
    private let showroom = ShowroomView()
    private let wallet = CreditsPill()
    private let record = UI.caps("", 10, UI.faint)
    private let badge = ClassBadge()
    private let carName = UI.label("", UI.font(26, .black))
    private let carLine = UI.caps("", 10, UI.cyan)
    private let dots = PageDots()
    private let stats = StatBars(compact: true)
    private let garageTile = TileButton(title: "GARAGE", symbol: "wrench.and.screwdriver.fill")
    private let dealerTile = TileButton(title: "DEALER", symbol: "tag.fill", tint: UI.amber)
    private let onlineTile = TileButton(title: "ONLINE", symbol: "antenna.radiowaves.left.and.right", tint: UI.magenta)

    /// What the showroom is showing, to rebuild only when the garage changed.
    private var shown: [OwnedCar] = []
    private var didAutostart = false

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        NotificationCenter.default.addObserver(self, selector: #selector(profileChanged), name: Profile.didChange, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        showroom.isPlaying = true
        refreshCars()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        showroom.isPlaying = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        autostartIfAsked()
    }

    // MARK: - Layout

    private func buildLayout() {
        let wordmark = UI.label("ARCLINE", UI.font(24, .black))
        wordmark.accessibilityTraits = .header
        let brand = UI.stack([wordmark, record], spacing: 0)
        let settings = CircleButton(symbol: "gearshape.fill", size: 36)
        settings.accessibilityLabel = "Settings"
        settings.onTap = { [weak self] in self?.present(SettingsViewController(), animated: true) }
        let topRight = UI.stack([wallet, settings], axis: .horizontal, spacing: 10, alignment: .center)

        let nameRow = UI.stack([badge, carName], axis: .horizontal, spacing: 10, alignment: .center)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        let info = UI.stack([carLine, nameRow, stats], spacing: 6)
        info.setCustomSpacing(14, after: nameRow)

        let race = GlowButton("RACE", filled: true, size: 22)
        race.accessibilityHint = "Circuit events and street challenges"
        race.onTap = { [weak self] in self?.navigationController?.pushViewController(EventsViewController(), animated: true) }

        garageTile.onTap = { [weak self] in self?.navigationController?.pushViewController(TuneViewController(), animated: true) }
        dealerTile.onTap = { [weak self] in self?.navigationController?.pushViewController(DealerViewController(), animated: true) }
        onlineTile.onTap = { [weak self] in self?.navigationController?.pushViewController(OnlineViewController(), animated: true) }
        onlineTile.detail = "Local network"
        let tiles = UI.stack([garageTile, dealerTile, onlineTile], axis: .horizontal, spacing: 10)
        tiles.distribution = .fillEqually

        let lower = UI.stack([info, race, tiles], spacing: 16)
        lower.setCustomSpacing(20, after: info)

        showroom.onIndexChange = { [weak self] i in self?.showInfo(i, animated: true) }
        showroom.onSettle = { [weak self] i in
            guard let self, self.shown.indices.contains(i) else { return }
            self.profile.select(self.shown[i].id)
        }

        [showroom, brand, topRight, dots, lower].forEach(view.addSubview)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            brand.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            brand.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: UI.gutter),
            topRight.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
            topRight.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -UI.gutter),

            showroom.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 0),
            showroom.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            showroom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            showroom.bottomAnchor.constraint(equalTo: dots.topAnchor, constant: -6),

            dots.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dots.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dots.bottomAnchor.constraint(equalTo: lower.topAnchor, constant: -18),

            lower.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: UI.gutter),
            lower.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -UI.gutter),
            lower.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
            race.heightAnchor.constraint(equalToConstant: 62),
            tiles.heightAnchor.constraint(equalToConstant: 92),
        ])
    }

    // MARK: - Content

    @objc private func profileChanged() {
        guard viewIfLoaded?.window != nil else { return }
        refreshCars()
    }

    private func refreshCars() {
        let cars = profile.cars
        if cars != shown {
            let sameSet = cars.map(\.id) == shown.map(\.id)
            if sameSet {
                for (i, car) in cars.enumerated() where car != shown[i] { showroom.update(car.design, at: i) }
            } else {
                showroom.setCars(cars.map(\.design), selected: profile.selectedIndex)
            }
            shown = cars
        }
        if showroom.index != profile.selectedIndex { showroom.scroll(to: profile.selectedIndex, animated: false) }
        showInfo(showroom.index, animated: false)
        record.attributedText = NSAttributedString(
            string: "\(profile.wins) WINS  ·  \(profile.races) RACES", attributes: [.kern: 1.4])
        garageTile.detail = "Upgrades · parts"
        dealerTile.detail = "\(Dealer.catalog.count) cars for sale"
    }

    private func showInfo(_ i: Int, animated: Bool) {
        guard shown.indices.contains(i) else { return }
        let car = shown[i]
        let design = car.design
        carName.text = design.name
        var line = design.className
        if let from = car.wonFrom { line += "  ·  WON FROM \(from)" }
        let upgrades = car.loadout.upgrades.reduce(0, +)
        if upgrades > 0 { line += "  ·  +\(upgrades) UPGRADES" }
        carLine.attributedText = NSAttributedString(string: line, attributes: [.kern: 1.4])
        carLine.textColor = UI.color(design.glow)
        badge.set(design.spec)
        stats.set(design.spec.ratings, tint: UI.color(design.primary), animated: animated)
        dots.set(count: shown.count, current: i)
        dots.isHidden = shown.count < 2
    }

    // MARK: - Debug launch

    /// `-autostart YES` goes straight into a race; `-track`, `-car`, `-seed`, `-laps`, `-driver`,
    /// `-autoDrive` refine it. `-mpHost YES` / `-mpJoin <ip>` open the online lobby directly.
    private func autostartIfAsked() {
        let defaults = UserDefaults.standard
        guard !didAutostart else { return }
        didAutostart = true
        // `-grant <credits>`: testing money.
        if defaults.integer(forKey: "grant") > 0 { profile.earn(defaults.integer(forKey: "grant")) }
        if defaults.bool(forKey: "mpHost") || defaults.string(forKey: "mpJoin") != nil {
            navigationController?.pushViewController(OnlineViewController(), animated: false)
            return
        }
        guard defaults.bool(forKey: "autostart") else { return }
        let tracks = TrackLibrary.all
        var definition = tracks[min(max(defaults.integer(forKey: "track"), 0), tracks.count - 1)]
        if defaults.integer(forKey: "seed") > 0 { definition = TrackLibrary.generated(seed: UInt64(defaults.integer(forKey: "seed"))) }
        var config = RaceConfig(definition: definition, carIndex: defaults.integer(forKey: "car"))
        config.assist = profile.assist
        if defaults.integer(forKey: "laps") > 0 { config.laps = defaults.integer(forKey: "laps") }
        let game = GameViewController(config: config)
        game.autoDrive = defaults.bool(forKey: "autoDrive")
        game.debugDriver = defaults.string(forKey: "driver").flatMap(GameScene.DebugDriver.init(rawValue:))
        present(game, animated: false)
    }
}
