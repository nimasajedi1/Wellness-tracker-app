import SwiftUI
import WellnessCore

private enum EnergyMethodChoice: String, CaseIterable, Identifiable {
    case none
    case restingPlusActive
    case healthKit
    case fixedTotal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Not configured"
        case .restingPlusActive: return "Estimated resting + logged active"
        case .healthKit: return "Health data (resting + active samples)"
        case .fixedTotal: return "Fixed daily total"
        }
    }
}

/// Settings (UI-016): energy method, day completion, Health and Reminders,
/// model readiness, and privacy notes. The owner profile is an opt-in seed
/// requiring confirmation (ENERGY-002); nothing here is a general health
/// recommendation.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var methodChoice: EnergyMethodChoice = .none
    @State private var useFormula = false
    @State private var weightText = "93"
    @State private var heightText = "178"
    @State private var ageText = "33"
    @State private var equation: RestingEquationConstant = .maleEquation
    @State private var manualRestingText = ""
    @State private var fixedTotalText = ""
    @State private var fixedAddsActive = false

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

            Section("Estimated energy out") {
                Picker("Method", selection: $methodChoice) {
                    ForEach(EnergyMethodChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }

                switch methodChoice {
                case .none:
                    Text("Without a method, the balance card shows intake only and stays gray.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                case .restingPlusActive:
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
                case .healthKit:
                    Text("Uses resting and active energy read from Health for the same day. The formula estimate is never added on top, and a same-day comparison stays provisional until the day is over (ENERGY-003). Enable Resting and Active energy under Health below.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                case .fixedTotal:
                    LabeledContent("Daily total (kcal)") {
                        TextField("kcal", text: $fixedTotalText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    Toggle("Add logged active energy on top", isOn: $fixedAddsActive)
                    Text("Off by default: a fixed total usually already includes activity, so active calories are shown but not added (ENERGY-004).")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Button("Apply energy settings") { applyEnergySettings() }
                Picker("Balance goal", selection: $appModel.balanceMode) {
                    Text("Weight loss").tag(BalanceGoalMode.weightLoss)
                    Text("Maintenance").tag(BalanceGoalMode.maintenance)
                    Text("Weight gain").tag(BalanceGoalMode.weightGain)
                }
                .onChange(of: appModel.balanceMode) {
                    UserDefaults.standard.set(appModel.balanceMode.rawValue, forKey: "balanceMode")
                }
            } footer: {
                Text("One method at a time — sources are never summed together. The equation choice is yours; it is never inferred. Values are estimates from published research (Mifflin et al.), not prescriptions.")
            }

            Section("Integrations") {
                NavigationLink {
                    HealthSettingsView()
                } label: {
                    Label("Health", systemImage: "heart")
                }
                NavigationLink {
                    RemindersSettingsView()
                } label: {
                    Label("Reminders", systemImage: "bell")
                }
            } footer: {
                Text("Health reading and reminders are optional; manual tracking never depends on them.")
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
        switch appModel.expenditureMethod ?? appModel.restingInput.map({ ExpenditureMethod.restingPlusActive($0) }) {
        case .restingPlusActive(let input):
            methodChoice = .restingPlusActive
            switch input {
            case .formula(let existing):
                useFormula = true
                weightText = existing.weightKg.cleanString
                heightText = existing.heightCm.cleanString
                ageText = "\(Int(existing.ageYears))"
                equation = existing.equationConstant
            case .manual(let value):
                useFormula = false
                manualRestingText = "\(Int(value))"
            }
        case .healthKitDaily:
            methodChoice = .healthKit
        case .fixedDailyTotal(let kcal, let addsActive):
            methodChoice = .fixedTotal
            fixedTotalText = "\(Int(kcal))"
            fixedAddsActive = addsActive
        case nil:
            methodChoice = .none
        }
    }

    private func applyEnergySettings() {
        switch methodChoice {
        case .none:
            appModel.expenditureMethod = nil
            appModel.restingInput = nil
        case .restingPlusActive:
            if useFormula, let profile {
                appModel.expenditureMethod = .restingPlusActive(.formula(profile))
            } else if let manual = Double(manualRestingText), manual > 0 {
                appModel.expenditureMethod = .restingPlusActive(.manual(manual))
            } else {
                appModel.expenditureMethod = nil
            }
        case .healthKit:
            appModel.expenditureMethod = .healthKitDaily
        case .fixedTotal:
            if let total = Double(fixedTotalText), total > 0 {
                appModel.expenditureMethod = .fixedDailyTotal(kcal: total, activeIsAdditional: fixedAddsActive)
            } else {
                appModel.expenditureMethod = nil
            }
        }
    }
}
