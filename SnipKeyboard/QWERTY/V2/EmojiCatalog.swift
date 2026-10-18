import Foundation

/// Immutable Unicode 16.0 data, decoded once off the UI thread. See the bundled
/// emoji-unicode-license.txt and scripts/generate_emoji_catalog.py for provenance.
final class EmojiCatalog: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let text: String
        let name: String
        let group: Int
        let base: Int
        let variants: [Int]
        let keywords: String

        enum CodingKeys: String, CodingKey {
            case text = "t", name = "n", group = "g", base = "b"
            case variants = "v", keywords = "k"
        }
    }

    struct Group: Decodable, Sendable {
        let name: String
        let symbol: String
        let entries: [Int]

        enum CodingKeys: String, CodingKey {
            case name = "n", symbol = "s", entries = "e"
        }
    }

    let version: String
    let groups: [Group]
    let entries: [Entry]
    /// Recents plus these eight categories fit the native-style footer. Source
    /// groups remain intact for Unicode provenance and keyword search ordering.
    let browseGroups: [Group]
    let indexByText: [String: Int]
    private let baseEntries: [Int]

    enum CodingKeys: String, CodingKey {
        case version, groups, entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        groups = try container.decode([Group].self, forKey: .groups)
        entries = try container.decode([Entry].self, forKey: .entries)
        browseGroups = [
            Group(name: "Smileys & People", symbol: "face.smiling", entries: groups[0].entries + groups[1].entries),
            Group(name: groups[2].name, symbol: "pawprint", entries: groups[2].entries),
            Group(name: groups[3].name, symbol: "carrot", entries: groups[3].entries),
            Group(name: groups[5].name, symbol: "soccerball", entries: groups[5].entries),
            groups[4], groups[6], groups[7], groups[8]
        ]
        indexByText = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.text, $0.offset) })
        baseEntries = groups.flatMap(\.entries)
    }

    // Both the browser's detached task and the prediction queue share this one decode.
    // Keep the Result private so all access enforces the off-main loading contract.
    private static let bundled: Result<EmojiCatalog, Error> = Result {
        guard let url = Bundle.main.url(forResource: "emoji-en", withExtension: "plist") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try load(from: url)
    }

    static func loadBundled() throws -> EmojiCatalog {
        precondition(!Thread.isMainThread, "Load the emoji catalog off the main thread")
        return try bundled.get()
    }

    static func load(from url: URL) throws -> EmojiCatalog {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try PropertyListDecoder().decode(EmojiCatalog.self, from: data)
    }

    /// The bounded result set contains indices, not copied entry objects or views.
    /// Normal searches omit tone duplicates; an explicit tone query includes them.
    func search(_ query: String, limit: Int = 80) -> [Int] {
        guard limit > 0 else { return [] }
        let normalized = Self.normalize(query)
        let tokens = normalized.split(separator: " ")
        guard !tokens.isEmpty else { return [] }
        let includesTones = tokens.contains { token in
            token == "skin" || token == "tone" || token == "light" || token == "medium" || token == "dark"
        }
        var exact: [Int] = []
        var leading: [Int] = []
        var other: [Int] = []
        exact.reserveCapacity(1)
        leading.reserveCapacity(min(limit, 16))
        other.reserveCapacity(limit)
        func consider(_ index: Int) {
            let entry = entries[index]
            guard tokens.allSatisfy({ entry.keywords.contains($0) }) else { return }
            if entry.name == normalized {
                exact.append(index)
            } else if entry.keywords.hasPrefix(normalized), leading.count < limit {
                leading.append(index)
            } else if other.count < limit {
                other.append(index)
            }
        }
        if includesTones {
            for index in entries.indices {
                if index.isMultiple(of: 64), Task<Never, Never>.isCancelled { return [] }
                consider(index)
            }
        } else {
            for (offset, index) in baseEntries.enumerated() {
                if offset.isMultiple(of: 64), Task<Never, Never>.isCancelled { return [] }
                consider(index)
            }
        }
        var result = Array(exact.prefix(limit))
        result.reserveCapacity(limit)
        result.append(contentsOf: leading.prefix(limit - result.count))
        result.append(contentsOf: other.prefix(limit - result.count))
        return result
    }

    /// Inline shortcodes have no display limit and always omit skin-tone variants.
    /// Unicode names/keywords remain authoritative; these small aliases cover common
    /// Slack spellings whose names differ from Unicode (not a full Slack alias table).
    private static let shortcodeAliases: [String: [String]] = [
        "😄": ["smile"], "😃": ["smiley"], "😏": ["smirk"],
        "😀": ["grinning"], "😁": ["grin"], "😂": ["joy"],
        "🤣": ["rofl"], "😊": ["blush"], "🙂": ["slightly smiling face"],
        "🙃": ["upside down face"], "😉": ["wink"], "😌": ["relieved"],
        "😍": ["heart eyes"], "🥰": ["smiling face with 3 hearts"],
        "😘": ["kissing heart"], "😗": ["kissing"], "😚": ["kissing closed eyes"],
        "😙": ["kissing smiling eyes"], "😎": ["sunglasses"], "🤓": ["nerd face"],
        "😛": ["stuck out tongue"], "😜": ["stuck out tongue winking eye"],
        "😝": ["stuck out tongue closed eyes"], "😆": ["laughing", "satisfied"],
        "😢": ["cry"], "😭": ["sob"], "😠": ["angry"], "😡": ["rage"],
        "😱": ["scream"], "😴": ["sleeping"], "😪": ["sleepy"],
        "😐": ["neutral face"], "😑": ["expressionless"], "😕": ["confused"],
        "😔": ["pensive"], "😞": ["disappointed"], "😅": ["sweat smile"],
        "😇": ["innocent"], "🤔": ["thinking face", "thinking"],
        "🤗": ["hugging face"], "🤩": ["star struck"], "🥳": ["partying face"],
        "👍": ["thumbsup", "thumbs up", "+1"], "👎": ["thumbsdown", "thumbs down", "-1"],
        "👊": ["facepunch", "punch"], "✊": ["fist"], "✌️": ["v"],
        "👋": ["wave"], "👏": ["clap"], "🙌": ["raised hands"], "🙏": ["pray"],
        "💪": ["muscle"], "💩": ["poop", "shit", "hankey"],
        "❤️": ["heart"], "💔": ["broken heart"], "💯": ["100"],
        "🔥": ["fire"], "🎉": ["tada"], "💥": ["boom", "collision"],
        "✅": ["white check mark"], "❌": ["x"],
        "🚀": ["rocket"], "💻": ["computer"], "📱": ["iphone"],
        "⚠️": ["warning"], "🏳️‍🌈": ["rainbow flag"]
    ]

    func searchShortcodes(_ query: String) -> [Int] {
        guard !query.isEmpty else { return baseEntries }
        // Normalization treats underscores/hyphens as spaces, except signed aliases.
        let normalized: String
        if (query.first == "+" || query.first == "-"),
           query.dropFirst().allSatisfy({ $0.isNumber }) {
            normalized = query
        } else {
            normalized = Self.normalize(query)
        }
        guard !normalized.isEmpty else { return [] }
        let tokens = normalized.split(separator: " ")
        var exact: [Int] = []
        var leading: [Int] = []
        var other: [Int] = []
        for index in baseEntries {
            let entry = entries[index]
            let aliases = Self.shortcodeAliases[entry.text]
            let exactAlias = aliases?.contains(normalized) == true
            let leadingAlias = aliases?.contains(where: { $0.hasPrefix(normalized) }) == true
            let keywordMatch = tokens.allSatisfy { entry.keywords.contains($0) }
            guard exactAlias || leadingAlias || keywordMatch else { continue }
            if exactAlias || (keywordMatch && Self.normalize(entry.name) == normalized) {
                exact.append(index)
            } else if leadingAlias || entry.keywords.hasPrefix(normalized) {
                leading.append(index)
            } else {
                other.append(index)
            }
        }
        // Each base index is visited once, preserving Unicode order within each rank.
        exact.append(contentsOf: leading)
        exact.append(contentsOf: other)
        return exact
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// A local mirror preserves recents when Full Access (and therefore shared-container
/// access for a keyboard extension) is disabled. Emoji browsing never requires it.
@MainActor
final class EmojiRecentsStore {
    static let capacity = 40
    private static let key = "emoji.recentSequences.v1"
    private let sharedDefaults: UserDefaults?
    private let localDefaults: UserDefaults
    private var allowsSharedAccess = false
    private(set) var sequences: [String] = []

    init(sharedDefaults: UserDefaults? = UserDefaults(suiteName: "group.snipkey"),
         localDefaults: UserDefaults = .standard) {
        self.sharedDefaults = sharedDefaults
        self.localDefaults = localDefaults
    }

    func reload(allowSharedAccess: Bool) {
        allowsSharedAccess = allowSharedAccess
        let local = localDefaults.stringArray(forKey: Self.key) ?? []
        let shared = allowSharedAccess ? sharedDefaults?.stringArray(forKey: Self.key) ?? [] : []
        var seen = Set<String>()
        sequences = (local + shared).filter { !$0.isEmpty && seen.insert($0).inserted }
        if sequences.count > Self.capacity {
            sequences.removeLast(sequences.count - Self.capacity)
        }
    }

    func record(_ sequence: String) {
        guard !sequence.isEmpty else { return }
        sequences.removeAll { $0 == sequence }
        sequences.insert(sequence, at: 0)
        if sequences.count > Self.capacity { sequences.removeLast() }
        localDefaults.set(sequences, forKey: Self.key)
        if allowsSharedAccess { sharedDefaults?.set(sequences, forKey: Self.key) }
    }
}
