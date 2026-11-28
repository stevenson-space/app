import SwiftUI

extension View {
    /// Makes Return act as a key on a vertical text field, where it would
    /// otherwise add a line break. The field keeps its text on one line of
    /// content and `action` runs instead.
    ///
    /// A vertical field is the reason to want this: unlike a single-line one,
    /// it doesn't give up the keyboard when Return is pressed, so focus can
    /// move to another field without the keyboard dropping away and coming back.
    func onReturn(in text: Binding<String>, perform action: @escaping () -> Void) -> some View {
        onChange(of: text.wrappedValue) { old, new in
            guard new.contains(where: \.isNewline) else { return }
            let typed = insertedText(from: old, to: new)
            if !typed.isEmpty && typed.allSatisfy(\.isNewline) {
                // Return, wherever the cursor is and even over a selection:
                // keep the text as it was.
                text.wrappedValue = old
                action()
            } else {
                // Pasted text that came with line breaks.
                text.wrappedValue = new.split(whereSeparator: \.isNewline).joined(separator: " ")
            }
        }
    }
}

/// The text an edit put in place of whatever it replaced, found by trimming
/// what the old and new strings share at each end.
private func insertedText(from old: String, to new: String) -> Substring {
    let prefix = zip(old, new).prefix { $0 == $1 }.count
    let suffix = zip(old.reversed(), new.reversed())
        .prefix(min(old.count, new.count) - prefix)
        .prefix { $0 == $1 }
        .count
    return new.dropFirst(prefix).dropLast(suffix)
}
