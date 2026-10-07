import SwiftUI

struct OnboardingAvatarView: View {
    let continueAction: () -> Void
    var body: some View {
        ZStack {
            Color.black
            ScrollView {
                VStack(spacing: 24) {
                    Text("Meet your cursor companion")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("A quiet companion beside your cursor.\nSee when RJT is listening, working, or needs your help.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    CursorAvatarPicker()
                    Text("None keeps a small status cue. Change your choice anytime in Settings.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Continue", action: continueAction)
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
    }
}
