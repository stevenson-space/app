import Foundation

public extension ResolvedBlock {
    /// The physical period this block occupies ("2", "4B", "3–4A"),
    /// independent of the class name; nil outside the numbered periods.
    var periodLabel: String? {
        spanLabel ?? periodID.periodNumber.map(String.init)
    }
}

public extension DayTimeline {
    /// The physical period a moment occupies, for every kind of span: one
    /// block keeps its own label; a merged run of free blocks reads from its
    /// first block's start to its last block's end ("6–7", "4B–5"), in the
    /// same form the resolver gives a 1½-period class. Nil when no member is
    /// a numbered period.
    func periodLabel(for span: ResolvedSpan) -> String? {
        let labels = blocks
            .filter { span.blockIDs.contains($0.id) }
            .compactMap(\.periodLabel)
        guard let first = labels.first, let last = labels.last else { return nil }
        guard labels.count > 1 else { return first }
        let start = first.split(separator: "–").first.map(String.init) ?? first
        let end = last.split(separator: "–").last.map(String.init) ?? last
        return start == end ? start : "\(start)–\(end)"
    }
}
