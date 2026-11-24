import Foundation

/// 把句子里出现的词形还原成可能的词典原形，用来在词库中查找。
/// 只做规则化的常见变形，不求语言学上的完备。
public enum Lemmatizer {
    /// 返回按优先级排列的候选写法，第一个总是小写的原词。
    public static func candidates(for token: String) -> [String] {
        var word = token.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted)
        guard !word.isEmpty else { return [] }

        var result: [String] = []
        func add(_ candidate: String) {
            if candidate.count >= 2, !result.contains(candidate) { result.append(candidate) }
        }
        add(word)

        // 所有格
        for suffix in ["'s", "’s"] where word.hasSuffix(suffix) {
            word = String(word.dropLast(suffix.count))
            add(word)
        }

        func stem(_ suffix: String) -> String? {
            word.hasSuffix(suffix) && word.count > suffix.count + 1 ? String(word.dropLast(suffix.count)) : nil
        }
        func undouble(_ base: String) -> String? {
            let characters = Array(base)
            guard characters.count >= 3, characters[characters.count - 1] == characters[characters.count - 2] else {
                return nil
            }
            return String(characters.dropLast())
        }

        // 复数与第三人称
        if let base = stem("ies") { add(base + "y") }
        if let base = stem("ves") { add(base + "f"); add(base + "fe") }
        if let base = stem("es") { add(base); add(base + "e") }
        if let base = stem("s"), !word.hasSuffix("ss") { add(base) }

        // 进行时
        if let base = stem("ing") {
            add(base)
            add(base + "e")
            if let single = undouble(base) { add(single) }
        }

        // 过去式
        if let base = stem("ied") { add(base + "y") }
        if let base = stem("ed") {
            add(base)
            add(base + "e")
            if let single = undouble(base) { add(single) }
        }

        // 比较级与副词
        if let base = stem("er") { add(base); add(base + "e") }
        if let base = stem("est") { add(base); add(base + "e") }
        if let base = stem("ly") { add(base) }

        return result
    }

    /// 把一行文字拆成单词，保留每个词在原字符串中的范围
    public static func words(in text: String) -> [(word: String, range: Range<String.Index>)] {
        var result: [(String, Range<String.Index>)] = []
        text.enumerateSubstrings(in: text.startIndex ..< text.endIndex, options: .byWords) { substring, range, _, _ in
            guard let substring, substring.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
                return
            }
            result.append((substring, range))
        }
        return result
    }
}
