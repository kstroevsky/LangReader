import SwiftUI
import LeafReaderCore

/// SwiftUI owns the low-frequency chrome around the native note editor.
///
/// The rich text surface and formatting toolbar remain AppKit because they
/// depend on NSTextView selection, attributed-string editing and the existing
/// floating AI actions. This view owns only presentation of the model-backed
/// header and metadata, so changing note state no longer rebuilds AppKit
/// labels and stacks by hand.
struct ReadingNoteEditorChromeView: View {
    let model: ReadingNoteEditorModel
    let theme: ReaderTheme
    let onShowNotes: () -> Void
    let onMore: () -> Void

    private var palette: ReadingNotePalette { ReadingNotePalette(theme: theme) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    chromeButton(symbol: "sidebar.right", label: AppText.localized("显示笔记列表", "Show notes"), action: onShowNotes)
                    chromeButton(symbol: "ellipsis.curlybraces", label: AppText.localized("更多笔记操作", "More note actions"), action: onMore)
                }
                .padding(.horizontal, 22)

                HStack(spacing: 8) {
                    Image(systemName: "pencil.and.list.clipboard")
                        .font(.system(size: 16, weight: .semibold))
                    Text(AppText.localized("阅读笔记", "Reading Note"))
                        .font(.system(size: 19, weight: .semibold))
                }
                .foregroundStyle(palette.primaryText)
            }
            .padding(.top, 18)
            .frame(height: 74, alignment: .top)

            metadata
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private var metadata: some View {
        HStack(spacing: 18) {
            metadataItem(
                title: AppText.localized("书籍", "Book"),
                value: model.note.documentTitle
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            metadataItem(
                title: AppText.localized("位置", "Location"),
                value: model.locationText
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            metadataItem(
                title: AppText.localized("创建时间", "Created"),
                value: model.createdAtText
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 26)
        .frame(height: 42)
        .background(palette.insetBackground, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 22)
    }

    private func metadataItem(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(palette.primaryText)
    }

    private func chromeButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .frame(width: 34, height: 34)
                .background(palette.secondaryButtonBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(palette.primaryText.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Status and word-count labels are deliberately separate hosting views so
/// the native editor toolbar keeps its original layout and first-responder
/// behaviour. Both are read-only projections of the same editor model.
struct ReadingNoteEditorStatusView: View {
    let model: ReadingNoteEditorModel
    let theme: ReaderTheme

    var body: some View {
        Text(model.statusMessage)
            .font(.system(size: 12))
            .foregroundStyle(ReadingNotePalette(theme: theme).primaryText.opacity(0.72))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
    }
}

struct ReadingNoteEditorWordCountView: View {
    let model: ReadingNoteEditorModel
    let theme: ReaderTheme

    var body: some View {
        Text(model.wordCountText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ReadingNotePalette(theme: theme).primaryText.opacity(0.58))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .allowsHitTesting(false)
    }
}
