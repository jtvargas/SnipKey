//
//  AccentMap.swift
//  SnipKeyboard
//
//  Long-press secondary character map — matches Apple's en-US iOS keyboard set.
//

import Foundation

enum AccentMap {

    /// Secondary characters revealed by long-pressing a base character.
    /// The base character is NOT included in the returned list — the menu always
    /// renders [base] + alternates so the user can still select the base.
    static let alternates: [Character: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā", "ª"],
        "c": ["ç", "ć", "č"],
        "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
        "i": ["ì", "į", "ī", "í", "ï", "î"],
        "l": ["ł"],
        "n": ["ñ", "ń"],
        "o": ["ô", "ö", "ò", "ó", "œ", "ø", "ō", "õ"],
        "s": ["ß", "ś", "š"],
        "u": ["û", "ü", "ù", "ú", "ū"],
        "y": ["ÿ"],
        "z": ["ž", "ź", "ż"],
        "$": ["¢", "£", "€", "¥", "₩", "₽"],
        "&": ["§"],
        "'": ["\"", "“", "”", "‘", "’", "«", "»"],
        ".": ["…"],
        "?": ["¿"],
        "!": ["¡"],
        "-": ["–", "—", "•"],
        "/": ["\\"],
    ]

    /// Domain alternates for a long-press on the "." key in URL / email fields (native iOS).
    /// `.com` is first so it's the default selection. Multi-character entries trigger the
    /// wider action slots in `KeyboardCalloutView.configureActionsMode`.
    static func domainMenu() -> [String] {
        [".com", ".net", ".org", ".edu", ".io"]
    }

    /// Returns the menu entries for a long-press, with the base character first.
    /// Casing is preserved using the same shift state as the base character.
    static func menu(for base: String, uppercased: Bool) -> [String]? {
        guard let scalar = base.first else { return nil }
        let key = Character(scalar.lowercased())
        guard let alts = alternates[key] else { return nil }
        let casedBase = uppercased ? base.uppercased() : base.lowercased()
        let casedAlts = alts.map { uppercased ? $0.uppercased() : $0 }
        return [casedBase] + casedAlts
    }
}
