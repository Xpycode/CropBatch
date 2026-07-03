import Foundation
import HelpMenu

/// CropBatch's help content, loaded from the bundled `help-manifest.json`
/// (+ the `.md` files in this Help folder). Edit the markdown to change help —
/// no recompiling of the HelpMenu package required.
enum CropBatchHelp {
    static let content: HelpContent = {
        do {
            return try HelpContent(manifest: "help-manifest", in: .main)
        } catch {
            // Manifest missing/unreadable: fall back to a minimal in-app topic
            // so the Help menu still works.
            return HelpContent(
                topics: [
                    HelpTopic(
                        id: "help",
                        title: "Help",
                        markdown: "# CropBatch Help\n\nHelp content could not be loaded from the app bundle."
                    )
                ],
                windowTitle: "CropBatch Help"
            )
        }
    }()
}
