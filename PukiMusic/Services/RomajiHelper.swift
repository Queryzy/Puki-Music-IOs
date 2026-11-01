import Foundation

/// Helper transliterasi CJK (Jepang Kanji/Kana, Korea Hangul, dan Mandarin Hanzi Pinyin) ke Romaji Latin
/// Menggunakan CoreFoundation / CFStringTransform native iOS yang sangat cepat dan akurat.
public final class RomajiHelper {
    public static let shared = RomajiHelper()
    private init() {}

    // Revised Romanization of Korean (Hangul Syllables 0xAC00 - 0xD7A3)
    private let choseong: [String] = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"]
    private let jungseong: [String] = ["a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"]
    private let jongseong: [String] = ["", "k", "k", "ks", "n", "nj", "nh", "t", "l", "lg", "lm", "lb", "ls", "lt", "lp", "lh", "m", "p", "ps", "s", "ss", "ng", "j", "ch", "k", "t", "p", "h"]

    public func containsCJK(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let val = scalar.value
            // Hiragana, Katakana, CJK Unified, Hangul
            if (val >= 0x3040 && val <= 0x30FF) ||
               (val >= 0x4E00 && val <= 0x9FFF) ||
               (val >= 0x3400 && val <= 0x4DBF) ||
               (val >= 0xAC00 && val <= 0xD7AF) {
                return true
            }
        }
        return false
    }

    public func hangulToRomaji(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            let code = Int(scalar.value)
            if code >= 0xAC00 && code <= 0xD7A3 {
                let sIndex = code - 0xAC00
                let lIndex = sIndex / (21 * 28)
                let vIndex = (sIndex % (21 * 28)) / 28
                let tIndex = sIndex % 28

                result += choseong[lIndex]
                result += jungseong[vIndex]
                result += jongseong[tIndex]
            } else {
                result.append(Character(scalar))
            }
        }
        return result
    }

    /// Mengubah teks CJK ke huruf Latin Romaji (1:1 Android & Windows)
    public func toRomaji(_ text: String) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        // 1. Ubah Hangul Korea
        let koreanProcessed = hangulToRomaji(text)

        // 2. Gunakan CFStringTransform bawaan iOS untuk transliterasi Kanji/Kana/Hanzi ke Latin
        let mutableString = NSMutableString(string: koreanProcessed) as CFMutableString
        
        // Transform Any to Latin (mandarin pinyin + japanese romaji)
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        // Strip combining diacritics / tone marks (contoh: ā -> a, é -> e) agar bersih
        CFStringTransform(mutableString, nil, kCFStringTransformStripCombiningMarks, false)

        let latin = mutableString as String
        return latin.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
