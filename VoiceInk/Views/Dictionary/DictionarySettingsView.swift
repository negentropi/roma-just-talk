import SwiftUI
import SwiftData
import VoiceInkCore

private enum DictionaryPane: Hashable {
    case catalog(VoiceInkDictionarySettingsSection)
    case snippets

    static var all: [DictionaryPane] {
        VoiceInkDictionarySettingsSection.allCases.map(DictionaryPane.catalog) + [.snippets]
    }

    var accessibilityIdentifier: String {
        switch self {
        case .catalog(let section): "dictionary.section.\(section)"
        case .snippets: "dictionary.section.snippets"
        }
    }
}

struct DictionarySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedPane: DictionaryPane = .catalog(.defaultSelection)
    @State private var isShowingSettings = false
    private let dictionaryPresentation = VoiceInkDictionarySettingsPresentation.macOS

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                mainContent
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .settingsSheet(isPresented: $isShowingSettings, width: 400) {
            DictionarySettingsPanel {
                withAnimation(.smooth(duration: 0.3)) {
                    isShowingSettings = false
                }
            }
        }
    }
    
    private var heroSection: some View {
        CompactHeroSection(
            icon: "brain.filled.head.profile",
            title: dictionaryPresentation.sectionTitle,
            description: dictionaryPresentation.heroDescription ?? "",
            maxDescriptionWidth: 500
        )
    }
    
    private var mainContent: some View {
        VStack(spacing: 40) {
            sectionSelector
            selectedSectionContent
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
    }
    
    private var sectionSelector: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(dictionaryPresentation.sectionSelectorTitle ?? "")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        isShowingSettings.toggle()
                    }
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isShowingSettings ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(dictionaryPresentation.settingsButtonHelp ?? "")
                .accessibilityLabel(dictionaryPresentation.settingsButtonHelp ?? "Dictionary Settings")
                .accessibilityIdentifier("dictionary.settings.open")
            }

            HStack(alignment: .top, spacing: 16) {
                ForEach(DictionaryPane.all, id: \.self) { pane in
                    sectionCard(for: pane)
                        .accessibilityIdentifier(pane.accessibilityIdentifier)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func sectionCard(for pane: DictionaryPane) -> some View {
        switch pane {
        case .catalog(let section):
            SectionCard(
                presentation: section.presentation(in: dictionaryPresentation),
                isSelected: selectedPane == pane,
                action: { selectedPane = pane }
            )
        case .snippets:
            SectionCard(
                systemImageName: "text.quote",
                title: "Snippets",
                description: "Say a short phrase to insert saved text exactly.",
                isSelected: selectedPane == pane,
                action: { selectedPane = pane }
            )
        }
    }

    private var selectedSectionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch selectedPane {
            case .catalog(.wordReplacements):
                WordReplacementView()
                    .background(CardBackground(isSelected: false))
            case .catalog(.vocabulary):
                VocabularyView()
                    .background(CardBackground(isSelected: false))
            case .snippets:
                SpokenSnippetsView()
                    .background(CardBackground(isSelected: false))
            }
        }
    }
}

struct SectionCard: View {
    let systemImageName: String
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    init(
        presentation: VoiceInkDictionarySettingsSectionPresentation,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.init(
            systemImageName: presentation.systemImageName,
            title: presentation.title,
            description: presentation.description,
            isSelected: isSelected,
            action: action
        )
    }

    init(
        systemImageName: String,
        title: String,
        description: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.systemImageName = systemImageName
        self.title = title
        self.description = description
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImageName)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
            .background(CardBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
