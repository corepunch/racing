import UIKit

/// Race read-outs. Everything sits in the top third; the bottom of the screen belongs to the thumb.
final class HUDView: UIView {
    private let position = UI.label("", UI.font(44, .black), .white)
    private let positionOf = UI.label("", UI.font(13, .bold), UI.dim)
    private let lap = UI.label("", UI.font(15, .heavy), .white, align: .right)
    private let time = UI.label("", UI.digits(15, .semibold), UI.dim, align: .right)
    private let speed = UI.label("0", UI.digits(40, .black), .white, align: .center)
    private let unit = UI.label("KM/H", UI.font(10, .bold), UI.dim, align: .center)
    private let banner = UI.label("", UI.font(64, .black), .white, align: .center)
    private let note = UI.label("", UI.font(17, .heavy), UI.cyan, align: .center)
    private let hint = UI.label("SLIDE TO STEER  ·  PULL DOWN TO SLOW, FURTHER TO BRAKE", UI.font(11, .bold), UI.dim, align: .center)
    private let map = TrackMapView()
    private var noteToken = 0
    private var bannerToken = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        [position, positionOf, lap, time, speed, unit, banner, note, hint, map].forEach(addSubview)
        banner.alpha = 0
        note.alpha = 0
        map.lineColor = UIColor(white: 1, alpha: 0.55)
        for l in [position, positionOf, lap, time, speed, unit, banner, note, hint] {
            l.layer.shadowColor = UIColor.black.cgColor
            l.layer.shadowOpacity = 0.9
            l.layer.shadowRadius = 4
            l.layer.shadowOffset = .zero
        }
        let safe = safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            position.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            position.topAnchor.constraint(equalTo: safe.topAnchor, constant: 2),
            positionOf.leadingAnchor.constraint(equalTo: position.trailingAnchor, constant: 4),
            positionOf.lastBaselineAnchor.constraint(equalTo: position.lastBaselineAnchor),

            lap.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -64),
            lap.topAnchor.constraint(equalTo: safe.topAnchor, constant: 10),
            time.trailingAnchor.constraint(equalTo: lap.trailingAnchor),
            time.topAnchor.constraint(equalTo: lap.bottomAnchor, constant: 2),

            speed.centerXAnchor.constraint(equalTo: centerXAnchor),
            speed.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            unit.centerXAnchor.constraint(equalTo: centerXAnchor),
            unit.topAnchor.constraint(equalTo: speed.bottomAnchor, constant: -4),

            map.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -10),
            map.topAnchor.constraint(equalTo: time.bottomAnchor, constant: 10),
            map.widthAnchor.constraint(equalToConstant: 92),
            map.heightAnchor.constraint(equalToConstant: 92),

            banner.centerXAnchor.constraint(equalTo: centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -110),
            banner.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
            note.centerXAnchor.constraint(equalTo: centerXAnchor),
            note.topAnchor.constraint(equalTo: unit.bottomAnchor, constant: 18),
            note.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -18),
            hint.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setTrack(_ path: TrackPath) { map.setTrack(path) }

    func update(_ state: HUDState) {
        position.text = "\(state.position)"
        positionOf.text = "/\(state.count)"
        lap.text = "LAP \(state.lap)/\(state.laps)"
        time.text = UI.time(state.raceTime)
        speed.text = "\(Int(state.speedKMH))"
        speed.textColor = state.boosting ? UI.amber : .white
        map.setDots(state.dots)
    }

    /// Large centre text: the countdown and GO.
    func flash(_ text: String, color: UIColor = .white, hold: TimeInterval = 0.7) {
        bannerToken += 1
        let token = bannerToken
        banner.text = text
        banner.textColor = color
        banner.alpha = 1
        banner.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        UIView.animate(withDuration: 0.18) { self.banner.transform = .identity }
        UIView.animate(withDuration: 0.3, delay: hold, options: []) {
            if token == self.bannerToken { self.banner.alpha = 0 }
        }
    }

    /// Small line under the speed: lap times, boost, final lap.
    func announce(_ text: String, color: UIColor = UI.cyan, hold: TimeInterval = 1.6) {
        noteToken += 1
        let token = noteToken
        note.text = text
        note.textColor = color
        note.alpha = 1
        UIView.animate(withDuration: 0.3, delay: hold, options: []) {
            if token == self.noteToken { self.note.alpha = 0 }
        }
    }

    func setHintVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.4) { self.hint.alpha = visible ? 1 : 0 }
    }
}

/// A line of the results panel's payout block: PRIZE  ₵1,500.
struct ResultLine {
    var title: String
    var value: String
    var color: UIColor = UI.amber
}

/// Dimmed overlay with a title, a few lines and stacked buttons: pause and results.
final class PanelView: UIView {
    init(title: String, titleColor: UIColor = .white, subtitle: String? = nil,
         rows: [(left: String, right: String, highlight: Bool)] = [], money: [ResultLine] = [], buttons: [GlowButton]) {
        super.init(frame: .zero)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = UIColor(red: 0.01, green: 0.02, blue: 0.05, alpha: 0.82)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let head = UI.label(title, UI.font(40, .black), titleColor, align: .center)
        stack.addArrangedSubview(head)
        if let subtitle = subtitle {
            stack.addArrangedSubview(UI.label(subtitle, UI.font(14, .bold), UI.dim, align: .center))
        }
        stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)

        for row in rows {
            let line = UIStackView()
            line.axis = .horizontal
            let color: UIColor = row.highlight ? UI.cyan : UIColor(white: 1, alpha: 0.82)
            let left = UI.label(row.left, UI.font(14, .bold), color)
            let right = UI.label(row.right, UI.digits(15, .semibold), color, align: .right)
            right.setContentHuggingPriority(.required, for: .horizontal)
            line.addArrangedSubview(left)
            line.addArrangedSubview(right)
            stack.addArrangedSubview(line)
        }
        if !rows.isEmpty { stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!) }

        if !money.isEmpty {
            let card = CardView(raised: true)
            let lines = money.map { line -> UIView in
                let left = UI.caps(line.title, 11, UIColor(white: 1, alpha: 0.8))
                let right = UI.label(line.value, UI.digits(17, .heavy), line.color, align: .right)
                right.setContentHuggingPriority(.required, for: .horizontal)
                return UI.stack([left, right], axis: .horizontal, spacing: 8, alignment: .center)
            }
            card.fill(with: UI.stack(lines, spacing: 8), inset: 14)
            stack.addArrangedSubview(card)
            stack.setCustomSpacing(22, after: card)
        }

        for button in buttons {
            stack.addArrangedSubview(button)
            button.heightAnchor.constraint(equalToConstant: 58).isActive = true
        }

        // Buttons sit low, under the thumb.
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.78),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -44),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
