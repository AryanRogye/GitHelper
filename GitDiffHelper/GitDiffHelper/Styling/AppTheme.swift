import AppKit
import SwiftUI

// Shared visual constants and typography scales for diff and commit-tree views.
enum NativeTheme {
    static let windowTop = Color(nsColor: .windowBackgroundColor)
    static let windowBottom = Color(nsColor: .underPageBackgroundColor)
    static let sidebarTop = Color(nsColor: .windowBackgroundColor)
    static let sidebarBottom = Color(nsColor: .underPageBackgroundColor).opacity(0.92)
    static let sidebarSearchBackground = Color(nsColor: .controlBackgroundColor).opacity(0.42)
    static let sidebarSearchBorder = Color(nsColor: .separatorColor).opacity(0.34)
    static let sidebarIconBase = Color(nsColor: .controlBackgroundColor).opacity(0.22)
    static let sidebarIconHover = Color(nsColor: .selectedContentBackgroundColor).opacity(0.2)
    static let sidebarIconBorder = Color(nsColor: .separatorColor).opacity(0.35)
    static let field = Color(nsColor: .textBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let seenBorder = Color.accentColor.opacity(0.9)
    static let topPathText = Color(nsColor: .labelColor).opacity(0.84)
    static let fileListPrimary = Color.primary.opacity(0.9)
    static let headerRow = Color(nsColor: .underPageBackgroundColor)
    static let fileCardBackground = Color(nsColor: .textBackgroundColor)
    static let contextBackground = Color(nsColor: .textBackgroundColor)
    static let lineNumber = Color(nsColor: .secondaryLabelColor)
    static let placeholderLineNumber = Color(nsColor: .secondaryLabelColor).opacity(0.48)
    static let deleteLineNumber = Color(nsColor: .systemRed).opacity(0.72)
    static let addLineNumber = Color(nsColor: .systemGreen).opacity(0.72)
    static let deleteLineNumberBackground = Color(nsColor: .systemRed).opacity(0.11)
    static let addLineNumberBackground = Color(nsColor: .systemGreen).opacity(0.11)
    static let lineNumberGutter = Color(nsColor: .underPageBackgroundColor).opacity(0.92)
    static let hunkHeaderText = Color(nsColor: .secondaryLabelColor)
    static let hunkHeaderBackground = Color(nsColor: .underPageBackgroundColor).opacity(0.7)
    static let readableSecondary = Color(nsColor: .secondaryLabelColor)
    static let metaText = Color(nsColor: .tertiaryLabelColor)
    static let metaBackground = Color(nsColor: .quaternaryLabelColor).opacity(0.08)
    static let deleteBackground = Color(nsColor: .systemRed).opacity(0.075)
    static let deleteMarker = Color(nsColor: .systemRed).opacity(0.60)
    static let addBackground = Color(nsColor: .systemGreen).opacity(0.075)
    static let addMarker = Color(nsColor: .systemGreen).opacity(0.60)
    static let placeholderBackground = Color(nsColor: .controlBackgroundColor).opacity(0.55)
    static let deletePlaceholderBackground = Color(nsColor: .systemRed).opacity(0.028)
    static let addPlaceholderBackground = Color(nsColor: .systemGreen).opacity(0.028)
    static let gutterDelete = Color(nsColor: .systemRed).opacity(0.045)
    static let gutterAdd = Color(nsColor: .systemGreen).opacity(0.045)
    static let gutterContext = Color(nsColor: .controlBackgroundColor).opacity(0.4)
    static let gutterAccent = Color.accentColor.opacity(0.2)
    static let centerGuide = Color.accentColor.opacity(0.2)
    static let sideGuides = Color(nsColor: .separatorColor).opacity(0.28)
    static let bridgeRibbon = Color.accentColor
}

enum DiffGridStyle {
    static let baseRowHeight: CGFloat = 25
    static let numberGutterWidth: CGFloat = 56
    static let markerColumnWidth: CGFloat = 16
    static let gutterWidth: CGFloat = 64
    static let gridLine = NativeTheme.border
}

struct CommitTreeTypography {
    static let defaultScale: CGFloat = 1.0
    static let minScale: CGFloat = 0.75
    static let maxScale: CGFloat = 1.8
    static let scaleStep: CGFloat = 0.1

    let scale: CGFloat

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    private var clampedScale: CGFloat {
        Self.clamp(scale)
    }

    var laneWidth: CGFloat {
        18 * clampedScale
    }

    var laneLeadingInset: CGFloat {
        10 * clampedScale
    }

    var branchLineWidth: CGFloat {
        max(1.7, 2.2 * clampedScale)
    }

    var guideLineWidth: CGFloat {
        max(0.75, 1.0 * clampedScale)
    }

    var nodeDiameter: CGFloat {
        max(8, 11 * clampedScale)
    }

    var nodeStrokeWidth: CGFloat {
        max(0.8, 1.0 * clampedScale)
    }

    var rowHorizontalPadding: CGFloat {
        10 * clampedScale
    }

    var rowVerticalPadding: CGFloat {
        max(7, 8 * clampedScale)
    }

    var hashFontSize: CGFloat {
        11 * clampedScale
    }

    var subjectFontSize: CGFloat {
        13 * clampedScale
    }

    var authorFontSize: CGFloat {
        11 * clampedScale
    }

    var metaFontSize: CGFloat {
        10 * clampedScale
    }
}

struct DiffTypography {
    static let defaultScale: CGFloat = 1.0
    static let minScale: CGFloat = 0.75
    static let maxScale: CGFloat = 1.8
    static let scaleStep: CGFloat = 0.1

    let scale: CGFloat

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    private var clampedScale: CGFloat {
        Self.clamp(scale)
    }

    var rowHeight: CGFloat {
        max(19, ceil(DiffGridStyle.baseRowHeight * clampedScale))
    }

    var hunkHeaderFontSize: CGFloat {
        11 * clampedScale
    }

    var lineNumberFontSize: CGFloat {
        11 * clampedScale
    }

    var markerFontSize: CGFloat {
        12 * clampedScale
    }

    var lineTextFontSize: CGFloat {
        12 * clampedScale
    }
}

extension View {
    func glassCard() -> some View {
        self
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(NativeTheme.border.opacity(0.65), lineWidth: 1)
            )
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
    }
}
