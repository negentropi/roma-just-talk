import SwiftUI

enum CursorAvatarStyle: String, CaseIterable, Identifiable {
    case cartoon, disney, anime, none
    static let defaultsKey = "CursorAvatarStyle"
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CaptureFeedback: Equatable {
    case hidden, starting, ready, listening, working, failed(String)
    var label: String {
        switch self {
        case .hidden: return ""
        case .starting: return "Getting ready…"
        case .ready: return "Ready to capture"
        case .listening: return "Listening"
        case .working: return "Working…"
        case .failed(let message): return message
        }
    }
    var pose: String {
        switch self {
        case .hidden, .starting: return "greeting"
        case .ready, .listening: return "listening"
        case .working: return "working"
        case .failed: return "worried"
        }
    }
    var isFailure: Bool { if case .failed = self { return true }; return false }
}

struct CursorAvatarView: View {
    let style: CursorAvatarStyle
    let feedback: CaptureFeedback
    var level: Double = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var reducedMotionOverride: Bool? = nil
    var animationDateOverride: Date? = nil
    var listeningElapsedOverride: TimeInterval? = nil
    var trailingAttachment = false
    var attachmentOffset: CGSize = .zero
    @State private var listeningBegan = Date.distantPast
    private var reduceMotion: Bool { reducedMotionOverride ?? systemReduceMotion }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if style != .none {
                Group {
                    if let date = animationDateOverride {
                        artwork(at: date)
                    } else {
                        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                            artwork(at: timeline.date)
                        }
                    }
                }
                .offset(x: (trailingAttachment ? 188 : 0) + attachmentOffset.width, y: attachmentOffset.height)
                .accessibilityHidden(true)
            }
            Image(systemName: statusSymbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 12, height: 12)
                .background(statusColor, in: Circle())
                .offset(x: (trailingAttachment ? 211 : 23) + attachmentOffset.width, y: 20 + attachmentOffset.height)
            if feedback.isFailure {
                Text(feedback.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(width: 180, alignment: .leading)
                    .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                    .offset(x: trailingAttachment ? 0 : 38)
            }
        }
        .frame(width: feedback.isFailure ? 224 : 40, height: feedback.isFailure ? 90 : 36, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RJT \(feedback.label)")
        .onAppear { if feedback == .listening { listeningBegan = Date() } }
        .onChange(of: feedback) { _, next in
            if next == .listening { listeningBegan = Date() }
        }
    }

    private func artwork(at date: Date) -> some View {
        let time = date.timeIntervalSinceReferenceDate
        let wave = reduceMotion ? 0 : sin(time * (feedback == .working ? 4 : 2))
        let elapsed = listeningElapsedOverride ?? max(0, date.timeIntervalSince(listeningBegan))
        let greeting = feedback == .listening && !reduceMotion ? max(0, 1 - elapsed / 0.9) : 0
        let blink = feedback == .listening && !reduceMotion && elapsed > 1 && elapsed.truncatingRemainder(dividingBy: 4.3) < 0.16
        return ZStack {
            artworkImage(blink ? "listening-blink" : feedback.pose).opacity(1 - greeting)
            if greeting > 0 { artworkImage("greeting").opacity(greeting) }
        }
        .frame(width: 32, height: 32)
        .scaleEffect(reduceMotion ? 1 : 1 + wave * 0.012 + (feedback == .listening ? min(level, 1) * 0.035 : 0), anchor: .bottom)
        .rotationEffect(.degrees(greeting > 0 ? sin(elapsed * 12) * greeting * 6 : (feedback == .working ? wave * 3 : 0)), anchor: .bottom)
        .offset(y: wave * 0.4)
    }

    private var statusSymbol: String {
        switch feedback {
        case .hidden, .starting: return "ellipsis"
        case .ready: return "checkmark"
        case .listening: return "mic.fill"
        case .working: return "hourglass"
        case .failed: return "exclamationmark"
        }
    }

    private var statusColor: Color {
        switch feedback {
        case .failed: return .orange
        case .ready, .listening: return .green
        default: return .blue
        }
    }

    private func artworkImage(_ pose: String) -> some View {
        let name = "CursorAvatar-\(style.rawValue)-\(pose)"
        return Image(nsImage: NSImage(named: name) ?? NSImage())
            .resizable().scaledToFit()
    }

}

struct CursorAvatarPicker: View {
    @AppStorage(CursorAvatarStyle.defaultsKey) private var selection = CursorAvatarStyle.cartoon.rawValue
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 12)], spacing: 12) {
            ForEach(CursorAvatarStyle.allCases) { style in
                Button {
                    selection = style.rawValue
                } label: {
                    VStack(spacing: 8) {
                        ZStack(alignment: .topLeading) {
                            CursorAvatarView(style: style, feedback: .listening)
                            Image(systemName: "cursorarrow")
                                .font(.system(size: 24))
                                .offset(x: 16, y: 32)
                        }
                        .frame(width: 60, height: 64, alignment: .topLeading)
                        .clipped()
                        .frame(maxWidth: .infinity)
                        Text(style.title).font(.headline)
                        Image(systemName: selection == style.rawValue ? "checkmark.circle.fill" : "circle")
                    }
                    .padding(8)
                    .background(selection == style.rawValue ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(selection == style.rawValue ? Color.accentColor : Color.clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.title)
                .accessibilityAddTraits(selection == style.rawValue ? .isSelected : [])
            }
        }
    }
}

@MainActor
final class CursorAvatarPresentation: ObservableObject {
    @Published var style: CursorAvatarStyle = .cartoon
    @Published var feedback: CaptureFeedback = .hidden
    @Published var level: Double = 0
    @Published var trailingAttachment = false
    @Published var attachmentOffset: CGSize = .zero
}

struct CursorAvatarLiveView: View {
    @ObservedObject var presentation: CursorAvatarPresentation
    var body: some View {
        CursorAvatarView(style: presentation.style, feedback: presentation.feedback, level: presentation.level,
                         trailingAttachment: presentation.trailingAttachment, attachmentOffset: presentation.attachmentOffset)
    }
}
