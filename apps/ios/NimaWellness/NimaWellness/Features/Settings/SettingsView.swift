import SwiftUI
import WellnessCore

/// Settings (UI-016): energy method, day completion, model readiness, and
/// privacy notes. The owner profile is an opt-in seed requiring confirmation
/// (ENERGY-002); nothing here is a general health recommendation.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var useFormula = false
    @State private var weightText = "93"
    @State private var heightText = "178"
    @State private var ageText = "33"
    @State private var equation: RestingEquationConstant = .maleEquation
    @State private var manualRestingText = ""

    var body: some View {
        @Bindable var appModel = appModel
        Form {
            Section("Selected day") {
                Toggle("Mark \(appModel.selectedDay.isoString) complete", isOn: Binding(
                    get: { appModel.completedDays.contains(appModel.selectedDay.isoString) },
                    set: { appModel.markSelectedDayComplete($0) }
                ))
                Text("The calorie-balance comparison stays provisional until the day's intake and activity are marked complete (ENERGY-007).")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section("Estimated resting energy") {
                Toggle("Use the Mifflin-St Jeor estimate", isOn: $useFormula)
                if useFormula {
                    LabeledContent("Weight (kg)") {
                        TextField("kg", text: $weightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Height (cm)") {
                        TextField("cm", text: $heightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Age (years)") {
                        TextField("years", text: $ageText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Equation constant", selection: $equation) {
                        Text("+5 (male equation)").tag(RestingEquationConstant.maleEquation)
                        Text("−161 (female equation)").tag(RestingEquationConstant.femaleEquation)
                    }
                    if let profile = profile {
                        Text("Estimated resting energy: \(Int(EnergyEngine.restingEstimate(profile: profile).rounded())) kcal/day — an estimate, not a measured value.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    LabeledContent("Manual daily estimate (kcal)") {
                        TextField("kcal", text: $manualRestingText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                }
                Button("Apply energy settings") { applyEnergySettings() }
                Picker("Balance goal", selection: $appModel.balanceMode) {
                    Text("Weight loss").tag(BalanceGoalMode.weightLoss)
                    Text("Maintenance").tag(BalanceGoalMode.maintenance)
                    Text("Weight gain").tag(BalanceGoalMode.weightGain)
                }
            } footer: {
                Text("The equation choice is yours; it is never inferred. Values are estimates from published research (Mifflin et al.), not prescriptions.")
            }

            Section("On-device model") {
                LabeledContent("Status", value: ChatModel.availabilityText(appModel.interpreterAvailability))
                Text("Interpretation runs on this device through Apple's system model. No conversation leaves the phone in this version. Manual tracking never requires the model.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section("Privacy") {
                Text("All personal data is stored locally on this device. There is no account, no analytics SDK, and no cloud sync in this version. Export and delete-all controls arrive with the M6 privacy review.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .navigationTitle("Settings")
        .onAppear { populate() }
    }

    private var profile: EnergyProfile? {
        guard let weight = Double(weightText), let height = Double(heightText), let age = Double(ageText) else { return nil }
        return EnergyProfile(weightKg: weight, heightCm: height, ageYears: age, equationConstant: equation)
    }

    private func populate() {
        switch appModel.restingInput {
        case .formula(let existing):
            useFormula = true
            weightText = existing.weightKg.cleanString
            heightText = existing.heightCm.cleanString
            ageText = "\(Int(existing.ageYears))"
            equation = existing.equationConstant
        case .manual(let value):
            useFormula = false
            manualRestingText = "\(Int(value))"
        case nil:
            break
        }
    }

    private func applyEnergySettings() {
        if useFormula, let profile {
            appModel.restingInput = .formula(profile)
        } else if let manual = Double(manualRestingText), manual > 0 {
            appModel.restingInput = .manual(manual)
        } else {
            appModel.restingInput = nil
        }
    }
}
