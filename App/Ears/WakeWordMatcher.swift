import Foundation

/// Spots the wake phrase in what the microphone heard, even when speech recognition
/// writes it slightly wrong ("hey help her", "a helper", "hey helpr").
enum WakeWordMatcher {
    /// If the wake phrase was heard, returns whatever was said after it (may be empty).
    static func remainder(after phrase: String, in text: String, sensitivity: WakeSensitivity) -> String? {
        let target = FuzzyMatch.normalize(phrase)
        guard !target.isEmpty else { return nil }
        let phraseWords = phrase.split(separator: " ")
        let wordCount = max(1, phraseWords.count)
        let keyWord = FuzzyMatch.normalize(String(phraseWords.last ?? ""))
        let allowed = sensitivity.allowedEdits(forLength: target.count)

        var words: [(word: String, range: Range<String.Index>)] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, range, _, _ in
            if let word { words.append((FuzzyMatch.normalize(word), range)) }
        }

        for start in words.indices {
            // Try 1-3 word windows and keep the closest one, so "hey help her" uses all three words.
            var best: (distance: Int, end: Int)?
            for length in max(1, wordCount - 1)...(wordCount + 1) {
                let end = start + length
                guard end <= words.count else { break }
                let joined = words[start..<end].map(\.word).joined()
                let distance = FuzzyMatch.distance(joined, target)
                if distance <= (best?.distance ?? Int.max) { best = (distance, end) }
            }
            if let best, best.distance <= allowed {
                return rest(of: text, after: words[best.end - 1].range.upperBound)
            }
            if sensitivity == .relaxed, keyWord.count >= 4, FuzzyMatch.distance(words[start].word, keyWord) <= 1 {
                return rest(of: text, after: words[start].range.upperBound)
            }
        }
        return nil
    }

    private static func rest(of text: String, after index: String.Index) -> String {
        String(text[index...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
