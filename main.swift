// Clawdling — a desktop pet that eats while you work in Claude Code.
// A floating window over every screen; Claude Code hooks drop food into ~/.clawdling/events.jsonl.
import AppKit

// MARK: - Constants

let home = NSHomeDirectory()
let dataDir = ProcessInfo.processInfo.environment["CLAWDLING_DIR"] ?? (home + "/.clawdling")
let eventsPath = dataDir + "/events.jsonl"
let statePath = dataDir + "/state.json"
let tgScript = dataDir + "/tg.py"

let DECAY_PER_HOUR = 4.0      // 100 → 0 in about a day
let DEATH_HOURS = 48.0        // longer without food and the pet dies
let HATCH_POINTS = 15.0       // food an egg needs to hatch
let EVOLVE_DAYS = 7.0
let SLEEP_IDLE = 20.0 * 60    // 20 idle minutes and it falls asleep

let FOOD: [String: (emoji: String, pts: Double)] = [
    "prompt": ("🍙", 3), "edit": ("🍎", 1), "bash": ("☕️", 1), "web": ("🐟", 2),
    "agent": ("🎂", 10), "done": ("🍪", 5), "other": ("🍬", 0.5),
]

// Interface language: Russian when the system prefers it, English otherwise.
let RU = Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
func L(_ en: String, _ ru: String) -> String { RU ? ru : en }

let NAMES = RU
    ? ["Бублик", "Пиксель", "Кекс", "Шпрота", "Мочи", "Тофу", "Байт", "Кнопка",
       "Пельмень", "Зефир", "Чип", "Гоша", "Крошка", "Сухарик", "Пончик", "Бит"]
    : ["Bagel", "Pixel", "Muffin", "Sprout", "Mochi", "Tofu", "Byte", "Button",
       "Dumpling", "Marshmallow", "Chip", "Noodle", "Crumb", "Biscuit", "Donut", "Bit"]

let FORM_NAME = ["hacker": L("Hacker", "Хакер"), "builder": L("Builder", "Строитель"),
                 "explorer": L("Explorer", "Исследователь"), "owl": L("Night Owl", "Сова"),
                 "queen": L("Hive Queen", "Королева улья")]

// MARK: - Sprites (left half, 8 columns, mirrored to 16)

struct Species {
    let id: String
    let name: String
    let rows: [String]
    let colors: [Int]
    var accent: Int = 0x000000
    var light: Int? = nil
    var outline: Int? = nil
    var mouth: Int? = nil
    var floats: Bool = false
}

let SPECIES: [Species] = [
    Species(id: "slime", name: L("slime", "слизень"), rows: [
        "........", "........", "......oo", ".....obb", "....obbl", "...obblb", "..obbbbb",
        "..obewbb", ".obbeebb", ".obpbbbm", ".obbbbbb", ".odbbbbb", "..oddddd", "...ooooo",
    ], colors: [0x6fd36b, 0x6ab8f0, 0xf28fc0, 0xb48cf2]),
    Species(id: "ghost", name: L("ghost", "призрак"), rows: [
        "........", "........", ".....ooo", "....obbb", "...obbbb", "..obbbbb", "..obbbbb",
        "..obewbb", "..obeebb", "..obpbbm", "..obbbbb", "..obbbbb", "..obbobb", "...oo.oo",
    ], colors: [0xf1eefc, 0xdff3ff], light: 0xffffff, outline: 0x6b6390, floats: true),
    Species(id: "cat", name: L("kitty", "котик"), rows: [
        "........", "..o.....", "..oo....", "..oao...", "..obaooo", ".obbbbbb", ".obbbbbb",
        ".obbewbb", ".obbeebb", ".obpbbbm", ".obbbbbb", "..obbbbb", "..obbobb", "...oo.oo",
    ], colors: [0xb9b9c4, 0xf2a65a, 0xf3e2c3, 0x5a5a66], accent: 0xf6a5b5),
    Species(id: "fox", name: L("fox kit", "лисёнок"), rows: [
        "........", ".o......", ".oo.....", ".oao....", ".oaao...", ".obaaooo", ".obbbbbb",
        ".obbewbb", ".obbeebb", ".obbbbbb", ".olllllm", "..olllll", "...ollll", "....oooo",
    ], colors: [0xf08a3c, 0xe9b44c], accent: 0x3a2620, light: 0xfff3e6),
    Species(id: "frog", name: L("froglet", "лягушонок"), rows: [
        "........", "........", "..ooo...", ".obbbo..", ".obewo..", ".obeeboo", "obbbbbbb",
        "obpbbbbb", "obbbmmmm", "obbbbbbb", ".obbllll", ".obbllll", "..obbooo", ".oooo...",
    ], colors: [0x7cc96a, 0x5fc4b0], light: 0xd9f2b8),
    Species(id: "crab", name: L("crab", "крабик"), rows: [
        "........", ".oo.oo..", "oaaoaao.", ".oaaao..", "..oao...", "..oooooo", ".obbbbbb",
        ".obbewbb", "obbbeebb", "obpbbbbm", "obbbbbbb", ".obbbbbb", "..oooooo", ".o.o.o..",
    ], colors: [0xe8604c, 0xf08a5d], accent: 0xc2402f),
    Species(id: "chick", name: L("chick", "цыплёнок"), rows: [
        "........", "......o.", "......oo", "....oobb", "...obbbb", "..obbbbb", "..obewbb",
        ".obbeebb", ".obpbbaa", ".obbbbbm", ".obbbbbb", "..obbbbb", "...ooooo", "....a.a.",
    ], colors: [0xffd84d], accent: 0xff9a2e, mouth: 0xff9a2e),
]

let EGG_ROWS = [
    "........", "........", "......oo", ".....obb", "....obbb", "....obab", "...obbbb",
    "...obabb", "...obbbb", "..obbbbb", "..obbbab", "..obbbbb", "...obbbb", "....oooo",
]
let TOMB_ROWS = [
    "........", "........", "....oooo", "...obbbb", "..obbbbb", "..obbbbo", "..obbooo",
    "..obbbbo", "..obbbbo", "..obbbbb", "..obbbbb", "..obbbbb", ".aobbbbb", "aaaaaaaa",
]

struct Sprite {
    let grid: [[Character]]
    let top: Int
    let eyes: [(Int, Int)]     // (row, col)
    let mouthRow: Double

    init(_ halves: [String]) {
        grid = halves.map { let a = Array($0); return a + a.reversed() }
        top = grid.firstIndex { $0.contains { $0 != "." } } ?? 0
        var e: [(Int, Int)] = []
        var m: [Int] = []
        for (r, row) in grid.enumerated() {
            for (c, ch) in row.enumerated() {
                if ch == "e" || ch == "w" { e.append((r, c)) }
                if ch == "m" { m.append(r) }
            }
        }
        eyes = e
        mouthRow = m.isEmpty ? 9 : Double(m.reduce(0, +)) / Double(m.count)
    }
}

func hex(_ v: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
            blue: CGFloat(v & 255) / 255, alpha: a)
}

func palette(body b: Int, accent: Int, light: Int?, outline: Int?, mouth: Int?) -> [Character: NSColor] {
    let body = hex(b)
    return [
        "b": body,
        "o": outline.map { hex($0) } ?? body.blended(withFraction: 0.68, of: .black)!,
        "l": light.map { hex($0) } ?? body.blended(withFraction: 0.5, of: .white)!,
        "d": body.blended(withFraction: 0.2, of: .black)!,
        "e": hex(0x1d1b2b), "w": .white, "p": hex(0xff7aa2, 0.6),
        "m": mouth.map { hex($0) } ?? hex(0x5b2433),
        "a": hex(accent),
    ]
}

// MARK: - State

struct Grave: Codable {
    var name: String
    var species: String
    var form: String?
    var days: Int
    var diedAt: Double
}

struct Pet: Codable {
    var name: String
    var species: String
    var colorIndex: Int
    var bornAt: Double
    var hatchedAt: Double?
    var eggPoints: Double = 0
    var full: Double = 70
    var fullAt: Double
    var lastFood: Double
    var dead = false
    var diedAt: Double?
    var form: String?
    var counts: [String: Int] = [:]
    var night = 0
    var fedDays: [String] = []
    var totalPoints: Double = 0
    var notifiedHungry = false
    var notifiedDying = false

    static func newEgg(now: Double) -> Pet {
        let sp = SPECIES.randomElement()!
        return Pet(name: NAMES.randomElement()!, species: sp.id, colorIndex: Int.random(in: 0..<sp.colors.count),
                   bornAt: now, fullAt: now, lastFood: now)
    }
}

struct Save: Codable {
    var pet: Pet
    var graves: [Grave] = []
    var offset: UInt64 = 0
    var scale: Double = 1
    var tg = true
    var roam: Bool? = true   // optional so an older state.json without the key still decodes
}

func dayKey(_ t: Double) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date(timeIntervalSince1970: t))
}

// MARK: - World

final class World {
    var save: Save
    var dirty = false
    var onFood: ((String, Double) -> Void)?
    var onAsk: (() -> Void)?
    var onDone: (() -> Void)?
    var onActivity: (() -> Void)?

    init() {
        try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        let now = Date().timeIntervalSince1970
        if let d = FileManager.default.contents(atPath: statePath), let s = try? JSONDecoder().decode(Save.self, from: d) {
            save = s
        } else {
            save = Save(pet: Pet.newEgg(now: now))
            // earlier events do not count: a new pet starts from a clean slate
            let size = (try? FileManager.default.attributesOfItem(atPath: eventsPath)[.size] as? UInt64) ?? 0
            save.offset = size
            dirty = true
        }
    }

    var pet: Pet {
        get { save.pet }
        set { save.pet = newValue; dirty = true }
    }
    var species: Species { SPECIES.first { $0.id == pet.species } ?? SPECIES[0] }
    var isEgg: Bool { pet.hatchedAt == nil }

    func full(at t: Double) -> Double {
        if isEgg { return 100 }
        return max(0, pet.full - DECAY_PER_HOUR * (t - pet.fullAt) / 3600)
    }

    func persist() {
        guard dirty else { return }
        dirty = false
        if let d = try? JSONEncoder().encode(save) {
            try? d.write(to: URL(fileURLWithPath: statePath), options: .atomic)
        }
    }

    /// Reads the lines appended to events.jsonl since the last poll.
    func pollEvents(now: Double) {
        guard let fh = FileHandle(forReadingAtPath: eventsPath) else { return }
        defer { try? fh.close() }
        let end = (try? fh.seekToEnd()) ?? 0
        if end < save.offset { save.offset = 0 }
        if end == save.offset { return }
        try? fh.seek(toOffset: save.offset)
        guard let data = try? fh.readToEnd(), let lastNL = data.lastIndex(of: 10) else { return }
        let chunk = data[data.startIndex...lastNL]
        save.offset += UInt64(chunk.count)
        dirty = true
        for line in chunk.split(separator: 10) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let t = obj["t"] as? Double, let k = obj["k"] as? String else { continue }
            let live = now - t < 15
            if k == "ask" {
                if live { onAsk?() }
                continue
            }
            if live { onActivity?() }
            if k == "done" && live { onDone?() }
            feed(kind: k, at: t, live: live)
        }
    }

    func feed(kind: String, at t: Double, live: Bool) {
        guard !pet.dead, let food = FOOD[kind] else { return }
        if !isEgg && t - pet.lastFood > DEATH_HOURS * 3600 {
            die(at: pet.lastFood + DEATH_HOURS * 3600)
            return
        }
        var p = pet
        p.counts[kind, default: 0] += 1
        let hour = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: t))
        if hour < 6 { p.night += 1 }
        let day = dayKey(t)
        if p.fedDays.last != day { p.fedDays.append(day); p.fedDays = Array(p.fedDays.suffix(400)) }
        p.totalPoints += food.pts
        if p.hatchedAt == nil {
            p.eggPoints += food.pts
        } else {
            p.full = min(100, full(at: t) + food.pts)
            p.fullAt = t
        }
        p.lastFood = max(p.lastFood, t)
        p.notifiedHungry = false
        p.notifiedDying = false
        pet = p
        if live { onFood?(food.emoji, food.pts) }
    }

    func die(at t: Double) {
        var p = pet
        p.dead = true
        p.diedAt = t
        pet = p
        let days = Int(((t - (p.hatchedAt ?? t)) / 86400).rounded(.down)) + 1
        save.graves.append(Grave(name: p.name, species: p.species, form: p.form, days: days, diedAt: t))
        dirty = true
        notifyTG(L("🪦 \(p.name) starved to death after \(days) days. Bury them and start over with a new egg.",
                   "🪦 \(p.name) умер от голода. Прожил дней: \(days). Похорони и начни заново с яйца."))
    }

    func newEgg(now: Double) {
        pet = Pet.newEgg(now: now)
    }

    /// Once-a-second logic: hatching, evolution, death, alerts.
    func tick(now: Double) {
        if pet.dead { return }
        if isEgg {
            if pet.eggPoints >= HATCH_POINTS {
                var p = pet
                p.hatchedAt = now
                p.full = 80
                p.fullAt = now
                p.lastFood = now
                pet = p
            }
            return
        }
        if now - pet.lastFood > DEATH_HOURS * 3600 {
            die(at: pet.lastFood + DEATH_HOURS * 3600)
            return
        }
        if pet.form == nil, let h = pet.hatchedAt, now - h >= EVOLVE_DAYS * 86400 {
            var p = pet
            p.form = pickForm(p)
            pet = p
        }
        let left = DEATH_HOURS * 3600 - (now - pet.lastFood)
        if full(at: now) <= 0 && !pet.notifiedHungry {
            var p = pet; p.notifiedHungry = true; pet = p
            notifyTG(L("🥺 \(pet.name) is starving. Do some work in Claude Code or they die in \(Int(left / 3600)) h.",
                       "🥺 \(pet.name) голодает. Открой Claude и поработай хоть немного — иначе через \(Int(left / 3600)) ч он умрёт."))
        }
        if left < 6 * 3600 && !pet.notifiedDying {
            var p = pet; p.notifiedDying = true; pet = p
            notifyTG(L("🚨 Less than 6 hours left for \(pet.name)! One prompt in Claude Code saves them.",
                       "🚨 \(pet.name) осталось меньше 6 часов! Один промпт в Claude — и он спасён."))
        }
    }

    func pickForm(_ p: Pet) -> String {
        let c = p.counts
        let score: [String: Double] = [
            "hacker": Double(c["bash"] ?? 0),
            "builder": Double(c["edit"] ?? 0) + 0.1,
            "explorer": Double(c["web"] ?? 0) * 2,
            "queen": Double(c["agent"] ?? 0) * 6,
            "owl": Double(p.night) * 1.5,
        ]
        return score.max { $0.value < $1.value }!.key
    }

    var streak: Int {
        let set = Set(pet.fedDays)
        var t = Date().timeIntervalSince1970
        if !set.contains(dayKey(t)) { t -= 86400 }
        var n = 0
        while set.contains(dayKey(t)) { n += 1; t -= 86400 }
        return n
    }

    func notifyTG(_ text: String) {
        guard save.tg, FileManager.default.fileExists(atPath: tgScript) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [tgScript, text]
        try? p.run()
    }
}

// MARK: - View

struct Drop { var emoji: String; var x: CGFloat; var y: CGFloat; var vy: CGFloat; var pts: Double }
struct Particle { var text: String; var x: CGFloat; var y: CGFloat; var vy: CGFloat; var vx: CGFloat; var life: Double; var size: CGFloat; var color: NSColor }

let W: CGFloat = 200, H: CGFloat = 232, CELL: CGFloat = 6
let SPRITE_X = (W - 16 * CELL) / 2, SPRITE_Y: CGFloat = H - 4 - 16 * CELL   // top of the 16×16 canvas; feet at the window's bottom edge

final class PetView: NSView {
    let world: World
    var t0 = Date().timeIntervalSince1970
    var drops: [Drop] = []
    var pending: [(String, Double)] = []
    var lastRelease = 0.0
    var particles: [Particle] = []
    var mouthUntil = 0.0, squashUntil = 0.0, nextBlink = 2.0, blinkUntil = 0.0
    var wobbleUntil = 0.0, nextWobble = 3.0
    var dragStart: NSPoint?, winStart: NSPoint?, dragged = false
    var walking = false, lean: CGFloat = 0, air: CGFloat = 0, held = false
    var hovering = false, barUntil = 0.0
    var searching = false, celebrateUntil = 0.0
    var onPick: (() -> Void)?
    var onDrop: (() -> Void)?
    var menuProvider: (() -> NSMenu)?
    var onDoubleClick: (() -> Void)?

    init(world: World) {
        self.world = world
        super.init(frame: NSRect(x: 0, y: 0, width: W, height: H))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var now: Double { Date().timeIntervalSince1970 }
    var t: Double { now - t0 }


    func enqueue(_ emoji: String, _ pts: Double) {
        if pending.count < 12 { pending.append((emoji, pts)) }
    }

    var mouthY: CGFloat {
        let sp = Sprite(world.species.rows)
        return SPRITE_Y + CGFloat(sp.mouthRow + 2) * CELL + bob
    }

    var mood: String {
        let w = world
        if w.pet.dead { return "dead" }
        if w.isEgg { return "egg" }
        let f = w.full(at: now)
        if f <= 0 { return "starving" }
        if f < 30 { return "hungry" }
        if !searching && t > celebrateUntil && now - w.pet.lastFood > SLEEP_IDLE && drops.isEmpty && pending.isEmpty { return "sleep" }
        return "happy"
    }

    var bob: CGFloat {
        switch mood {
        case "dead": return 0
        case "starving": return 3
        case "sleep": return CGFloat(sin(t * 1.2)) * 1
        default:
            if held { return 0 }
            if walking { return -abs(CGFloat(sin(t * 11))) * 5 }
            return CGFloat(sin(t * 2.4)) * (world.species.floats ? 5 : 2)
        }
    }

    // animation, ~30 fps
    func step(dt: Double) {
        let m = mood
        if t > nextBlink { blinkUntil = t + 0.14; nextBlink = t + Double.random(in: 2.5...5.5) }
        if m == "egg" && t > nextWobble { wobbleUntil = t + 0.6; nextWobble = t + Double.random(in: 2...5) }
        if !pending.isEmpty && t - lastRelease > 0.22 {
            let (e, p) = pending.removeFirst()
            drops.append(Drop(emoji: e, x: W / 2 + CGFloat.random(in: -26...26), y: -24, vy: 40, pts: p))
            lastRelease = t
        }
        let target = mouthY - 14
        for i in drops.indices {
            drops[i].vy += 520 * CGFloat(dt)
            drops[i].y += drops[i].vy * CGFloat(dt)
            drops[i].x += (W / 2 - 10 - drops[i].x) * CGFloat(dt) * 2.2
        }
        for d in drops where d.y >= target {
            mouthUntil = t + 0.35
            barUntil = t + 4
            squashUntil = t + 0.18
        }
        drops.removeAll { $0.y >= target }
        for i in particles.indices {
            particles[i].y += particles[i].vy * CGFloat(dt)
            particles[i].x += particles[i].vx * CGFloat(dt)
            particles[i].life -= dt
        }
        particles.removeAll { $0.life <= 0 }
        if m == "sleep" && Int(t * 10) % 14 == 0 && particles.filter({ $0.text == "💤" }).count < 2 {
            particles.append(Particle(text: "💤", x: W / 2 + 30, y: SPRITE_Y + 20, vy: -14, vx: 8, life: 2.4, size: 13, color: hex(0x6b6390)))
        }
        needsDisplay = true
    }

    func pet() {
        switch mood {
        case "dead", "starving", "hungry": break
        case "egg": wobbleUntil = t + 0.6
        default:
            for i in 0..<4 {
                particles.append(Particle(text: "❤️", x: W / 2 + CGFloat(i * 14 - 24), y: SPRITE_Y + 30, vy: -30 - CGFloat(i * 6), vx: CGFloat.random(in: -8...8), life: 1.3, size: 13, color: .red))
            }
        }
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        let scale = CGFloat(world.save.scale)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        let m = mood
        let w = world

        // shadow
        hex(0x000000, 0.18).setFill()
        let shW: CGFloat = held ? 0 : max(16, (m == "starving" ? 84 : 70 - abs(bob) * 2) - air * 0.4)
        if shW > 0 { NSBezierPath(ovalIn: NSRect(x: (W - shW) / 2, y: SPRITE_Y + 16 * CELL - 6 + min(air, 4), width: shW, height: 8)).fill() }

        // sprite
        var rows: [String]
        var pal: [Character: NSColor]
        let sp = w.species
        if m == "dead" {
            rows = TOMB_ROWS
            pal = palette(body: 0xaeb0bb, accent: 0x6fbf5a, light: nil, outline: 0x5d5f6b, mouth: nil)
        } else if m == "egg" {
            rows = EGG_ROWS
            pal = palette(body: 0xfbf4e4, accent: sp.colors[w.pet.colorIndex % sp.colors.count], light: nil, outline: 0x8a7f6a, mouth: nil)
        } else {
            rows = sp.rows
            pal = palette(body: sp.colors[w.pet.colorIndex % sp.colors.count], accent: sp.accent, light: sp.light, outline: sp.outline, mouth: sp.mouth)
        }
        let sprite = Sprite(rows)
        let grey = m == "starving"
        let party = t < celebrateUntil && m != "dead" && m != "egg"
        let closed = party || m == "sleep" || t < blinkUntil || m == "starving" && Int(t) % 4 == 0
        let open = party || t < mouthUntil
        let squash: CGFloat = t < squashUntil ? 0.9 : (m == "starving" ? 0.86 : 1)
        var wobble: CGFloat = 0
        if t < wobbleUntil { wobble = CGFloat(sin((wobbleUntil - t) * 30)) * 0.08 }
        if walking { wobble += lean * 0.07 + CGFloat(sin(t * 11)) * 0.05 }
        if held { wobble = CGFloat(sin(t * 5)) * 0.12 }

        ctx.saveGState()
        let baseX = SPRITE_X + 8 * CELL, baseY = SPRITE_Y + 16 * CELL
        ctx.translateBy(x: baseX, y: baseY + bob)
        ctx.rotate(by: wobble)
        ctx.scaleBy(x: 2 - squash, y: squash)
        ctx.translateBy(x: -8 * CELL, y: -16 * CELL)

        let maxEyeRow = sprite.eyes.map { $0.0 }.max() ?? 0
        for (r, row) in sprite.grid.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." {
                var key = ch
                if (ch == "e" || ch == "w") && party { key = r == maxEyeRow ? "b" : "e" }
                else if (ch == "e" || ch == "w") && closed { key = r == maxEyeRow ? "o" : "b" }
                guard var col = pal[key] else { continue }
                if grey { col = (col.blended(withFraction: 0.55, of: hex(0x8a8a8a)) ?? col).withAlphaComponent(col.alphaComponent) }
                col.setFill()
                NSRect(x: CGFloat(c) * CELL - 0.3, y: CGFloat(r + 2) * CELL - 0.3, width: CELL + 0.6, height: CELL + 0.6).fill(using: .sourceOver)
                if ch == "m" && open && r + 1 < sprite.grid.count {
                    hex(0x5b2433).setFill()
                    NSRect(x: CGFloat(c) * CELL, y: CGFloat(r + 3) * CELL, width: CELL, height: CELL).fill()
                }
            }
        }
        if party {
            // happy ^^ eyes: legs at the outer edges of each eye
            pal["e"]!.setFill()
            for side in [sprite.eyes.filter { $0.1 < 8 }, sprite.eyes.filter { $0.1 >= 8 }] where !side.isEmpty {
                let r = maxEyeRow, c0 = side.map { $0.1 }.min()! - 1, c1 = side.map { $0.1 }.max()! + 1
                for c in [c0, c1] { NSRect(x: CGFloat(c) * CELL, y: CGFloat(r + 2) * CELL, width: CELL, height: CELL).fill() }
            }
        }
        if let form = w.pet.form, m != "dead", m != "egg" { drawForm(form, sprite, pal) }
        ctx.restoreGState()

        if w.pet.form == "queen" && m != "dead" { drawMinions(pal) }

        // food
        for d in drops {
            (d.emoji as NSString).draw(at: NSPoint(x: d.x, y: d.y), withAttributes: [.font: NSFont.systemFont(ofSize: 20)])
        }
        // particles
        for p in particles {
            let a = CGFloat(min(1, p.life * 1.5))
            (p.text as NSString).draw(at: NSPoint(x: p.x, y: p.y), withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: p.size), .foregroundColor: p.color.withAlphaComponent(a)])
        }
        // fullness bar and label
        drawBar(m)
        if searching && m != "dead" && m != "egg" { drawMagnifier() }
        ctx.restoreGState()
    }

    func drawForm(_ form: String, _ sp: Sprite, _ pal: [Character: NSColor]) {
        func px(_ r: Int, _ c: Int, _ col: NSColor) {
            col.setFill()
            NSRect(x: CGFloat(c) * CELL, y: CGFloat(r + 2) * CELL, width: CELL, height: CELL).fill()
        }
        let top = sp.top
        let eyeRows = sp.eyes.map { $0.0 }, eyeCols = sp.eyes.map { $0.1 }
        let er = eyeRows.min() ?? 7, c0 = (eyeCols.min() ?? 4) - 1, c1 = (eyeCols.max() ?? 11) + 1
        switch form {
        case "hacker":
            for c in c0...c1 { px(er, c, hex(0x111318)) }
            for c in c0...c1 where c != 7 && c != 8 { px(er + 1, c, hex(0x111318)) }
            px(er, c0 + 1, hex(0x59f08a))
            px(er, c1 - 2, hex(0x59f08a))
            ("</>" as NSString).draw(at: NSPoint(x: 15.5 * CELL, y: CGFloat(top + 1) * CELL),
                                    withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold), .foregroundColor: hex(0x2fbf5f)])
        case "builder":
            for c in 5...10 { px(top - 2, c, hex(0xffc531)) }
            for c in 4...11 { px(top - 1, c, hex(0xffc531)) }
            for c in 2...13 { px(top, c, hex(0xd9a21f)) }
            px(top - 2, 7, hex(0xfff1b0))
        case "explorer":
            for c in 5...10 { px(top - 2, c, hex(0xc8a46a)) }
            for c in 5...10 { px(top - 1, c, hex(0x6b4a2b)) }
            for c in 2...13 { px(top, c, hex(0xb08f55)) }
        case "owl":
            let ring = hex(0x3a2a1a)
            for (r, c) in sp.eyes {
                for dr in -1...1 { for dc in -1...1 where dr != 0 || dc != 0 {
                    let rr = r + dr, cc = c + dc
                    if !sp.eyes.contains(where: { $0 == (rr, cc) }) { px(rr, cc, ring) }
                } }
            }
            px(top - 1, 3, hex(0x8a5a2b)); px(top - 2, 2, hex(0x8a5a2b))
            px(top - 1, 12, hex(0x8a5a2b)); px(top - 2, 13, hex(0x8a5a2b))
        case "queen":
            let gold = hex(0xffd23f)
            for c in 5...10 { px(top - 1, c, gold) }
            for c in [5, 7, 8, 10] { px(top - 2, c, gold) }
            px(top - 1, 7, hex(0xe8394d)); px(top - 1, 8, hex(0xe8394d))
        default: break
        }
    }

    func drawMagnifier() {
        // magnifier in the paw on the walking side; a magnified eye in the glass looks for you
        let dir: CGFloat = lean >= 0 ? 1 : -1
        let sway = CGFloat(sin(t * 3.2)) * 4
        let cx = W / 2 + dir * (50 + sway), cy = SPRITE_Y + 44 + bob + CGFloat(sin(t * 2.1)) * 5
        let r: CGFloat = 19
        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: cx - dir * r * 0.75, y: cy + r * 0.75))
        handle.line(to: NSPoint(x: cx - dir * (r + 16), y: cy + r + 18))
        handle.lineCapStyle = .round
        handle.lineWidth = 9
        hex(0x2b1d14).setStroke()
        handle.stroke()
        handle.lineWidth = 6
        hex(0x9a6234).setStroke()
        handle.stroke()
        let lens = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        hex(0xe8f6ff, 0.92).setFill()
        lens.fill()
        // magnified eye: the pupil darts around
        let look = CGFloat(sin(t * 1.7)) * 4
        hex(0x1d1b2b).setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - 7 + dir * 3 + look, y: cy - 8, width: 14, height: 16)).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - 3 + dir * 3 + look, y: cy - 5, width: 5, height: 5)).fill()
        // rim
        lens.lineWidth = 6
        hex(0x2b1d14).setStroke()
        lens.stroke()
        lens.lineWidth = 3.5
        hex(0xe0b04a).setStroke()
        lens.stroke()
        hex(0xffffff, 0.8).setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - r * 0.62, y: cy - r * 0.68, width: 7, height: 4)).fill()
    }

    func drawMinions(_ pal: [Character: NSColor]) {
        for i in 0..<2 {
            let a = t * 1.3 + Double(i) * .pi
            let x = W / 2 + CGFloat(cos(a)) * 70 - 9
            let y = SPRITE_Y + 60 + CGFloat(sin(a)) * 14
            pal["o"]!.setFill(); NSBezierPath(ovalIn: NSRect(x: x - 1, y: y - 1, width: 20, height: 16)).fill()
            pal["b"]!.setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 18, height: 14)).fill()
            pal["e"]!.setFill()
            NSRect(x: x + 5, y: y + 5, width: 2, height: 3).fill()
            NSRect(x: x + 11, y: y + 5, width: 2, height: 3).fill()
        }
    }

    func drawBar(_ m: String) {
        let w = world
        let top = CGFloat(Sprite(m == "dead" ? TOMB_ROWS : m == "egg" ? EGG_ROWS : w.species.rows).top)
        let y = SPRITE_Y + top * CELL - 14 + bob
        let hungry = !w.isEgg && !w.pet.dead && w.full(at: now) < 30
        guard hovering || t < barUntil || hungry else { return }
        let label: String
        if m == "dead" {
            label = "\(w.pet.name) · RIP"
        } else if m == "egg" {
            let frac = min(1, w.pet.eggPoints / HATCH_POINTS)
            bar(y: y, frac: frac, color: hex(0xc9b38a))
            label = L("egg", "яйцо") + " · \(Int(frac * 100))%"
        } else {
            let f = w.full(at: now)
            let col = f > 60 ? hex(0x5cc46a) : f > 30 ? hex(0xf2b33d) : hex(0xe5534b)
            bar(y: y, frac: f / 100, color: col)
            let day = Int((now - (w.pet.hatchedAt ?? now)) / 86400) + 1
            label = "\(w.pet.name) · " + L("day \(day)", "день \(day)")
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.white]
        let shadow: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: hex(0x000000, 0.55)]
        let s = label as NSString
        let size = s.size(withAttributes: attrs)
        guard hovering else { return }
        let p = NSPoint(x: (W - size.width) / 2, y: y - 15)
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] { s.draw(at: NSPoint(x: p.x + CGFloat(dx), y: p.y + CGFloat(dy)), withAttributes: shadow) }
        s.draw(at: p, withAttributes: attrs)
    }

    func bar(y: CGFloat, frac: Double, color: NSColor) {
        let bw: CGFloat = 72, x = (W - bw) / 2
        hex(0x1d1b2b, 0.75).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: bw, height: 7), xRadius: 3.5, yRadius: 3.5).fill()
        color.setFill()
        let fw = max(0, (bw - 2) * CGFloat(frac))
        if fw > 0 { NSBezierPath(roundedRect: NSRect(x: x + 1, y: y + 1, width: fw, height: 5), xRadius: 2.5, yRadius: 2.5).fill() }
    }

    // MARK: mouse — drag across any screen

    override func mouseDown(with e: NSEvent) {
        dragStart = NSEvent.mouseLocation
        winStart = window?.frame.origin
        dragged = false
        if e.clickCount == 2 { onDoubleClick?() }
    }

    override func mouseDragged(with e: NSEvent) {
        guard let s = dragStart, let o = winStart, let win = window else { return }
        let p = NSEvent.mouseLocation
        if !dragged && abs(p.x - s.x) + abs(p.y - s.y) > 3 { dragged = true; held = true; onPick?() }
        win.setFrameOrigin(NSPoint(x: o.x + p.x - s.x, y: o.y + p.y - s.y))
    }

    override func mouseUp(with e: NSEvent) {
        if dragged {
            held = false
            window?.saveFrame(usingName: "ClawdlingWindow")
            onDrop?()
        } else if e.clickCount == 1 {
            pet()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }

    func land() {
        squashUntil = t + 0.22
    }

    override func rightMouseDown(with e: NSEvent) {
        if let menu = menuProvider?() { NSMenu.popUpContextMenu(menu, with: e, for: self) }
    }
}


// MARK: - Toys (a small window of their own on the screen floor)

final class ToyView: NSView {
    var emoji = "⚽️"
    var angle: CGFloat = 0
    var onKick: (() -> Void)?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ r: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.translateBy(x: bounds.midX, y: bounds.midY)
        ctx.rotate(by: angle)
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: bounds.width * 0.62)]
        let sz = (emoji as NSString).size(withAttributes: a)
        (emoji as NSString).draw(at: NSPoint(x: -sz.width / 2, y: -sz.height / 2), withAttributes: a)
    }
    override func mouseDown(with e: NSEvent) { onKick?() }
}

final class Toy {
    let kind: String          // ball, yarn, butterfly
    let panel: NSPanel
    let view = ToyView()
    var x: CGFloat, y: CGFloat   // center x, height above the floor
    var vx: CGFloat = 0, vy: CGFloat = 0
    var phase = Double.random(in: 0...6)
    let size: CGFloat

    init(kind: String, x: CGFloat, y: CGFloat, scale: CGFloat) {
        self.kind = kind
        self.x = x
        self.y = y
        size = 40 * scale
        view.emoji = ["ball": "⚽️", "yarn": "🧶", "butterfly": "🦋"][kind] ?? "⚽️"
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        view.frame = NSRect(x: 0, y: 0, width: size, height: size)
        panel.contentView = view
        panel.orderFront(nil)
    }

    func kick(dir: CGFloat) {
        if kind == "butterfly" {
            vx = dir * CGFloat.random(in: 140...240)
            phase += 2
        } else {
            vx = dir * CGFloat.random(in: 260...480)
            vy = CGFloat.random(in: 140...360)
        }
    }

    func step(dt: CGFloat, t: Double, floor: CGFloat, minX: CGFloat, maxX: CGFloat) {
        if kind == "butterfly" {
            // flutters: wanders in x, sine in height
            vx += CGFloat(sin(t * 0.9 + phase)) * 160 * dt
            vx *= pow(0.5, dt)
            x += vx * dt
            y = 70 + CGFloat(sin(t * 1.7 + phase)) * 40 + CGFloat(sin(t * 9)) * 4
            view.angle = CGFloat(sin(t * 9)) * 0.15
        } else {
            vy -= 1300 * dt
            y += vy * dt
            if y <= 0 {
                y = 0
                vy = abs(vy) > 90 ? -vy * 0.45 : 0
            }
            vx *= pow(y > 0 ? 0.85 : 0.35, dt)
            if abs(vx) < 4 { vx = 0 }
            x += vx * dt
            view.angle -= vx * dt / (size * 0.45)
        }
        if x < minX + size / 2 { x = minX + size / 2; vx = abs(vx) * 0.6 }
        if x > maxX - size / 2 { x = maxX - size / 2; vx = -abs(vx) * 0.6 }
        panel.setFrameOrigin(NSPoint(x: x - size / 2, y: floor + y))
        view.needsDisplay = true
    }

    func close() { panel.orderOut(nil) }
}


// MARK: - Party: poppers and confetti

final class ConfettiView: NSView {
    struct Piece { var x, y, vx, vy, rot, vr, w, h: CGFloat; var color: NSColor }
    var pieces: [Piece] = []
    var age = 0.0
    override var isFlipped: Bool { false }

    func burst(from x: CGFloat, _ y: CGFloat, dir: CGFloat) {
        let colors = [0xff5d73, 0xffd23f, 0x4fd1c5, 0x7c83ff, 0x5cc46a, 0xff9a2e, 0xffffff]
        for _ in 0..<70 {
            let a = CGFloat.random(in: 0.25...1.25) // angle above the horizon
            let sp = CGFloat.random(in: 260...620)
            pieces.append(Piece(x: x, y: y, vx: dir * cos(a) * sp, vy: sin(a) * sp,
                                rot: .random(in: 0...6), vr: .random(in: -12...12),
                                w: .random(in: 5...9), h: .random(in: 3...6), color: hex(colors.randomElement()!)))
        }
    }

    func step(_ dt: CGFloat) {
        age += Double(dt)
        for i in pieces.indices {
            pieces[i].vy -= 700 * dt
            pieces[i].vx *= pow(0.4, dt)
            pieces[i].vy = max(pieces[i].vy, -160 + CGFloat(sin(Double(pieces[i].rot))) * 40) // flutter down
            pieces[i].x += pieces[i].vx * dt + CGFloat(sin(age * 6 + Double(i))) * 0.6
            pieces[i].y += pieces[i].vy * dt
            pieces[i].rot += pieces[i].vr * dt
        }
        needsDisplay = true
    }

    override func draw(_ r: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let fade = CGFloat(max(0, min(1, (4.0 - age) / 1.0)))
        for p in pieces where p.y > -10 {
            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: p.rot)
            ctx.scaleBy(x: 1, y: abs(cos(p.rot * 1.7)) * 0.8 + 0.2)   // tumble
            p.color.withAlphaComponent(fade).setFill()
            NSRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h).fill()
            ctx.restoreGState()
        }
        // poppers at both sides for the first 1.5 s
        if age < 1.5 {
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 34)]
            let k = CGFloat(min(1, age * 6)), y: CGFloat = 40
            ctx.saveGState()
            ctx.setAlpha(CGFloat(min(1, (1.5 - age) * 3)))
            ("🎉" as NSString).draw(at: NSPoint(x: bounds.midX + 70 * k, y: y), withAttributes: a)
            ctx.translateBy(x: bounds.midX - 70 * k, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            ("🎉" as NSString).draw(at: NSPoint(x: 0, y: y), withAttributes: a)
            ctx.restoreGState()
        }
    }
}

final class Confetti {
    let panel: NSPanel
    let view = ConfettiView()

    init(centerX: CGFloat, floor: CGFloat, petTop: CGFloat) {
        let w: CGFloat = 900, h: CGFloat = 520
        panel = NSPanel(contentRect: NSRect(x: centerX - w / 2, y: floor, width: w, height: h),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        view.frame = NSRect(x: 0, y: 0, width: w, height: h)
        panel.contentView = view
        view.burst(from: w / 2 - 60, 60, dir: -1)
        view.burst(from: w / 2 + 60, 60, dir: 1)
        panel.orderFront(nil)
    }

    var isDone: Bool { view.age > 4.2 }
    func step(_ dt: CGFloat) { view.step(dt) }
    func close() { panel.orderOut(nil) }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate {
    let world = World()
    var panel: NSPanel!
    var view: PetView!
    var lastStep = Date().timeIntervalSince1970

    // walking along the screen floor
    var act = "fall"            // idle, walk, play, fall
    var actUntil = 0.0
    var targetX: CGFloat = 0    // target for the pet's center (screen coordinates)
    var air: CGFloat = 0, vy: CGFloat = 0
    var toy: Toy?
    var playUntil = 0.0
    var lastPlay = ProcessInfo.processInfo.environment["CLAWDLING_PLAY"] != nil ? 0 : Date().timeIntervalSince1970 - 30
    var lastKick = 0.0
    var confetti: [Confetti] = []
    var searchUntil = 0.0
    var nextSearchHop = 0.0
    var roam: Bool { world.save.roam ?? true }

    func applicationDidFinishLaunching(_ n: Notification) {
        view = PetView(world: world)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.contentView = view
        applyScale()
        if !panel.setFrameUsingName("ClawdlingWindow"), let s = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: s.maxX - panel.frame.width - 40, y: s.minY + 30))
        }
        panel.orderFrontRegardless()
        air = 400   // drops to the floor on launch

        world.onFood = { [weak self] e, p in self?.view.enqueue(e, p) }
        world.onAsk = { [weak self] in self?.startSearch() }
        world.onActivity = { [weak self] in self?.stopSearch() }
        world.onDone = { [weak self] in self?.celebrate() }
        view.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
        view.onDoubleClick = { [weak self] in self?.showStats() }
        view.onPick = { [weak self] in self?.act = "fall" }
        view.onDrop = { [weak self] in
            guard let self else { return }
            self.air = max(0, self.panel.frame.origin.y - self.floorInfo().1)
            self.vy = 0
            self.act = "fall"
        }

        let now = Date().timeIntervalSince1970
        world.pollEvents(now: now)
        world.tick(now: now)
        world.persist()

        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = Date().timeIntervalSince1970
            let dt = min(0.1, t - self.lastStep)
            self.roamStep(dt: CGFloat(dt), now: t)
            self.view.step(dt: dt)
            self.lastStep = t
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = Date().timeIntervalSince1970
            self.world.pollEvents(now: t)
            self.world.tick(now: t)
            self.world.persist()
        }
    }


    // MARK: walking

    func floorInfo() -> (NSRect, CGFloat) {
        let c = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let scr = NSScreen.screens.first { $0.frame.contains(c) } ?? NSScreen.screens.min {
            hypot($0.frame.midX - c.x, $0.frame.midY - c.y) < hypot($1.frame.midX - c.x, $1.frame.midY - c.y)
        } ?? NSScreen.main!
        return (scr.visibleFrame, scr.visibleFrame.minY)
    }

    func roamStep(dt: CGFloat, now: Double) {
        guard roam, !view.held else { view.walking = false; return }
        let s = CGFloat(world.save.scale)
        let (vis, floor) = floorInfo()
        let half = W / 2 * s
        let minC = vis.minX + 40 * s, maxC = vis.maxX - 40 * s   // bounds for the pet's center
        var cx = panel.frame.origin.x + half

        // gravity
        if air > 0 || vy > 0 {
            vy -= 1500 * dt
            air += vy * dt
            if air <= 0 {
                air = 0
                if vy < -350 { view.land() }
                vy = 0
                if act == "fall" { act = "idle"; actUntil = now + 1.5 }
            }
        }
        view.air = air

        let m = view.mood
        let busy = !view.pending.isEmpty || !view.drops.isEmpty
        let canMove = (m == "happy" || m == "hungry") && !busy && act != "fall"
        if toy != nil && (m != "happy" || now > playUntil || view.searching) { endPlay() }
        if view.searching && now > searchUntil { stopSearch() }
        for c in confetti { c.step(dt) }
        confetti.removeAll { if $0.isDone { $0.close(); return true }; return false }
        let partying = view.t < view.celebrateUntil
        if partying && air == 0 && vy == 0 && m != "dead" && m != "egg" { vy = 430 }
        view.walking = false

        if view.searching && m != "dead" && m != "egg" && m != "starving" && act != "fall" {
            // looking for you: runs to the cursor; if it is on another screen, paces this one
            let mouse = NSEvent.mouseLocation
            let mine = mouse.x >= vis.minX && mouse.x <= vis.maxX
            if mine {
                targetX = min(max(mouse.x, minC), maxC)
            } else if abs(targetX - cx) < 5 || targetX < minC || targetX > maxC {
                targetX = targetX < cx ? maxC : minC
            }
            if walk(&cx, to: targetX, speed: 120 * s, dt: dt) || abs(targetX - cx) < 30 * s {
                view.lean = mouse.x >= cx ? 1 : -1
                if mine && air == 0 && now > nextSearchHop { vy = 300; nextSearchHop = now + 1.1 }
            }
        } else if canMove && !partying {
            switch act {
            case "idle":
                if now > actUntil { decide(now: now, cx: cx, minC: minC, maxC: maxC, s: s) }
            case "walk":
                let speed: CGFloat = (m == "hungry" ? 28 : 55) * s
                if walk(&cx, to: targetX, speed: speed, dt: dt) {
                    act = "idle"
                    actUntil = now + Double.random(in: 2...7)
                }
            case "play":
                if let toy {
                    let d = toy.x - cx
                    if abs(d) > 22 * s { _ = walk(&cx, to: toy.x, speed: 95 * s, dt: dt) }
                    if abs(d) < 34 * s && now - lastKick > 0.6 {
                        if toy.kind == "butterfly" {
                            if air == 0 { vy = 520; toy.kick(dir: Bool.random() ? 1 : -1); lastKick = now }
                        } else if toy.y < 30 {
                            toy.kick(dir: d >= 0 ? 1 : -1)
                            if air == 0 && Bool.random() { vy = 260 }
                            lastKick = now
                        }
                    }
                } else {
                    act = "idle"
                }
            default:
                act = "idle"
            }
        }
        cx = min(max(cx, minC), maxC)
        toy?.step(dt: dt, t: view.t, floor: floor, minX: vis.minX, maxX: vis.maxX)
        panel.setFrameOrigin(NSPoint(x: cx - half, y: floor + air - 2 * s))
    }

    /// Walks toward the target; true once there.
    func walk(_ cx: inout CGFloat, to x: CGFloat, speed: CGFloat, dt: CGFloat) -> Bool {
        let d = x - cx
        if abs(d) < 3 { return true }
        cx += d > 0 ? min(d, speed * dt) : -min(-d, speed * dt)
        view.walking = true
        view.lean = d > 0 ? 1 : -1
        return false
    }

    func decide(now: Double, cx: CGFloat, minC: CGFloat, maxC: CGFloat, s: CGFloat) {
        let bored = view.mood == "happy" && now - lastPlay > 45
        let r = Double.random(in: 0...1)
        if bored && r < 0.4 {
            startPlay(now: now, cx: cx, minC: minC, maxC: maxC, s: s)
        } else if r < 0.75 {
            act = "walk"
            let span = CGFloat.random(in: 120...520) * s * (Bool.random() ? 1 : -1)
            targetX = min(max(cx + span, minC), maxC)
        } else {
            act = "idle"
            actUntil = now + Double.random(in: 3...8)
        }
    }

    func startPlay(now: Double, cx: CGFloat, minC: CGFloat, maxC: CGFloat, s: CGFloat) {
        let kind = ["ball", "yarn", "butterfly"].randomElement()!
        let x = min(max(cx + CGFloat.random(in: 140...260) * s * (Bool.random() ? 1 : -1), minC), maxC)
        let toy = Toy(kind: kind, x: x, y: kind == "butterfly" ? 80 : 260, scale: s)
        toy.view.onKick = { [weak toy] in toy?.kick(dir: Bool.random() ? 1 : -1) }
        self.toy = toy
        act = "play"
        playUntil = now + Double.random(in: 20...40)
    }

    func startSearch() {
        guard !world.pet.dead else { return }
        view.searching = true
        searchUntil = Date().timeIntervalSince1970 + 600
        targetX = panel.frame.midX
    }

    func stopSearch() {
        view.searching = false
    }

    func celebrate() {
        stopSearch()
        guard !world.pet.dead, !world.isEgg else { return }
        view.celebrateUntil = view.t + 2.6
        let (_, floor) = floorInfo()
        if confetti.count < 3 {
            confetti.append(Confetti(centerX: panel.frame.midX, floor: floor, petTop: panel.frame.maxY))
        }
    }

    func endPlay() {
        toy?.close()
        toy = nil
        lastPlay = Date().timeIntervalSince1970
        if act == "play" { act = "idle"; actUntil = lastPlay + 3 }
    }

    func applyScale() {
        let s = CGFloat(world.save.scale)
        let o = panel.frame.origin
        panel.setFrame(NSRect(x: o.x, y: o.y, width: W * s, height: H * s), display: true)
        view.frame = NSRect(x: 0, y: 0, width: W * s, height: H * s)
    }

    func makeMenu() -> NSMenu {
        let m = NSMenu()
        let p = world.pet
        let title: String
        if p.dead { title = "🪦 \(p.name)" }
        else if world.isEgg { title = L("🥚 egg", "🥚 яйцо") }
        else { title = "\(p.name) — \(world.species.name)" + (p.form.map { " · \(FORM_NAME[$0]!)" } ?? "") }
        let head = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        head.isEnabled = false
        m.addItem(head)
        m.addItem(.separator())
        m.addItem(item(L("Stats…", "Статы…"), #selector(statsAction)))
        m.addItem(item(L("Graveyard", "Кладбище") + " (\(world.save.graves.count))…", #selector(gravesAction)))
        if p.dead { m.addItem(item(L("Bury and take a new egg 🥚", "Похоронить и взять новое яйцо 🥚"), #selector(reviveAction))) }
        let size = NSMenuItem(title: L("Size", "Размер"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (name, v) in [(L("Small", "Маленький"), 0.75), (L("Normal", "Обычный"), 1.0), (L("Large", "Большой"), 1.4)] {
            let i = item(name, #selector(scaleAction(_:)))
            i.representedObject = v
            i.state = world.save.scale == v ? .on : .off
            sub.addItem(i)
        }
        size.submenu = sub
        m.addItem(size)
        let walkItem = item(L("Walk around the screen", "Гулять по экрану"), #selector(roamAction))
        walkItem.state = roam ? .on : .off
        m.addItem(walkItem)
        if roam && toy == nil && !world.isEgg && !p.dead {
            m.addItem(item(L("Give a toy 🧶", "Дать игрушку 🧶"), #selector(toyAction)))
        }
        let tg = item(L("Telegram alerts", "Пинги в Telegram"), #selector(tgAction))
        tg.state = world.save.tg ? .on : .off
        m.addItem(tg)
        m.addItem(.separator())
        m.addItem(item(L("Quit", "Выйти"), #selector(quitAction)))
        return m
    }

    func item(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    @objc func statsAction() { showStats() }

    func showStats() {
        let p = world.pet
        let now = Date().timeIntervalSince1970
        let c = p.counts
        let ago = Int((now - p.lastFood) / 3600)
        var lines: [String] = []
        if world.isEgg {
            lines.append(L("Egg: \(Int(p.eggPoints)) of \(Int(HATCH_POINTS)) food to hatch", "Яйцо: \(Int(p.eggPoints)) из \(Int(HATCH_POINTS)) еды до вылупления"))
        } else {
            let day = Int((now - (p.hatchedAt ?? now)) / 86400) + 1
            lines.append(L("Species: ", "Вид: ") + world.species.name + (p.form.map { L(", form: ", ", форма: ") + FORM_NAME[$0]! } ?? L(", evolves on day 7", ", эволюция на 7-й день")))
            lines.append(L("Age: day \(day)", "Возраст: день \(day)"))
            lines.append(L("Fullness: ", "Сытость: ") + "\(Int(world.full(at: now)))%")
            if !p.dead { lines.append(L("Starves in: \(max(0, Int(DEATH_HOURS) - ago)) h", "До голодной смерти: \(max(0, Int(DEATH_HOURS) - ago)) ч")) }
        }
        lines.append(L("Last meal: ", "Последняя еда: ") + (ago == 0 ? L("just now", "только что") : L("\(ago) h ago", "\(ago) ч назад")))
        lines.append(L("Streak: \(world.streak) days in a row", "Стрик: \(world.streak) дн. подряд"))
        lines.append("")
        lines.append(L("🍙 prompts", "🍙 промпты") + " \(c["prompt"] ?? 0)   " + L("🍪 finished tasks", "🍪 задачи") + " \(c["done"] ?? 0)")
        lines.append(L("🍎 edits", "🍎 правки") + " \(c["edit"] ?? 0)   " + L("☕️ commands", "☕️ команды") + " \(c["bash"] ?? 0)")
        lines.append(L("🐟 web", "🐟 веб") + " \(c["web"] ?? 0)   " + L("🎂 agents", "🎂 агенты") + " \(c["agent"] ?? 0)   " + L("🍬 other", "🍬 прочее") + " \(c["other"] ?? 0)")
        lines.append(L("Midnight snacks: ", "Ночных перекусов: ") + "\(p.night)")
        alert(p.dead ? "🪦 \(p.name)" : p.name, lines.joined(separator: "\n"))
    }

    @objc func gravesAction() {
        let g = world.save.graves
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        let text = g.isEmpty ? L("Nobody has died yet. Keep it up.", "Пока никто не умер. Так держать.") : g.reversed().map { gr in
            let sp = SPECIES.first(where: { $0.id == gr.species })?.name ?? gr.species
            let form = gr.form.map { " (\(FORM_NAME[$0] ?? $0))" } ?? ""
            return "🪦 \(gr.name), \(sp)\(form) — \(gr.days) " + L("days", "дн.") + ", \(f.string(from: Date(timeIntervalSince1970: gr.diedAt)))"
        }.joined(separator: "\n")
        alert(L("Graveyard", "Кладбище"), text)
    }

    @objc func reviveAction() {
        world.newEgg(now: Date().timeIntervalSince1970)
        world.persist()
    }

    @objc func scaleAction(_ s: NSMenuItem) {
        world.save.scale = s.representedObject as? Double ?? 1
        world.dirty = true
        world.persist()
        applyScale()
    }

    @objc func tgAction() {
        world.save.tg.toggle()
        world.dirty = true
        world.persist()
    }

    @objc func roamAction() {
        world.save.roam = !roam
        world.dirty = true
        world.persist()
        if !roam { endPlay() } else { act = "fall"; air = max(0, panel.frame.origin.y - floorInfo().1) }
    }

    @objc func toyAction() {
        let s = CGFloat(world.save.scale)
        let vis = floorInfo().0
        endPlay()
        startPlay(now: Date().timeIntervalSince1970, cx: panel.frame.midX, minC: vis.minX + 40 * s, maxC: vis.maxX - 40 * s, s: s)
    }

    @objc func quitAction() { NSApp.terminate(nil) }
}

// Debug: CLAWDLING_FRAMES=/dir renders a looping strip of animated pets (frame_000.png …) for the README GIF.
if let dir = ProcessInfo.processInfo.environment["CLAWDLING_FRAMES"] {
    // (species, form, what it does)
    let cast: [(String, String?, String)] = [
        ("slime", nil, "walk"), ("ghost", nil, "idle"), ("cat", nil, "search"), ("fox", nil, "party"),
        ("frog", "hacker", "walk"), ("crab", "queen", "idle"), ("chick", "builder", "party")]
    let world = World()
    let fps = 15.0, frames = 45
    let views: [PetView] = cast.enumerated().map { i, c in
        let v = PetView(world: world)
        v.nextBlink = 1e9
        v.searching = c.2 == "search"
        v.walking = c.2 == "walk"
        v.lean = i % 2 == 0 ? 1 : -1
        if c.2 == "party" { v.celebrateUntil = 1e9 }
        return v
    }
    let cw = W, ch = H + 30
    for f in 0..<frames {
        let ft = Double(f) / fps
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(cw) * cast.count, pixelsHigh: Int(ch),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let g = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = g
        hex(0x2b3040).setFill()
        NSRect(x: 0, y: 0, width: cw * CGFloat(cast.count), height: ch).fill()
        hex(0x3a4156).setFill()
        NSRect(x: 0, y: 0, width: cw * CGFloat(cast.count), height: 30).fill()
        for (i, c) in cast.enumerated() {
            let now = Date().timeIntervalSince1970
            var p = Pet.newEgg(now: now)
            p.species = c.0
            p.colorIndex = 0
            p.form = c.1
            p.hatchedAt = now - 3 * 86400
            p.full = 90
            world.save.pet = p
            let v = views[i]
            v.t0 = Date().timeIntervalSince1970 - ft - Double(i) * 0.37
            if f % 30 == 12 + i % 5 { v.blinkUntil = v.t + 0.12 }
            let jump: CGFloat = c.2 == "party" ? abs(CGFloat(sin(ft * .pi * 2 / 1.5))) * 26 : 0
            g.cgContext.saveGState()
            g.cgContext.translateBy(x: CGFloat(i) * cw, y: ch + 2 + jump)
            g.cgContext.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: g.cgContext, flipped: true)
            v.air = jump
            v.draw(v.bounds)
            g.cgContext.restoreGState()
            NSGraphicsContext.current = g
            if c.2 == "party" {
                // a few confetti specks around the party animals
                for k in 0..<14 {
                    let seed = Double(k * 37 + i * 11)
                    let x = CGFloat(i) * cw + cw / 2 + CGFloat(sin(seed) * 80)
                    let y = ch - CGFloat((ft * 60 + seed * 13).truncatingRemainder(dividingBy: Double(ch)))
                    hex([0xff5d73, 0xffd23f, 0x4fd1c5, 0x7c83ff, 0x5cc46a][k % 5]).setFill()
                    NSRect(x: x, y: y, width: 6, height: 4).fill()
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let path = String(format: "%@/frame_%03d.png", dir, f)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
    exit(0)
}

// Debug: CLAWDLING_SHEET=/path.png renders every species × form into one sheet and exits.
if let sheetPath = ProcessInfo.processInfo.environment["CLAWDLING_SHEET"] {
    let cols = SPECIES.count, moods: [(String, String?)] = [
        ("egg", nil), ("happy", nil), ("happy", "hacker"), ("happy", "builder"), ("happy", "explorer"),
        ("happy", "owl"), ("happy", "queen"), ("hungry", nil), ("starving", nil), ("dead", nil),
        ("search", nil), ("party", nil)]
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W) * cols, pixelsHigh: Int(H) * moods.count,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    hex(0x3c4458).setFill()
    NSRect(x: 0, y: 0, width: W * CGFloat(cols), height: H * CGFloat(moods.count)).fill()
    let world = World()
    for (ci, sp) in SPECIES.enumerated() {
        for (ri, (mood, form)) in moods.enumerated() {
            let now = Date().timeIntervalSince1970
            var p = Pet.newEgg(now: now)
            p.species = sp.id
            p.colorIndex = ci % sp.colors.count
            p.form = form
            if mood != "egg" { p.hatchedAt = now - 3 * 86400 }
            p.eggPoints = 9
            p.full = mood == "hungry" ? 20 : mood == "starving" ? 0 : 85
            p.dead = mood == "dead"
            world.save.pet = p
            let v = PetView(world: world)
            v.nextBlink = 1e9
            if ri == 7 { v.mouthUntil = 1e9 }
            if mood == "search" { v.searching = true; v.lean = ci % 2 == 0 ? 1 : -1 }
            if mood == "party" { v.celebrateUntil = 1e9 }
            gctx.cgContext.saveGState()
            // the bitmap context is not flipped: flip each cell by hand
            gctx.cgContext.translateBy(x: CGFloat(ci) * W, y: H * CGFloat(moods.count - ri))
            gctx.cgContext.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: gctx.cgContext, flipped: true)
            v.draw(v.bounds)
            gctx.cgContext.restoreGState()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: sheetPath))
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
