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

let FOOD: [String: (art: String, pts: Double)] = [
    "prompt": ("rice", 3), "edit": ("apple", 1), "bash": ("coffee", 1), "web": ("fish", 2),
    "agent": ("cake", 10), "done": ("cookie", 5), "other": ("candy", 0.5),
]

let NAMES = ["Bagel", "Pixel", "Muffin", "Sprout", "Mochi", "Tofu", "Byte", "Button",
             "Dumpling", "Marshmallow", "Chip", "Noodle", "Crumb", "Biscuit", "Donut", "Bit"]

let FORM_NAME = ["hacker": "Hacker", "builder": "Builder",
                 "explorer": "Explorer", "owl": "Night Owl",
                 "queen": "Hive Queen"]

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
    Species(id: "slime", name: "slime", rows: [
        "........", "........", "......oo", ".....obb", "....obbl", "...obblb", "..obbbbb",
        "..obewbb", ".obbeebb", ".obpbbbm", ".obbbbbb", ".odbbbbb", "..oddddd", "...ooooo",
    ], colors: [0x6fd36b, 0x6ab8f0, 0xf28fc0, 0xb48cf2]),
    Species(id: "ghost", name: "ghost", rows: [
        "........", "........", ".....ooo", "....obbb", "...obbbb", "..obbbbb", "..obbbbb",
        "..obewbb", "..obeebb", "..obpbbm", "..obbbbb", "..obbbbb", "..obbobb", "...oo.oo",
    ], colors: [0xf1eefc, 0xdff3ff], light: 0xffffff, outline: 0x6b6390, floats: true),
    Species(id: "cat", name: "kitty", rows: [
        "........", "..o.....", "..oo....", "..oao...", "..obaooo", ".obbbbbb", ".obbbbbb",
        ".obbewbb", ".obbeebb", ".obpbbbm", ".obbbbbb", "..obbbbb", "..obbobb", "...oo.oo",
    ], colors: [0xb9b9c4, 0xf2a65a, 0xf3e2c3, 0x5a5a66], accent: 0xf6a5b5),
    Species(id: "fox", name: "fox kit", rows: [
        "........", ".o......", ".oo.....", ".oao....", ".oaao...", ".obaaooo", ".obbbbbb",
        ".obbewbb", ".obbeebb", ".obbbbbb", ".olllllm", "..olllll", "...ollll", "....oooo",
    ], colors: [0xf08a3c, 0xe9b44c], accent: 0x3a2620, light: 0xfff3e6),
    Species(id: "frog", name: "froglet", rows: [
        "........", "........", "..ooo...", ".obbbo..", ".obewo..", ".obeeboo", "obbbbbbb",
        "obpbbbbb", "obbbmmmm", "obbbbbbb", ".obbllll", ".obbllll", "..obbooo", ".oooo...",
    ], colors: [0x7cc96a, 0x5fc4b0], light: 0xd9f2b8),
    Species(id: "crab", name: "crab", rows: [
        "........", ".oo.oo..", "oaaoaao.", ".oaaao..", "..oao...", "..oooooo", ".obbbbbb",
        ".obbewbb", "obbbeebb", "obpbbbbm", "obbbbbbb", ".obbbbbb", "..oooooo", ".o.o.o..",
    ], colors: [0xe8604c, 0xf08a5d], accent: 0xc2402f),
    Species(id: "chick", name: "chick", rows: [
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

/// Pixel art for food, icons, toys and poppers: rows of palette letters, '.' is empty.
let ART: [String: (rows: [String], colors: [Character: Int])] = [
    "rice": (["....oooo....", "...owwwwo...", "..owwwwwwo..", "..owwwhwwo..", ".owwwwwwwwo.", ".owwwwwwwwo.", "owwwwwwwwwwo", "owwwnnnnwwwo", "owwwnnnnwwwo", ".oownnnnwoo.", "...oooooo..."],
        ["o": 0x4a4a5a, "w": 0xfffaf0, "h": 0xffffff, "n": 0x1f3a2a]),
    "apple": ([".....b......", ".....bgg....", "..ooobgooo..", ".orrrrrrhro.", "orrrrrrrrhro", "orrrrrrrrrro", "orrrrrrrrrro", "orrrrrrrrrro", ".orrrrrrrdo.", ".orrrrrrddo.", "..oorrrdoo..", "....oooo...."],
        ["o": 0x6e1a24, "r": 0xe5534b, "h": 0xffb3a8, "d": 0xb83a34, "b": 0x6b4226, "g": 0x5cc46a]),
    "coffee": (["...s..s.....", "....s..s....", "...s..s.....", ".oooooooo...", ".occccccooo.", ".owwwwwwo.o.", ".owwwwwwo.o.", ".owwwwwwooo.", ".owwwwwwo...", "..owwwwo....", "...oooo....."],
        ["o": 0x3a2a2a, "c": 0x7a4a2a, "w": 0xf4efe6, "s": 0xc8d0dc]),
    "fish": (["...ooooo....", ".oobbbbbo..o", "obewbbbbbobo", "obbbbbbbbbbo", "ollllllllobo", ".oolllllo..o", "...ooooo...."],
        ["o": 0x24405e, "b": 0x6ab8f0, "l": 0xd8f0ff, "e": 0x1d1b2b, "w": 0xffffff]),
    "cake": ([".....f......", ".....k......", ".....k......", "..oooooooo..", ".owwwwwwwwo.", ".owpwwpwwpo.", ".obbbbbbbbo.", ".oppppppppo.", ".obbbbbbbbo.", ".obbbbbbbbo.", "..oooooooo.."],
        ["o": 0x6b3a22, "w": 0xfffaf5, "p": 0xf28fc0, "b": 0xf3c98b, "f": 0xffb03a, "k": 0x7c83ff]),
    "cookie": (["...oooooo...", "..obbbbbbo..", ".obbdbbbhbo.", "obbbbbbdbbbo", "obdbbbbbbbbo", "obbbbdbbbdbo", "obbbbbbbbbbo", ".obdbbbbdbo.", "..obbbbbbo..", "...oooooo..."],
        ["o": 0x6b3a1a, "b": 0xd9a35a, "h": 0xf0c888, "d": 0x4a2a1a]),
    "candy": (["oo..oooo..oo", "opooppwpoopo", "oppppppppppo", "opooppppoopo", "oo..oooo..oo"],
        ["o": 0x8a2050, "p": 0xff6fa0, "w": 0xffffff]),
    "heart": ([".oo...oo.", "orro.orro", "orwrorrro", "orrrrrrro", ".orrrrro.", "..orrro..", "...oro...", "....o...."],
        ["o": 0x8a1f35, "r": 0xff5d73, "w": 0xffd0d8]),
    "zzz": (["ooooo", "...o.", "..o..", ".o...", "ooooo"],
        ["o": 0x6b6390]),
    "ball": (["...oooo...", ".oowrrboo.", ".owwrrbbo.", "owhwrrbbbo", "owwwrrbbbo", "owwwrrbbbo", "owwwrrbbbo", ".owwrrbbo.", ".oowrrboo.", "...oooo..."],
        ["o": 0x2b2b3a, "w": 0xffffff, "h": 0xd8e4ff, "r": 0xe5534b, "b": 0x4f7cff]),
    "yarn": (["...oooo...", ".oopppoo..", ".oplpplpo.", "oppplpplpo", "oplpplpppo", "opplpplppo", "oppplpplpo", ".opplpppo.", ".oopppooo.", "...oooo.oo"],
        ["o": 0x4a2f7a, "p": 0xb48cf2, "l": 0xe2d4ff]),
    "butterfly": (["...o...o...", "oo..o.o..oo", "oyyo.k.oyyo", "oyyyokoyyyo", ".oyyokoyyo.", ".oddokoddo.", "..oo.k.oo.."],
        ["o": 0x5a2a0a, "y": 0xff9a2e, "d": 0xffd23f, "k": 0x2b2b3a]),
    "popper": (["oooooooooo", "oyrrryybro", ".oyrrybbo.", ".oyyrrbbo.", "..oyrrbo..", "..oyyrbo..", "...oyro...", "...oyro...", "....oo...."],
        ["o": 0x5a2a3a, "y": 0xffd23f, "r": 0xff5d73, "b": 0x4fd1c5]),
]

var artImages: [String: NSImage] = [:]
/// One piece of pixel art as an image (one pixel per art cell), built once and scaled up without smoothing.
func artImage(_ name: String) -> NSImage {
    if let img = artImages[name] { return img }
    let a = ART[name] ?? ART["candy"]!
    let w = a.rows[0].count, h = a.rows.count
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let bytes = rep.bitmapData!, stride = rep.bytesPerRow
    memset(bytes, 0, stride * h)
    for (r, row) in a.rows.enumerated() {
        for (c, ch) in row.enumerated() {
            guard let v = a.colors[ch] else { continue }
            let o = r * stride + c * 4
            bytes[o] = UInt8((v >> 16) & 255); bytes[o + 1] = UInt8((v >> 8) & 255)
            bytes[o + 2] = UInt8(v & 255); bytes[o + 3] = 255
        }
    }
    let img = NSImage(size: NSSize(width: w, height: h))
    img.addRepresentation(rep.retagging(with: .sRGB) ?? rep)
    artImages[name] = img
    return img
}

/// Draws pixel art centred on `c`, each art cell `px` points wide; `flapX` squashes it sideways (wings).
func drawArt(_ name: String, px: CGFloat, center c: NSPoint, alpha: CGFloat = 1, flapX: CGFloat = 1) {
    let img = artImage(name)
    let w = img.size.width * px * flapX, h = img.size.height * px
    NSGraphicsContext.current?.imageInterpolation = .none
    img.draw(in: NSRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), from: .zero,
             operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
}

var spriteImages: [String: NSImage] = [:]
/// The pet's body for one look (eyes open/closed/happy, mouth, starving grey) as a 16×16 pixel image,
/// built once; drawing ~150 cells one by one every frame was most of the app's CPU.
func spriteImage(rows: [String], sprite: Sprite, pal: [Character: NSColor], palKey: String,
                 closed: Bool, party: Bool, open: Bool, grey: Bool) -> NSImage {
    let key = "\(rows.count)\(rows[2])\(rows[7])\(palKey)\(closed)\(party)\(open)\(grey)"
    if let img = spriteImages[key] { return img }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let bytes = rep.bitmapData!, stride = rep.bytesPerRow
    memset(bytes, 0, stride * 16)
    func put(_ r: Int, _ c: Int, _ col: NSColor) {
        guard (0..<16).contains(r + 2), (0..<16).contains(c),
              let k = (grey ? greyed(col) : col).usingColorSpace(.sRGB) else { return }
        let a = k.alphaComponent, o = (r + 2) * stride + c * 4   // premultiplied RGBA
        bytes[o] = UInt8(k.redComponent * a * 255); bytes[o + 1] = UInt8(k.greenComponent * a * 255)
        bytes[o + 2] = UInt8(k.blueComponent * a * 255); bytes[o + 3] = UInt8(a * 255)
    }
    let maxEyeRow = sprite.eyes.map { $0.0 }.max() ?? 0
    for (r, row) in sprite.grid.enumerated() {
        for (c, ch) in row.enumerated() where ch != "." {
            var k = ch
            if (ch == "e" || ch == "w") && party { k = r == maxEyeRow ? "b" : "e" }
            else if (ch == "e" || ch == "w") && closed { k = r == maxEyeRow ? "o" : "b" }
            if let col = pal[k] { put(r, c, col) }
            if ch == "m" && open && r + 1 < sprite.grid.count { put(r + 1, c, hex(0x5b2433)) }
        }
    }
    if party {
        // happy ^^ eyes: legs at the outer edges of each eye
        for side in [sprite.eyes.filter { $0.1 < 8 }, sprite.eyes.filter { $0.1 >= 8 }] where !side.isEmpty {
            for c in [side.map { $0.1 }.min()! - 1, side.map { $0.1 }.max()! + 1] { put(maxEyeRow, c, pal["e"]!) }
        }
    }
    let img = NSImage(size: NSSize(width: 16, height: 16))
    img.addRepresentation(rep.retagging(with: .sRGB) ?? rep)
    spriteImages[key] = img
    return img
}

var greyCache: [NSColor: NSColor] = [:]
/// A colour washed towards grey (the starving look), cached.
func greyed(_ c: NSColor) -> NSColor {
    if let g = greyCache[c] { return g }
    let g = (c.blended(withFraction: 0.55, of: hex(0x8a8a8a)) ?? c).withAlphaComponent(c.alphaComponent)
    greyCache[c] = g
    return g
}

var spriteCache: [String: Sprite] = [:]
/// Parsed sprite for these rows, built once.
func sprite(_ rows: [String]) -> Sprite {
    let key = rows.joined(separator: "|")
    if let s = spriteCache[key] { return s }
    let s = Sprite(rows)
    spriteCache[key] = s
    return s
}

func hex(_ v: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
            blue: CGFloat(v & 255) / 255, alpha: a)
}

var paletteCache: [String: [Character: NSColor]] = [:]
func palette(body b: Int, accent: Int, light: Int?, outline: Int?, mouth: Int?) -> [Character: NSColor] {
    let key = "\(b) \(accent) \(light ?? -1) \(outline ?? -1) \(mouth ?? -1)"
    if let p = paletteCache[key] { return p }
    let body = hex(b)
    let p: [Character: NSColor] = [
        "b": body,
        "o": outline.map { hex($0) } ?? body.blended(withFraction: 0.68, of: .black)!,
        "l": light.map { hex($0) } ?? body.blended(withFraction: 0.5, of: .white)!,
        "d": body.blended(withFraction: 0.2, of: .black)!,
        "e": hex(0x1d1b2b), "w": .white, "p": hex(0xff7aa2, 0.6),
        "m": mouth.map { hex($0) } ?? hex(0x5b2433),
        "a": hex(accent),
    ]
    paletteCache[key] = p
    return p
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
    var onEvolve: (() -> Void)?
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
        if live { onFood?(food.art, food.pts) }
    }

    func die(at t: Double) {
        var p = pet
        p.dead = true
        p.diedAt = t
        pet = p
        let days = Int(((t - (p.hatchedAt ?? t)) / 86400).rounded(.down)) + 1
        save.graves.append(Grave(name: p.name, species: p.species, form: p.form, days: days, diedAt: t))
        dirty = true
        notifyTG("🪦 \(p.name) starved to death after \(days) days. Bury them and start over with a new egg.")
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
            onEvolve?()
        }
        let left = DEATH_HOURS * 3600 - (now - pet.lastFood)
        if full(at: now) <= 0 && !pet.notifiedHungry {
            var p = pet; p.notifiedHungry = true; pet = p
            notifyTG("🥺 \(pet.name) is starving. Do some work in Claude Code or they die in \(Int(left / 3600)) h.")
        }
        if left < 6 * 3600 && !pet.notifiedDying {
            var p = pet; p.notifiedDying = true; pet = p
            notifyTG("🚨 Less than 6 hours left for \(pet.name)! One prompt in Claude Code saves them.")
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

struct Drop { var art: String; var x: CGFloat; var y: CGFloat; var vy: CGFloat; var pts: Double }
struct Particle { var text: String; var x: CGFloat; var y: CGFloat; var vy: CGFloat; var vx: CGFloat; var life: Double; var size: CGFloat; var color: NSColor }

let W: CGFloat = 200, CELL: CGFloat = 6
let FOOT_PAD: CGFloat = 36                        // room under the feet: a pet spinning mid-air stays inside its window
let H: CGFloat = 228 + FOOT_PAD
let SPRITE_X = (W - 16 * CELL) / 2, SPRITE_Y: CGFloat = H - FOOT_PAD - 16 * CELL   // top of the 16×16 canvas

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
    var hovering = false
    var searching = false, celebrateUntil = 0.0
    var onPick: (() -> Void)?
    var onDrop: ((CGVector) -> Void)?
    var trail: [(t: Double, p: NSPoint)] = []   // recent cursor samples while held
    var squashAmt: CGFloat = 0.1, spin: CGFloat = 0
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


    func enqueue(_ art: String, _ pts: Double) {
        if pending.count < 12 { pending.append((art, pts)) }
    }

    var mouthY: CGFloat {
        let sp = sprite(world.species.rows)
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
            drops.append(Drop(art: e, x: W / 2 + CGFloat.random(in: -26...26), y: -24, vy: 40, pts: p))
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
            squashUntil = t + 0.18
            squashAmt = 0.1
        }
        drops.removeAll { $0.y >= target }
        for i in particles.indices {
            particles[i].y += particles[i].vy * CGFloat(dt)
            particles[i].x += particles[i].vx * CGFloat(dt)
            particles[i].life -= dt
        }
        particles.removeAll { $0.life <= 0 }
        if m == "sleep" && Int(t * 10) % 14 == 0 && particles.filter({ $0.text == "zzz" }).count < 2 {
            particles.append(Particle(text: "zzz", x: W / 2 + 30, y: SPRITE_Y + 20, vy: -14, vx: 8, life: 2.4, size: 13, color: hex(0x6b6390)))
        }
        needsDisplay = true
    }

    /// The pet's current body (egg, gravestone, or the creature itself) as an 18-pt menu bar icon.
    func menuBarIcon() -> NSImage {
        let w = world, m = mood, sp = w.species
        let rows: [String], pal: [Character: NSColor], palKey: String
        if m == "dead" {
            rows = TOMB_ROWS; palKey = "tomb"
            pal = palette(body: 0xaeb0bb, accent: 0x6fbf5a, light: nil, outline: 0x5d5f6b, mouth: nil)
        } else if m == "egg" {
            rows = EGG_ROWS; palKey = "egg\(w.pet.species)\(w.pet.colorIndex)"
            pal = palette(body: 0xfbf4e4, accent: sp.colors[w.pet.colorIndex % sp.colors.count], light: nil, outline: 0x8a7f6a, mouth: nil)
        } else {
            rows = sp.rows; palKey = "\(sp.id)\(w.pet.colorIndex)"
            pal = palette(body: sp.colors[w.pet.colorIndex % sp.colors.count], accent: sp.accent, light: sp.light, outline: sp.outline, mouth: sp.mouth)
        }
        let body = spriteImage(rows: rows, sprite: sprite(rows), pal: pal, palKey: palKey,
                               closed: m == "sleep", party: false, open: false, grey: m == "starving")
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            NSGraphicsContext.current?.imageInterpolation = .none
            body.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        icon.isTemplate = false
        return icon
    }

    func pet() {
        switch mood {
        case "dead", "starving", "hungry": break
        case "egg": wobbleUntil = t + 0.6
        default:
            for i in 0..<4 {
                particles.append(Particle(text: "heart", x: W / 2 + CGFloat(i * 14 - 24), y: SPRITE_Y + 30, vy: -30 - CGFloat(i * 6), vx: CGFloat.random(in: -8...8), life: 1.3, size: 13, color: .red))
            }
        }
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill(using: .copy)
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
        var palKey = ""
        let sp = w.species
        if m == "dead" {
            rows = TOMB_ROWS
            palKey = "tomb"
            pal = palette(body: 0xaeb0bb, accent: 0x6fbf5a, light: nil, outline: 0x5d5f6b, mouth: nil)
        } else if m == "egg" {
            rows = EGG_ROWS
            palKey = "egg\(w.pet.species)\(w.pet.colorIndex)"
            pal = palette(body: 0xfbf4e4, accent: sp.colors[w.pet.colorIndex % sp.colors.count], light: nil, outline: 0x8a7f6a, mouth: nil)
        } else {
            rows = sp.rows
            palKey = "\(sp.id)\(w.pet.colorIndex)"
            pal = palette(body: sp.colors[w.pet.colorIndex % sp.colors.count], accent: sp.accent, light: sp.light, outline: sp.outline, mouth: sp.mouth)
        }
        let sprite = sprite(rows)
        let grey = m == "starving"
        let party = t < celebrateUntil && m != "dead" && m != "egg"
        let closed = party || m == "sleep" || t < blinkUntil || m == "starving" && Int(t) % 4 == 0
        let open = party || t < mouthUntil
        let squash: CGFloat = t < squashUntil ? 1 - squashAmt * CGFloat((squashUntil - t) / 0.22).squareRoot() : (m == "starving" ? 0.86 : 1)
        var wobble: CGFloat = 0
        if t < wobbleUntil { wobble = CGFloat(sin((wobbleUntil - t) * 30)) * 0.08 }
        if walking { wobble += lean * 0.07 + CGFloat(sin(t * 11)) * 0.05 }
        if held { wobble = CGFloat(sin(t * 5)) * 0.12 }

        ctx.saveGState()
        let baseX = SPRITE_X + 8 * CELL, baseY = SPRITE_Y + 16 * CELL
        // the mid-air tumble turns around the body's middle; sways and wobbles pivot on the feet
        ctx.translateBy(x: baseX, y: SPRITE_Y + 9 * CELL + bob)
        ctx.setShouldAntialias(spin != 0 || wobble != 0)
        ctx.rotate(by: spin)
        ctx.translateBy(x: 0, y: baseY - (SPRITE_Y + 9 * CELL))
        ctx.rotate(by: wobble)
        ctx.scaleBy(x: 2 - squash, y: squash)
        ctx.translateBy(x: -8 * CELL, y: -16 * CELL)

        // the whole body is one cached 16×16 image, scaled up with no smoothing
        let img = spriteImage(rows: rows, sprite: sprite, pal: pal, palKey: palKey,
                              closed: closed, party: party, open: open, grey: grey)
        NSGraphicsContext.current?.imageInterpolation = .none
        img.draw(in: NSRect(x: 0, y: 0, width: 16 * CELL, height: 16 * CELL), from: .zero,
                 operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if let form = w.pet.form, m != "dead", m != "egg" { drawForm(form, sprite, pal) }
        ctx.restoreGState()

        if w.pet.form == "queen" && m != "dead" { drawMinions(pal) }

        // food
        for d in drops {
            drawArt(d.art, px: 2, center: NSPoint(x: d.x + 12, y: d.y + 12))
        }
        // particles
        for p in particles {
            drawArt(p.text, px: p.size / 7, center: NSPoint(x: p.x + 7, y: p.y + 7), alpha: CGFloat(min(1, p.life * 1.5)))
        }
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

    /// The body alone at the canvas origin (16×16 cells), for the evolution show: `white` washes it into a silhouette.
    func drawBody(form: String?, white: CGFloat, party: Bool) {
        let sp = world.species
        let pal = palette(body: sp.colors[world.pet.colorIndex % sp.colors.count], accent: sp.accent, light: sp.light, outline: sp.outline, mouth: sp.mouth)
        let spr = sprite(sp.rows)
        let img = spriteImage(rows: sp.rows, sprite: spr, pal: pal, palKey: "\(sp.id)\(world.pet.colorIndex)",
                              closed: party, party: party, open: party, grey: false)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        NSGraphicsContext.current?.imageInterpolation = .none
        img.draw(in: NSRect(x: 0, y: 0, width: 16 * CELL, height: 16 * CELL), from: .zero,
                 operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if let form { drawForm(form, spr, pal) }
        if white > 0 {
            NSColor(calibratedRed: 1, green: 0.98, blue: 0.9, alpha: min(1, white)).set()
            NSRect(x: -4 * CELL, y: -4 * CELL, width: 24 * CELL, height: 24 * CELL).fill(using: .sourceAtop)
        }
        ctx.endTransparencyLayer()
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


    // MARK: mouse — drag across any screen

    override func mouseDown(with e: NSEvent) {
        dragStart = NSEvent.mouseLocation
        winStart = window?.frame.origin
        dragged = false
        trail = [(e.timestamp, dragStart!)]
        if e.clickCount == 2 { onDoubleClick?() }
    }

    override func mouseDragged(with e: NSEvent) {
        guard let s = dragStart, let o = winStart, let win = window else { return }
        let p = NSEvent.mouseLocation
        if !dragged && abs(p.x - s.x) + abs(p.y - s.y) > 3 { dragged = true; held = true; spin = 0; onPick?() }
        win.setFrameOrigin(NSPoint(x: o.x + p.x - s.x, y: o.y + p.y - s.y))
        trail.append((e.timestamp, p))
        trail.removeAll { e.timestamp - $0.t > 0.12 }
    }

    /// Cursor velocity (points/s) over the last ~80 ms; zero if the hand stopped before letting go.
    func throwVelocity(at now: Double) -> CGVector {
        let recent = trail.filter { now - $0.t < 0.08 }
        guard let a = recent.first, let b = recent.last, b.t - a.t > 0.008 else { return .zero }
        let dt = CGFloat(b.t - a.t)
        return CGVector(dx: (b.p.x - a.p.x) / dt, dy: (b.p.y - a.p.y) / dt)
    }

    override func mouseUp(with e: NSEvent) {
        if dragged {
            held = false
            window?.saveFrame(usingName: "ClawdlingWindow")
            onDrop?(throwVelocity(at: e.timestamp))
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

    /// Squash on impact; `strength` 0…1 from the landing speed.
    func land(_ strength: CGFloat = 0.5) {
        squashUntil = t + 0.22
        squashAmt = 0.08 + 0.3 * min(1, strength)
    }

    override func rightMouseDown(with e: NSEvent) {
        if let menu = menuProvider?() { NSMenu.popUpContextMenu(menu, with: e, for: self) }
    }
}


// MARK: - Toys (a small window of their own on the screen floor)

final class ToyView: NSView {
    var art = "ball"
    var angle: CGFloat = 0
    var onKick: (() -> Void)?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ r: NSRect) {
        NSColor.clear.set()
        r.fill(using: .copy)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.translateBy(x: bounds.midX, y: bounds.midY)
        ctx.rotate(by: angle)
        // a butterfly flaps: its wings squash sideways and spring back
        let flap = art == "butterfly" ? 0.35 + 0.65 * abs(CGFloat(sin(Date().timeIntervalSince1970 * 14))) : 1
        drawArt(art, px: bounds.width / 15, center: .zero, flapX: flap)
    }
    override func mouseDown(with e: NSEvent) { onKick?() }
}

final class Toy {
    /// Every toy window that is on screen, so strays can be found and closed.
    static var live: [Toy] = []
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
        view.art = kind
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
        Toy.live.append(self)
    }

    var g: CGFloat = 1300

    func kick(dir: CGFloat) {
        if kind == "butterfly" {
            vx = dir * CGFloat.random(in: 140...240)
            phase += 2
        } else {
            vx = dir * CGFloat.random(in: 260...480)
            vy = (2 * g * CGFloat.random(in: 8...60)).squareRoot()   // hop 8–60 pt high
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
            vy -= g * dt
            y += vy * dt
            if y <= 0 {
                y = 0
                vy = abs(vy) > (2 * g * 2).squareRoot() ? -vy * 0.55 : 0
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

    func close() {
        panel.orderOut(nil)
        Toy.live.removeAll { $0 === self }
    }
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
        NSColor.clear.set()
        r.fill(using: .copy)
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
            // pixel party cones, mouths tipped outwards, sliding apart as they pop
            let k = CGFloat(min(1, age * 6)), y: CGFloat = 58
            let alpha = CGFloat(min(1, (1.5 - age) * 3))
            for side: CGFloat in [-1, 1] {
                ctx.saveGState()
                ctx.translateBy(x: bounds.midX + side * 72 * k, y: y)
                ctx.rotate(by: side * -0.6)   // mouths tip outwards
                drawArt("popper", px: 3, center: .zero, alpha: alpha)
                ctx.restoreGState()
            }
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


// MARK: - Evolution: the pet spins up into a blaze of light, whirls in mid-air, bursts and lands in its new form

final class EvolveView: NSView {
    struct Spark { var x, y, vx, vy, life, max, size: CGFloat; var color: NSColor; var star: Bool }
    unowned let pet: PetView
    let oldForm: String?, newForm: String
    var cx: CGFloat = 0, floorY: CGFloat = 0, s: CGFloat = 1   // floorY: the feet line, flipped view coordinates
    var age = 0.0, phase: CGFloat = 0, flick: CGFloat = 0, shake: CGFloat = 0
    var sparks: [Spark] = []
    var burst = false
    // timeline, seconds
    static let rise = 0.8, top = 2.8, pop = 4.7, fall = 6.1, land = 6.7, end = 8.4
    override var isFlipped: Bool { true }

    init(pet: PetView, oldForm: String?, newForm: String, frame: NSRect) {
        self.pet = pet; self.oldForm = oldForm; self.newForm = newForm
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    func ease(_ x: Double) -> CGFloat { let k = min(1, max(0, x)); return CGFloat(k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2) }
    func k(_ a: Double, _ b: Double) -> CGFloat { CGFloat(min(1, max(0, (age - a) / (b - a)))) }

    var lift: CGFloat {
        let h = 230 * s
        if age < Self.rise { return 0 }
        if age < Self.top { return h * ease((age - Self.rise) / (Self.top - Self.rise)) }
        if age < Self.fall { return h + CGFloat(sin((age - Self.top) * 2.6)) * 6 * s }
        let x = k(Self.fall, Self.land)
        return h * (1 - x * x)
    }
    /// How bright the light is, 0…1.
    var glow: CGFloat {
        if age < Self.rise { return 0.35 * k(0, Self.rise) }
        if age < Self.top { return 0.35 + 0.3 * k(Self.rise, Self.top) }
        if age < Self.pop { return 0.65 + 0.35 * k(Self.top, Self.pop) }
        return 0.9 * (1 - k(Self.pop + 0.3, Self.land + 0.4))
    }
    /// Spin speed around the body's own vertical axis, rad/s.
    var omega: CGFloat {
        if age < Self.rise { return 0 }
        if age < Self.top { return 3 + 15 * k(Self.rise, Self.top) }
        if age < Self.pop { return 18 + 34 * k(Self.top, Self.pop) }
        return 0
    }
    var white: CGFloat {
        if age < Self.rise { return 0 }
        if age < Self.top { return 0.4 * k(Self.rise, Self.top) }
        if age < Self.pop { return 0.4 + 0.6 * k(Self.top, Self.pop - 0.4) }
        return 1 - k(Self.pop + 0.15, Self.pop + 0.9)
    }
    var center: NSPoint { NSPoint(x: cx + shake, y: floorY - 2 * s - lift - 8 * CELL * s) }

    let gold = [0xffffff, 0xfff3b0, 0xffd23f, 0xffb43c, 0xbfe9ff]

    func step(_ dt: CGFloat) {
        age += Double(dt)
        phase += omega * dt
        if age > Self.top && age < Self.pop {   // the old and new look swap faster and faster
            flick += dt / (0.32 - 0.27 * k(Self.top, Self.pop))
        }
        let trem: CGFloat = age < Self.rise ? 2 * k(0, Self.rise) : (age > Self.top && age < Self.pop ? 4 * k(Self.top, Self.pop) : 0)
        shake = trem > 0 ? CGFloat.random(in: -trem...trem) * s : 0
        let c = center
        // charging: motes of light stream into the body
        if age < Self.pop {
            let rate = 30 + 90 * Double(glow)
            for _ in 0..<Int((rate * Double(dt) + Double.random(in: 0...1)).rounded(.down)) {
                let a = CGFloat.random(in: 0...(2 * .pi)), r = CGFloat.random(in: 120...260) * s
                let life = CGFloat.random(in: 0.45...0.8)
                sparks.append(Spark(x: c.x + cos(a) * r, y: c.y + sin(a) * r, vx: -cos(a) * r / life, vy: -sin(a) * r / life,
                                    life: life, max: life, size: CGFloat.random(in: 2...4).rounded() * s,
                                    color: hex(gold.randomElement()!), star: false))
            }
        }
        if age >= Self.pop && !burst {
            burst = true
            let sp = pet.world.species
            let tints = gold + [sp.colors[pet.world.pet.colorIndex % sp.colors.count], sp.accent]
            for i in 0..<220 {
                let a = CGFloat.random(in: 0...(2 * .pi)), v = CGFloat.random(in: 250...1300) * s
                let life = CGFloat.random(in: 0.9...2.2)
                sparks.append(Spark(x: c.x, y: c.y, vx: cos(a) * v, vy: sin(a) * v - 200 * s, life: life, max: life,
                                    size: CGFloat.random(in: 3...7).rounded() * s, color: hex(tints.randomElement()!), star: i % 6 == 0))
            }
        }
        for i in sparks.indices {
            sparks[i].life -= dt
            if age >= Self.pop { sparks[i].vy += 700 * s * dt * (sparks[i].star ? 0.3 : 1) }
            let drag = pow(0.25, dt)
            if age >= Self.pop { sparks[i].vx *= drag; sparks[i].vy *= drag }
            sparks[i].x += sparks[i].vx * dt
            sparks[i].y += sparks[i].vy * dt
        }
        sparks.removeAll { $0.life <= 0 }
        needsDisplay = true
    }

    override func draw(_ r: NSRect) {
        NSColor.clear.set()
        r.fill(using: .copy)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let c = center, g = glow, t = CGFloat(age)

        // rays turning slowly behind the pet
        if g > 0.02 {
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: t * 0.7)
            let n = 16
            for i in 0..<n {
                let a = CGFloat(i) / CGFloat(n) * 2 * .pi
                let len = (160 + 520 * g) * s * (i % 2 == 0 ? 1 : 0.62) * (1 + 0.08 * sin(t * 5 + CGFloat(i)))
                let wd: CGFloat = i % 2 == 0 ? 0.055 : 0.035
                let path = CGMutablePath()
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: cos(a - wd) * len, y: sin(a - wd) * len))
                path.addLine(to: CGPoint(x: cos(a + wd) * len, y: sin(a + wd) * len))
                path.closeSubpath()
                ctx.addPath(path)
                ctx.saveGState()
                ctx.clip()
                let rg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [CGColor(red: 1, green: 0.97, blue: 0.8, alpha: 0.55 * g), CGColor(red: 1, green: 0.85, blue: 0.4, alpha: 0)] as CFArray,
                                    locations: [0, 1])!
                ctx.drawRadialGradient(rg, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: len, options: [])
                ctx.restoreGState()
            }
            ctx.restoreGState()
        }
        // the blaze itself
        if g > 0.01 {
            let R = (70 + 190 * g) * s * (1 + 0.04 * sin(t * 9))
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                CGColor(red: 1, green: 1, blue: 1, alpha: min(1, 1.1 * g)),
                CGColor(red: 1, green: 0.97, blue: 0.82, alpha: 0.85 * g),
                CGColor(red: 1, green: 0.84, blue: 0.42, alpha: 0.4 * g),
                CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 0)] as CFArray, locations: [0, 0.22, 0.55, 1])!
            ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: R, options: [])
        }
        // shadow left on the floor
        if age < Self.land + 0.3 {
            let w = max(10, 70 * s * (1 - lift / (300 * s)))
            hex(0x000000, 0.18).setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - w / 2, y: floorY - 6 * s, width: w, height: 8 * s)).fill()
        }
        // the pet: turns around its own axis, flickers between the old and the new look, then bursts out new
        if age < Self.land {
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y + 8 * CELL * s)
            var sx = cos(phase), pop: CGFloat = 1
            if age >= Self.pop {
                sx = 1
                let x = k(Self.pop, Self.pop + 0.45)
                pop = 1 + 0.45 * (1 - x) * cos(x * 9)
            }
            if abs(sx) < 0.08 { sx = sx < 0 ? -0.08 : 0.08 }   // edge-on: a sliver, not nothing
            ctx.scaleBy(x: s * sx * pop, y: s * pop)
            ctx.translateBy(x: -8 * CELL, y: -16 * CELL)
            ctx.setShouldAntialias(false)
            let form = age >= Self.pop ? newForm : (Int(flick) % 2 == 1 ? newForm : oldForm)
            pet.drawBody(form: form, white: white, party: age < Self.pop || age > Self.fall)
            ctx.restoreGState()
        }
        // flash and shock rings at the burst
        if age >= Self.pop {
            let x = CGFloat(age - Self.pop)
            if x < 0.5 {
                NSColor(calibratedRed: 1, green: 0.98, blue: 0.9, alpha: 0.75 * (1 - x / 0.5)).setFill()
                bounds.fill(using: .sourceOver)
            }
            for (i, delay) in [0.0, 0.12].enumerated() {
                let y = x - CGFloat(delay)
                guard y > 0 && y < 0.7 else { continue }
                let rad = (40 + 1500 * y * (1 - y * 0.6)) * s
                let ring = NSBezierPath(ovalIn: NSRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
                ring.lineWidth = (i == 0 ? 14 : 7) * s * (1 - y / 0.7)
                NSColor(calibratedRed: 1, green: 0.95, blue: 0.75, alpha: 0.9 * (1 - y / 0.7)).setStroke()
                ring.stroke()
            }
        }
        // pixel sparks and four-point stars
        ctx.setShouldAntialias(false)
        for p in sparks {
            let a = min(1, p.life / p.max * 2.2)
            p.color.withAlphaComponent(a).setFill()
            let z = p.size
            if p.star {
                let arm = sin(t * 18 + p.x) > 0 ? z : 0   // twinkle: the arms blink in and out
                NSRect(x: (p.x - z / 2).rounded(), y: (p.y - z / 2 - arm).rounded(), width: z, height: z + 2 * arm).fill()
                NSRect(x: (p.x - z / 2 - arm).rounded(), y: (p.y - z / 2).rounded(), width: z + 2 * arm, height: z).fill()
            } else {
                NSRect(x: (p.x - z / 2).rounded(), y: (p.y - z / 2).rounded(), width: z, height: z).fill()
            }
        }
    }
}

final class Evolution {
    let panel: NSPanel
    let view: EvolveView

    init(pet: PetView, oldForm: String?, newForm: String, centerX: CGFloat, floor: CGFloat, scale: CGFloat) {
        let scr = NSScreen.screens.first { $0.frame.minX <= centerX && centerX < $0.frame.maxX && $0.frame.minY <= floor + 1 && floor < $0.frame.maxY }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let f = scr.frame
        panel = NSPanel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.depthLimit = .twentyfourBitRGB
        view = EvolveView(pet: pet, oldForm: oldForm, newForm: newForm, frame: NSRect(origin: .zero, size: f.size))
        view.cx = centerX - f.minX
        view.floorY = f.maxY - floor
        view.s = scale
        panel.contentView = view
        panel.orderFrontRegardless()
    }

    var landed: Bool { view.age >= EvolveView.land }
    var isDone: Bool { view.age >= EvolveView.end }
    func step(_ dt: CGFloat) { view.step(dt) }
    func close() { panel.orderOut(nil) }
}


// MARK: - Notch ear: the pet's icon in a black tab grown out of the left side of the MacBook notch

final class EarView: NSView {
    var icon: NSImage?
    var fullness: Double = 1      // 0…1, drawn as a thin bar; < 0 hides it
    var notchOverlap: CGFloat = 12
    var bumpUntil = 0.0
    var onClick: ((NSEvent) -> Void)?
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ r: NSRect) {
        NSColor.clear.set()
        r.fill(using: .copy)
        // black tab, flush with the notch on its right, rounded at the bottom left like the notch itself
        let b = bounds, rad: CGFloat = 9
        let path = NSBezierPath()
        path.move(to: NSPoint(x: b.maxX, y: b.maxY))
        path.line(to: NSPoint(x: 0, y: b.maxY))
        path.line(to: NSPoint(x: 0, y: rad))
        path.appendArc(withCenter: NSPoint(x: rad, y: rad), radius: rad, startAngle: 180, endAngle: 270)
        path.line(to: NSPoint(x: b.maxX, y: 0))
        path.close()
        NSColor.black.setFill()
        path.fill()
        let area = NSRect(x: 0, y: 0, width: b.width - notchOverlap, height: b.height)
        let hop = Date().timeIntervalSince1970 < bumpUntil ? CGFloat(2) : 0
        let c = NSPoint(x: area.midX, y: area.midY + hop)
        // health ring around the pet: fills clockwise from the top, green → yellow → red
        let ringR: CGFloat = 12
        if fullness >= 0 {
            let track = NSBezierPath()
            track.appendArc(withCenter: c, radius: ringR, startAngle: 0, endAngle: 360)
            track.lineWidth = 2.5
            NSColor(white: 1, alpha: 0.16).setStroke()
            track.stroke()
            let f = CGFloat(min(1, max(0, fullness)))
            if f > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: c, radius: ringR, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
                arc.lineWidth = 2.5
                arc.lineCapStyle = .round
                (fullness > 0.6 ? hex(0x5cc46a) : fullness > 0.3 ? hex(0xf2b33d) : hex(0xe5534b)).setStroke()
                arc.stroke()
            }
        }
        if let icon {
            NSGraphicsContext.current?.imageInterpolation = .none
            let size: CGFloat = 16
            icon.draw(in: NSRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size),
                      from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    override func mouseDown(with e: NSEvent) { onClick?(e) }
}

final class NotchEar {
    let panel: NSPanel
    let view = EarView()
    static let width: CGFloat = 34   // visible part, left of the notch

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 46, height: 32),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)   // above the menu bar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.contentView = view
    }

    /// The notch of the first screen that has one, in global coordinates.
    static func notchRect() -> NSRect? {
        for scr in NSScreen.screens where scr.safeAreaInsets.top > 0 {
            guard let l = scr.auxiliaryTopLeftArea, let r = scr.auxiliaryTopRightArea else { continue }
            return NSRect(x: l.maxX, y: scr.frame.maxY - scr.safeAreaInsets.top,
                          width: r.minX - l.maxX, height: scr.safeAreaInsets.top)
        }
        return nil
    }

    /// Sits the tab against the notch's left edge; false when no screen has a notch.
    @discardableResult func place() -> Bool {
        guard let n = NotchEar.notchRect() else { panel.orderOut(nil); return false }
        let f = NSRect(x: n.minX - NotchEar.width, y: n.minY, width: NotchEar.width + view.notchOverlap, height: n.height)
        panel.setFrame(f, display: true)
        view.frame = NSRect(origin: .zero, size: f.size)
        panel.orderFrontRegardless()
        return true
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate {
    let world = World()
    var panel: NSPanel!
    var view: PetView!
    var lastStep = Date().timeIntervalSince1970
    var statusItem: NSStatusItem!
    let ear = NotchEar()
    var iconKey = ""

    // walking along the screen floor
    var act = "fall"            // idle, walk, play, fall
    var actUntil = 0.0
    var targetX: CGFloat = 0    // target for the pet's center (screen coordinates)
    var air: CGFloat = 0, vy: CGFloat = 0, vx: CGFloat = 0
    var lastFloor: CGFloat?
    /// Height of the pet's feet above the window's bottom edge.
    var footOffset: CGFloat { (FOOT_PAD - 2) * CGFloat(world.save.scale) }
    var G: CGFloat = 4200       // gravity in points/s²
    var spinRate: CGFloat = 0
    var toy: Toy?
    var playUntil = 0.0
    var lastPlay = ProcessInfo.processInfo.environment["CLAWDLING_PLAY"] != nil ? 0 : Date().timeIntervalSince1970 - 30
    var lastKick = 0.0
    var confetti: [Confetti] = []
    var evolution: Evolution?
    var evolveQueued = ProcessInfo.processInfo.environment["CLAWDLING_EVOLVE"] != nil
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
        panel.depthLimit = .twentyfourBitRGB   // 8-bit colour; an HDR (16-bit) buffer doubled every fill
        applyScale()
        if !panel.setFrameUsingName("ClawdlingWindow"), let s = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: s.maxX - panel.frame.width - 40, y: s.minY + 30))
        }
        panel.orderFrontRegardless()
        air = 400   // drops to the floor on launch

        world.onFood = { [weak self] e, p in
            guard let self else { return }
            self.view.enqueue(e, p)
            self.ear.view.bumpUntil = Date().timeIntervalSince1970 + 0.18
            self.ear.view.needsDisplay = true
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in self?.ear.view.needsDisplay = true }
        }
        world.onAsk = { [weak self] in self?.startSearch() }
        // Debug: CLAWDLING_THROW="vx,vy[,x,y]" throws the pet 2 s after launch (points/s), from mid-screen or a global point.
        if let th = ProcessInfo.processInfo.environment["CLAWDLING_THROW"] {
            let v = th.split(separator: ",").compactMap { Double($0) }
            Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                guard let self, v.count >= 2 else { return }
                if v.count == 4 {   // "vx,vy,x,y": start from this global point
                    self.panel.setFrameOrigin(NSPoint(x: v[2] - W / 2, y: v[3]))
                } else {
                    let vis = self.floorInfo().0
                    self.panel.setFrameOrigin(NSPoint(x: vis.midX - W / 2, y: vis.minY + 300))
                }
                self.view.onDrop?(CGVector(dx: v[0], dy: v[1]))
            }
        }
        world.onActivity = { [weak self] in self?.stopSearch() }
        world.onDone = { [weak self] in self?.celebrate() }
        world.onEvolve = { [weak self] in self?.evolveQueued = true }
        view.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
        view.onDoubleClick = { [weak self] in self?.showStats() }
        view.onPick = { [weak self] in self?.act = "fall"; self?.vx = 0; self?.vy = 0 }
        view.onDrop = { [weak self] v in
            guard let self else { return }
            let floor = self.floorInfo().1
            self.lastFloor = floor
            self.air = max(0, self.panel.frame.origin.y + self.footOffset - 2 * CGFloat(self.world.save.scale) - floor)
            // throw: the cursor's velocity at release, capped so it peaks at most ~1600 pt up
            let cap = (2 * self.G * 1600).squareRoot()
            let sp = hypot(v.dx, v.dy), k = sp > cap ? cap / sp : 1
            self.vx = v.dx * k
            self.vy = v.dy * k
            self.spinRate = -self.vx / 900
            self.act = "fall"
        }

        let now = Date().timeIntervalSince1970
        world.pollEvents(now: now)
        world.tick(now: now)
        world.persist()

        if #available(macOS 14, *) {
            // display-synced frames (100/120 Hz on ProMotion and fast monitors)
            let link = view.displayLink(target: self, selector: #selector(onDisplayFrame(_:)))
            link.add(to: .main, forMode: .common)
        }
        // backup clock: a display link stops when its window is on no display, and the pet would freeze there
        let backup = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Date().timeIntervalSince1970 - self.lastStep > 0.1 { self.frame() }
        }
        RunLoop.main.add(backup, forMode: .common)

        // menu bar icon: the pet itself; click for its menu and "Find"
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.toolTip = "Clawdling"
        // by the notch when the Mac has one; otherwise a regular menu bar icon
        ear.view.onClick = { [weak self] e in
            guard let self else { return }
            let menu = self.makeMenu(fromStatusBar: true)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self.ear.view)
        }
        placeIcon()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.placeIcon() }
        updateStatusIcon()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = Date().timeIntervalSince1970
            self.world.pollEvents(now: t)
            self.world.tick(now: t)
            self.world.persist()
            self.updateStatusIcon()
            self.rescueIfLost()
            // safety net: no toy window may outlive its game
            for stray in Toy.live where stray !== self.toy { stray.close() }
        }
    }

    /// The icon lives in the notch tab when a notch exists, in the menu bar otherwise.
    func placeIcon() {
        let inNotch = ear.place()
        statusItem.isVisible = !inNotch
        iconKey = ""
        updateStatusIcon()
    }

    func updateStatusIcon() {
        let now = Date().timeIntervalSince1970
        let full = world.pet.dead || world.isEgg ? -1 : world.full(at: now) / 100
        if ear.view.fullness != full { ear.view.fullness = full; ear.view.needsDisplay = true }
        let key = "\(view.mood)\(world.pet.species)\(world.pet.colorIndex)"
        guard key != iconKey else { return }
        iconKey = key
        let icon = view.menuBarIcon()
        statusItem.button?.image = icon
        ear.view.icon = icon
        ear.view.needsDisplay = true
    }

    @objc func statusClicked() {
        statusItem.menu = makeMenu(fromStatusBar: true)
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// The pet's middle is on no screen (thrown into a gap between monitors, a display unplugged): bring it back.
    func rescueIfLost() {
        guard !view.held else { return }
        let c = NSPoint(x: panel.frame.midX, y: panel.frame.minY + footOffset + 40 * CGFloat(world.save.scale))
        if NSScreen.screens.contains(where: { $0.frame.contains(c) }) { return }
        let scr = NSScreen.screens.min { hypot($0.frame.midX - c.x, $0.frame.midY - c.y) < hypot($1.frame.midX - c.x, $1.frame.midY - c.y) }
            ?? NSScreen.main!
        dropPet(at: NSPoint(x: min(max(c.x, scr.visibleFrame.minX + 80), scr.visibleFrame.maxX - 80),
                            y: scr.visibleFrame.minY + scr.visibleFrame.height * 0.4))
    }

    /// Puts the pet with its feet at `p` (global coordinates) and lets it fall to the floor there.
    func dropPet(at p: NSPoint) {
        let s = CGFloat(world.save.scale)
        panel.setFrameOrigin(NSPoint(x: p.x - W / 2 * s, y: p.y - footOffset + 2 * s))
        let floor = floorInfo().1
        lastFloor = floor
        air = max(0, p.y - floor)
        vx = 0; vy = 0; spinRate = 0; view.spin = 0
        act = "fall"
        panel.orderFrontRegardless()
        lastStep = Date().timeIntervalSince1970
    }

    /// Menu bar "Find": the pet appears under the cursor, on whatever screen you are, and drops to the floor.
    @objc func findAction() {
        let m = NSEvent.mouseLocation
        let scr = NSScreen.screens.first { $0.frame.contains(m) } ?? NSScreen.main!
        let vis = scr.visibleFrame
        if !roam { world.save.roam = true; world.dirty = true }
        dropPet(at: NSPoint(x: min(max(m.x, vis.minX + 80), vis.maxX - 80), y: min(m.y - 40, vis.maxY - 200)))
    }


    // MARK: walking

    /// The floor under the pet's feet: among the screens at its x, the highest floor that is not above the feet.
    /// Stacked monitors therefore act as solid floors and the pet can never fall through a screen edge.
    func floorInfo() -> (NSRect, CGFloat) {
        let cx = panel.frame.midX, feet = panel.frame.minY + footOffset
        let column = NSScreen.screens.filter { $0.frame.minX <= cx && cx <= $0.frame.maxX }
        let below = column.filter { $0.visibleFrame.minY <= feet + 4 }
        let scr = below.max { $0.visibleFrame.minY < $1.visibleFrame.minY }
            ?? column.min { $0.visibleFrame.minY < $1.visibleFrame.minY }
            ?? NSScreen.screens.min { abs($0.frame.midX - cx) < abs($1.frame.midX - cx) }
            ?? NSScreen.main!
        return (scr.visibleFrame, scr.visibleFrame.minY)
    }


    /// Cartoon gravity: real 9.81 m/s² at screen scale made a 3 cm pet drop like a stone,
    /// so the world is scaled up — the pet falls like a small animal, not a pebble.
    func gravity() -> CGFloat { 4200 * CGFloat(world.save.scale) }

    /// Velocity that lifts the pet `h` points (scaled with the pet's size).
    func hop(_ h: CGFloat) -> CGFloat { (2 * G * h * CGFloat(world.save.scale)).squareRoot() }

    /// Is there a screen right at this point? Lets a throw carry the pet to a monitor that really
    /// continues at the pet's height — never into the empty gap between offset monitors.
    func screenExists(x: CGFloat, y: CGFloat) -> Bool {
        NSScreen.screens.contains { $0.frame.contains(NSPoint(x: x, y: y)) }
    }

    func roamStep(dt: CGFloat, now: Double) {
        guard roam, !view.held else { view.walking = false; return }
        let s = CGFloat(world.save.scale)
        let (vis, floor) = floorInfo()
        G = gravity()
        toy?.g = G
        // keep the height absolute when the floor changes (moved to another screen)
        if let lf = lastFloor, lf != floor { air += lf - floor }
        lastFloor = floor
        let half = W / 2 * s
        let minC = vis.minX + 40 * s, maxC = vis.maxX - 40 * s   // bounds for the pet's center
        var cx = panel.frame.origin.x + half

        // gravity, flight and bounces
        let flying = air > 0 || vy > 0 || vx != 0
        if flying {
            vy -= G * dt
            vx *= pow(0.92, dt)                         // a little air drag
            air += vy * dt
            cx += vx * dt
            spinRate *= pow(0.6, dt)
            view.spin += spinRate * dt * 60 * 0.05
            // walls and ceiling of this screen; open sides lead to the next monitor
            let edgeL = vis.minX + 40 * s, edgeR = vis.maxX - 40 * s
            let body = floor + air + 50 * s   // the pet's middle
            if cx < edgeL && !screenExists(x: cx - 60 * s, y: body) { cx = edgeL; vx = abs(vx) * 0.5; spinRate = -spinRate }
            if cx > edgeR && !screenExists(x: cx + 60 * s, y: body) { cx = edgeR; vx = -abs(vx) * 0.5; spinRate = -spinRate }
            let ceiling = vis.maxY - floor - H * s
            if air > ceiling && vy > 0 { air = ceiling; vy = -vy * 0.4 }
            if air <= 0 {
                air = 0
                let impact = -vy
                if impact > 0 {
                    // bounce: restitution 0.55 for a soft creature; tiny bounces die out
                    view.land(impact / hop(220))
                    view.spin = atan2(sin(view.spin), cos(view.spin))   // land upright-ish, then settle
                    spinRate *= 0.4
                    vy = impact > hop(3) ? impact * 0.55 : 0
                    vx *= 0.75
                }
                if vy == 0 {
                    // sliding on the floor: friction μ≈0.5
                    let f = 0.5 * G * dt
                    vx = abs(vx) <= f ? 0 : vx - (vx > 0 ? f : -f)
                    view.spin *= pow(0.001, dt)
                    if vx == 0 { view.spin = 0 }
                }
                if vy == 0 && vx == 0 && act == "fall" { act = "idle"; actUntil = now + 1.5 }
            }
        } else if view.spin != 0 {
            view.spin = 0
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
        if partying && air == 0 && vy == 0 && m != "dead" && m != "egg" { vy = hop(62) }
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
                if mine && air == 0 && now > nextSearchHop { vy = hop(30); nextSearchHop = now + 1.1 }
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
                            if air == 0 { vy = hop(90); toy.kick(dir: Bool.random() ? 1 : -1); lastKick = now }
                        } else if toy.y < 30 {
                            toy.kick(dir: d >= 0 ? 1 : -1)
                            if air == 0 && Bool.random() { vy = hop(22) }
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
        if !flying { cx = min(max(cx, minC), maxC) }
        else if !screenExists(x: cx, y: floor + max(air, 0) + 50 * s) {
            cx = min(max(cx, minC), maxC)
            vx = -vx * 0.5
        }
        toy?.step(dt: dt, t: view.t, floor: floor, minX: vis.minX, maxX: vis.maxX)
        panel.setFrameOrigin(NSPoint(x: cx - half, y: floor + air - footOffset + 2 * s))
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
        toy?.close()   // picking the pet up mid-game left the old toy on screen for good
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

    /// Starts the show once the pet stands still on a floor: it hides, and the light panel plays it out.
    func evolveStep(_ dt: CGFloat) {
        if evolution == nil && evolveQueued && air == 0 && vy == 0 && !view.held,
           let form = world.pet.form, !world.pet.dead {
            evolveQueued = false
            endPlay()
            stopSearch()
            view.spin = 0
            vx = 0
            act = "idle"
            let s = CGFloat(world.save.scale)
            evolution = Evolution(pet: view, oldForm: nil, newForm: form, centerX: panel.frame.midX,
                                  floor: panel.frame.minY + footOffset - 2 * s, scale: s)
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
        }
        guard let e = evolution else { return }
        e.step(dt)
        if e.landed && panel.alphaValue == 0 {
            panel.alphaValue = 1
            panel.ignoresMouseEvents = false
            view.squashAmt = 0.25
            view.squashUntil = view.t + 0.22
            celebrate()
        }
        if e.isDone { e.close(); evolution = nil }
    }

    @objc func evolveAction() { evolveQueued = true }

    func endPlay() {
        toy?.close()
        toy = nil
        lastPlay = Date().timeIntervalSince1970
        if act == "play" { act = "idle"; actUntil = lastPlay + 3 }
    }

    @available(macOS 14, *)
    @objc func onDisplayFrame(_ link: CADisplayLink) { frame() }

    /// Frame rate for what is happening now: flight, drags and toys get every display frame,
    /// walking and eating 60 fps, rest 30 fps.
    var frameRate: Double {
        if air > 0 || vy != 0 || vx != 0 || view.held || toy != nil || !confetti.isEmpty || evolution != nil { return 1000 }
        if view.walking || view.searching || !view.drops.isEmpty || !view.pending.isEmpty
            || view.t < view.celebrateUntil || view.t < view.squashUntil { return 60 }
        return 30
    }

    func frame() {
        let t = Date().timeIntervalSince1970
        if t - lastStep < 1 / frameRate - 0.002 { return }
        let dt = min(0.05, t - lastStep)
        if evolution == nil || evolution!.landed { roamStep(dt: CGFloat(dt), now: t) }
        view.step(dt: dt)
        evolveStep(CGFloat(dt))
        lastStep = t
        if fpsLog {   // debug: CLAWDLING_FPSLOG=1 logs frames per second while something moves
            fpsFrames += 1
            if t - fpsSince >= 1 {
                if frameRate > 30 { NSLog("clawdling fps=%d rate=%.0f", fpsFrames, frameRate) }
                fpsFrames = 0
                fpsSince = t
            }
        }
    }
    let fpsLog = ProcessInfo.processInfo.environment["CLAWDLING_FPSLOG"] != nil
    var fpsFrames = 0, fpsSince = 0.0

    func applyScale() {
        let s = CGFloat(world.save.scale)
        let o = panel.frame.origin
        panel.setFrame(NSRect(x: o.x, y: o.y, width: W * s, height: H * s), display: true)
        view.frame = NSRect(x: 0, y: 0, width: W * s, height: H * s)
    }

    func makeMenu(fromStatusBar: Bool = false) -> NSMenu {
        let m = NSMenu()
        let p = world.pet
        let title: String
        if p.dead { title = "🪦 \(p.name)" }
        else if world.isEgg { title = "🥚 egg" }
        else { title = "\(p.name) — \(world.species.name)" + (p.form.map { " · \(FORM_NAME[$0]!)" } ?? "")
                      + " · \(Int(world.full(at: Date().timeIntervalSince1970)))% full" }
        let head = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        head.isEnabled = false
        m.addItem(head)
        m.addItem(.separator())
        if fromStatusBar {
            m.addItem(item(p.dead ? "Show the grave" : "Find \(world.isEgg ? "the egg" : p.name)", #selector(findAction)))
            m.addItem(.separator())
        }
        m.addItem(item("Stats…", #selector(statsAction)))
        m.addItem(item("Graveyard (\(world.save.graves.count))…", #selector(gravesAction)))
        if p.dead { m.addItem(item("Bury and take a new egg 🥚", #selector(reviveAction))) }
        let size = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (name, v) in [("Small", 0.75), ("Normal", 1.0), ("Large", 1.4)] {
            let i = item(name, #selector(scaleAction(_:)))
            i.representedObject = v
            i.state = world.save.scale == v ? .on : .off
            sub.addItem(i)
        }
        size.submenu = sub
        m.addItem(size)
        let walkItem = item("Walk around the screen", #selector(roamAction))
        walkItem.state = roam ? .on : .off
        m.addItem(walkItem)
        if p.form != nil && !p.dead && evolution == nil {
            m.addItem(item("Replay evolution ✨", #selector(evolveAction)))
        }
        if roam && toy == nil && !world.isEgg && !p.dead {
            m.addItem(item("Give a toy 🧶", #selector(toyAction)))
        }
        let tg = item("Telegram alerts", #selector(tgAction))
        tg.state = world.save.tg ? .on : .off
        m.addItem(tg)
        m.addItem(.separator())
        m.addItem(item("Quit", #selector(quitAction)))
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
            lines.append("Egg: \(Int(p.eggPoints)) of \(Int(HATCH_POINTS)) food to hatch")
        } else {
            let day = Int((now - (p.hatchedAt ?? now)) / 86400) + 1
            lines.append("Species: " + world.species.name + (p.form.map { ", form: " + FORM_NAME[$0]! } ?? ", evolves on day 7"))
            lines.append("Age: day \(day)")
            lines.append("Fullness: \(Int(world.full(at: now)))%")
            if !p.dead { lines.append("Starves in: \(max(0, Int(DEATH_HOURS) - ago)) h") }
        }
        lines.append("Last meal: " + (ago == 0 ? "just now" : "\(ago) h ago"))
        lines.append("Streak: \(world.streak) days in a row")
        lines.append("")
        lines.append("🍙 prompts \(c["prompt"] ?? 0)   🍪 finished tasks \(c["done"] ?? 0)")
        lines.append("🍎 edits \(c["edit"] ?? 0)   ☕️ commands \(c["bash"] ?? 0)")
        lines.append("🐟 web \(c["web"] ?? 0)   🎂 agents \(c["agent"] ?? 0)   🍬 other \(c["other"] ?? 0)")
        lines.append("Midnight snacks: \(p.night)")
        alert(p.dead ? "🪦 \(p.name)" : p.name, lines.joined(separator: "\n"))
    }

    @objc func gravesAction() {
        let g = world.save.graves
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        let text = g.isEmpty ? "Nobody has died yet. Keep it up." : g.reversed().map { gr in
            let sp = SPECIES.first(where: { $0.id == gr.species })?.name ?? gr.species
            let form = gr.form.map { " (\(FORM_NAME[$0] ?? $0))" } ?? ""
            return "🪦 \(gr.name), \(sp)\(form) — \(gr.days) days, \(f.string(from: Date(timeIntervalSince1970: gr.diedAt)))"
        }.joined(separator: "\n")
        alert("Graveyard", text)
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
        if !roam { endPlay() } else { act = "fall"; air = max(0, panel.frame.origin.y + footOffset - 2 * CGFloat(world.save.scale) - floorInfo().1) }
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
            g.cgContext.translateBy(x: CGFloat(i) * cw, y: ch + 2 + jump - (FOOT_PAD - 4))
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

// Debug: CLAWDLING_EARSHOT=/path.png renders the notch tab at three health levels (4× scale) and exits.
if let earPath = ProcessInfo.processInfo.environment["CLAWDLING_EARSHOT"] {
    let world = World()
    let pv = PetView(world: world)
    let k: CGFloat = 4, ew = NotchEar.width + 12 + 40, eh: CGFloat = 32
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ew * k * 3), pixelsHigh: Int(eh * k),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    hex(0x3a3f4b).setFill()   // a menu bar-ish grey behind it
    NSRect(x: 0, y: 0, width: ew * k * 3, height: eh * k).fill()
    for (i, f) in [0.9, 0.45, 0.15].enumerated() {
        let v = EarView(frame: NSRect(x: 0, y: 0, width: NotchEar.width + 12, height: eh))
        v.icon = pv.menuBarIcon()
        v.fullness = f
        g.cgContext.saveGState()
        g.cgContext.scaleBy(x: k, y: k)
        g.cgContext.translateBy(x: CGFloat(i) * ew + 10, y: 0)
        NSColor.black.setFill()
        NSRect(x: NotchEar.width, y: 0, width: 42, height: eh).fill()   // stand-in for the notch
        v.draw(v.bounds)
        g.cgContext.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: earPath))
    exit(0)
}

// Debug: CLAWDLING_ARTSHEET=/path.png renders every piece of pixel art (food, icons, toys, popper) and exits.
if let artPath = ProcessInfo.processInfo.environment["CLAWDLING_ARTSHEET"] {
    let names = ["rice", "apple", "coffee", "fish", "cake", "cookie", "candy", "heart", "zzz", "ball", "yarn", "butterfly", "popper"]
    let cw: CGFloat = 64, k: CGFloat = 2
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(cw * CGFloat(names.count) * k), pixelsHigh: Int(cw * k),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    g.cgContext.scaleBy(x: k, y: k)
    hex(0x2b3040).setFill()
    NSRect(x: 0, y: 0, width: cw * CGFloat(names.count), height: cw).fill()
    for (i, n) in names.enumerated() { drawArt(n, px: 3.5, center: NSPoint(x: CGFloat(i) * cw + cw / 2, y: cw / 2)) }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: artPath))
    exit(0)
}

// Debug: CLAWDLING_SHEET=/path.png renders every species × form into one sheet and exits.
if let sheetPath = ProcessInfo.processInfo.environment["CLAWDLING_SHEET"] {
    let cols = SPECIES.count, moods: [(String, String?)] = [
        ("egg", nil), ("happy", nil), ("happy", "hacker"), ("happy", "builder"), ("happy", "explorer"),
        ("happy", "owl"), ("happy", "queen"), ("hungry", nil), ("starving", nil), ("dead", nil),
        ("search", nil), ("party", nil), ("spin", nil)]
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
            if mood == "spin" { v.spin = CGFloat(ci) * .pi / 6 + .pi / 4 }   // tumble angles must stay inside the window
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

// Debug: CLAWDLING_EVOFRAMES=/dir renders the evolution show at 30 fps (evo_000.png …, transparent).
if let dir = ProcessInfo.processInfo.environment["CLAWDLING_EVOFRAMES"] {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let world = World()
    let form = ProcessInfo.processInfo.environment["CLAWDLING_EVOFORM"] ?? world.pet.form ?? "owl"
    let pv = PetView(world: world)
    let fw: CGFloat = 960, fh: CGFloat = 640
    let ev = EvolveView(pet: pv, oldForm: nil, newForm: form, frame: NSRect(x: 0, y: 0, width: fw, height: fh))
    ev.cx = fw / 2; ev.floorY = fh - 40; ev.s = 1
    var i = 0
    while ev.age < EvolveView.end {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(fw), pixelsHigh: Int(fh), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let g = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = g
        g.cgContext.translateBy(x: 0, y: fh)
        g.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: g.cgContext, flipped: true)
        ev.draw(ev.bounds)
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir + String(format: "/evo_%03d.png", i)))
        ev.step(1.0 / 30)
        i += 1
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
