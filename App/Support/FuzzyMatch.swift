import Foundation

/// Lets Helper match words that were misheard or mispronounced ("you tube" -> "youtube", "help her" -> "helper").
enum FuzzyMatch {
    /// Lowercase letters and digits only, accents removed.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Number of single-letter edits needed to turn one word into the other.
    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[y.count]
    }

    /// 1.0 means identical, 0.0 means nothing alike.
    static func similarity(_ a: String, _ b: String) -> Double {
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(distance(a, b)) / Double(longest)
    }
}
