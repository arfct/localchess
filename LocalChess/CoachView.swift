// CoachView.swift — LocalChess
// Yeti coach portraits + speech bubble, echoing the reference layout:
// avatar left, quip bubble right.

import SwiftUI

struct CoachView: View {
    let message: String
    let mood: CoachMood
    var avatar: CGFloat = 86

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            CoachAvatar(mood: mood)
                .frame(width: avatar, height: avatar)
            SpeechBubble(text: message)
            // Absorbs bubble width changes so the row always spans the
            // full width and the avatar never shifts with text length.
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Yeti portrait for a coach mood. Portraits live in the asset catalog
/// as yeti-<mood> imagesets.
struct CoachAvatar: View {
    let mood: CoachMood

    var body: some View {
        YetiPortrait(asset: mood.yetiAsset, label: "yeti coach, \(mood)")
    }
}

/// Circular yeti portrait usable anywhere (coach bubble, mate card).
struct YetiPortrait: View {
    let asset: String
    var label: String = "yeti"

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: s, height: s)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.25),
                                        lineWidth: max(1.5, s * 0.02)))
                .frame(width: geo.size.width, height: geo.size.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityIdentifier("coach-\(asset)")
        }
    }
}

extension CoachMood {
    var yetiAsset: String {
        switch self {
        case .thinking: return "yeti-thinking"
        case .happy: return "yeti-happy"
        case .excited: return "yeti-excited"
        case .worried: return "yeti-worried"
        case .sad: return "yeti-sad"
        }
    }
}

struct SpeechBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .lineLimit(3)
            .minimumScaleFactor(0.85)
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.04))
                }
            )
            .overlay(
                // Tail pointing at the coach.
                Path { p in
                    p.move(to: CGPoint(x: -8, y: 22))
                    p.addLine(to: CGPoint(x: -18, y: 28))
                    p.addLine(to: CGPoint(x: -8, y: 34))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.10, green: 0.15, blue: 0.17)),
                alignment: .leading
            )
            .id(text)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: text)
    }
}
