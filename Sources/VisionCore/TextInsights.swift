import Foundation

/// 用系统的数据检测器从文本里找出链接、电话、日期和地址
public enum TextInsights {
    public static func detect(in text: String) -> [TextInsight] {
        guard !text.isEmpty else { return [] }
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber, .date, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }

        let source = text as NSString
        var insights: [TextInsight] = []
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: source.length))
        for match in matches {
            let value = source.substring(with: match.range)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }

            let insight: TextInsight
            switch match.resultType {
            case .link:
                insight = TextInsight(kind: .link, value: value, url: match.url?.absoluteString)
            case .phoneNumber:
                let digits = (match.phoneNumber ?? value).filter { $0.isNumber || $0 == "+" }
                insight = TextInsight(kind: .phoneNumber, value: value, url: digits.isEmpty ? nil : "tel:\(digits)")
            case .date:
                insight = TextInsight(kind: .date, value: value, url: nil)
            case .address:
                let query = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                insight = TextInsight(kind: .address, value: value, url: query.map { "https://maps.apple.com/?q=\($0)" })
            default:
                continue
            }
            if !insights.contains(insight) {
                insights.append(insight)
            }
        }
        return insights
    }
}
