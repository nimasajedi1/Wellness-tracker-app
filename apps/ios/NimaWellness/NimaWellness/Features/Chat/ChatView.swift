import SwiftUI
import WellnessCore

/// Chat screen (section 6.4): header shows log date and model availability,
/// a deterministic daily summary sits above the composer, and result cards
/// clearly separate Preview from Logged (UI-011).
struct ChatView: View {
    @Environment(AppModel.self) private var appModel
    @State private var chatModel: ChatModel?
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let chatModel {
                    content(chatModel)
                } else {
                    ProgressView()
                }
            }
            .background(Theme.background)
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(appModel.selectedDay.isoString)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    availabilityBadge
                }
            }
        }
        .task {
            if chatModel == nil {
                chatModel = ChatModel(appModel: appModel)
            }
        }
    }

    private var availabilityBadge: some View {
        let ready = appModel.interpreterAvailability == .ready
        return Label(
            ready ? "On-device" : "Model unavailable",
            systemImage: ready ? "cpu" : "cpu.fill"
        )
        .font(.caption2)
        .foregroundStyle(ready ? .green : .orange)
        .accessibilityLabel(ChatModel.availabilityText(appModel.interpreterAvailability))
    }

    @ViewBuilder
    private func content(_ chatModel: ChatModel) -> some View {
        @Bindable var chatModel = chatModel
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if !(appModel.interpreterAvailability == .ready) {
                            AvailabilityNotice(availability: appModel.interpreterAvailability)
                        }
                        ForEach(chatModel.messages) { message in
                            MessageView(message: message, chatModel: chatModel)
                                .id(message.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: chatModel.messages.count) {
                    if let last = chatModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Deterministic summary for enabled nutrition fields (section 6.4).
            Text(chatModel.daySummaryText())
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            HStack(alignment: .bottom, spacing: 8) {
                // UI-013: multiline composer with send, cancel, and dismissal.
                TextField("Log food or ask…", text: $chatModel.composerText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($composerFocused)
                if chatModel.isInterpreting {
                    Button {
                        chatModel.cancelInterpretation()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Cancel interpretation")
                } else {
                    Button {
                        chatModel.send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(chatModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send")
                }
            }
            .padding(12)
        }
    }
}

struct AvailabilityNotice: View {
    let availability: InterpreterAvailability

    var body: some View {
        Label {
            Text("\(ChatModel.availabilityText(availability)) Manual logging on Today works without it.")
                .font(.footnote)
        } icon: {
            Image(systemName: "info.circle")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MessageView: View {
    let message: ChatMessage
    let chatModel: ChatModel

    var body: some View {
        switch message.content {
        case .userText(let text):
            Text(text)
                .padding(10)
                .background(Theme.accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistantText(let text), .receipt(let text):
            Text(text)
                .font(.callout)
                .padding(10)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failure(let text):
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .padding(10)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.5)))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .clarification(let clarification):
            VStack(alignment: .leading, spacing: 8) {
                Text(clarification.question).font(.callout)
                ForEach(clarification.options, id: \.self) { option in
                    Button(option) {
                        chatModel.composerText = option
                    }
                    .buttonStyle(.bordered)
                    .font(.footnote)
                }
            }
            .padding(10)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
        case .preview(let preview):
            ResultCardView(preview: preview, chatModel: chatModel)
        }
    }
}

/// Nutrition result card (section 6.4): matched item, portion basis, nutrients
/// with unknowns visible, evidence type, and separate actions. The Preview /
/// Logged distinction is explicit (UI-011).
struct ResultCardView: View {
    let preview: MealPreview
    let chatModel: ChatModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(preview.isLogged ? "LOGGED" : (preview.isHypothetical ? "PREVIEW · not counted" : "PREVIEW · confirm to log"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(preview.isLogged ? .green : Theme.secondaryText)
                Spacer()
                Text(preview.logDay.isoString)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }

            ForEach(preview.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName).font(.subheadline.weight(.semibold))
                    Text(item.portionDescription)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    HStack(spacing: 12) {
                        nutrientText("kcal", item.nutrients[.energyKcal], id: .energyKcal)
                        nutrientText("protein", item.nutrients[.proteinG], id: .proteinG)
                        nutrientText("fiber", item.nutrients[.fiberG], id: .fiberG)
                    }
                    Text(evidenceLabel(item.evidenceType))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.vertical, 2)
            }

            ForEach(Array(preview.unresolvedMentions.enumerated()), id: \.offset) { _, mention in
                Label("“\(mention.textSpan)” — no verified match; not logged. Add a portion or search manually.", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !preview.items.isEmpty {
                HStack {
                    if preview.isLogged {
                        Button("Undo") { chatModel.undoCommit(preview) }
                            .buttonStyle(.bordered)
                    } else {
                        Button(preview.isHypothetical ? "Log it anyway" : "Add") {
                            chatModel.addPreview(preview)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .font(.footnote)
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nutrientText(_ label: String, _ value: NutrientValue?, id: NutrientID) -> some View {
        let display = NutrientDisplay.displayString(value ?? .unknown(reason: "missing"), nutrientID: id)
        return Text("\(display) \(label)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(display == "—" ? Theme.secondaryText : Theme.text)
    }

    private func evidenceLabel(_ type: EvidenceType) -> String {
        switch type {
        case .officialSource: return "Source: official document"
        case .usdaReference: return "Source: USDA reference"
        case .brandedLabelRecord: return "Source: branded label record"
        case .userEnteredLabel: return "Source: your transcribed label"
        case .recipeCalculated: return "Calculated from your recipe"
        case .estimate: return "Estimate — not a verified source"
        case .syntheticFixture: return "Test fixture (not real nutrition)"
        }
    }
}
