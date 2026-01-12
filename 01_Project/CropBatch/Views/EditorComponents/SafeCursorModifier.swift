import SwiftUI

/// A ViewModifier that safely manages cursor push/pop with proper cleanup on disappear.
/// Prevents cursor stack imbalance if view disappears while hovering.
struct SafeCursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var cursorPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    if !cursorPushed {
                        cursor.push()
                        cursorPushed = true
                    }
                } else {
                    if cursorPushed {
                        NSCursor.pop()
                        cursorPushed = false
                    }
                }
            }
            .onDisappear {
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
    }
}

extension View {
    /// Applies a cursor on hover with safe cleanup on view disappear.
    /// Prevents cursor stack imbalance if view disappears mid-hover.
    func cursor(_ cursor: NSCursor) -> some View {
        self.modifier(SafeCursorModifier(cursor: cursor))
    }
}
