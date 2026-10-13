//
//  IIDChip.swift
//  GitlabMenubar
//

import SwiftUI

/// MR (`!605`) / issue (`#501`) number as a solid accent capsule, so it stands out when scanning lists.
struct IIDChip: View {
    enum Kind {
        case mergeRequest, issue

        var prefix: String { self == .mergeRequest ? "!" : "#" }
    }

    let kind: Kind
    let iid: Int

    var body: some View {
        Text("\(kind.prefix)\(iid)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.accentColor, in: Capsule())
    }
}
