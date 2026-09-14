import SwiftUI
import WellnessCore

/// HealthKit settings (HEALTH-001/002/007): per-type opt-in with a stated
/// purpose, just-in-time permission, honest empty states, and a disconnect
/// that stops future imports without touching the health store's own data.
struct HealthSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showDisconnectConfirm = false

    var body: some View {
        Form {
            if !HealthKitService.isAvailableOnDevice {
                Section {
                    Label("Health data is not available on this device.", systemImage: "heart.slash")
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Section("Read from Health") {
                ForEach(HealthDataType.allCases) { type in
                    Toggle(isOn: Binding(
                        get: { appModel.enabledHealthTypes.contains(type) },
                        set: { enabled in
                            Task { await appModel.setHealthType(type, enabled: enabled) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName)
                            Text(type.purpose)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .disabled(!HealthKitService.isAvailableOnDevice)
                }
            } footer: {
                Text("Permission is requested only for the types you enable, when you enable them. Reading is one-way: this app never writes to Health in this release.")
            }

            Section("Import") {
                Button("Import selected day now") {
                    Task { await appModel.importHealthData() }
                }
                .disabled(appModel.enabledHealthTypes.isEmpty)
                if let status = appModel.healthStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            } footer: {
                // HEALTH-002: absence of samples is not a known denial.
                Text("If nothing imports, the data may not exist or reading may not be allowed — iOS does not tell apps which. Manual entry always works. Each metric uses one source at a time: enabling a Health type switches that field to Health, and disabling returns it to manual entry, so values are never counted twice.")
            }

            Section {
                Button("Stop all Health imports…", role: .destructive) {
                    showDisconnectConfirm = true
                }
            } footer: {
                Text("Stopping removes nothing from the Health app. Data recorded there by other apps is theirs; this app never deletes it.")
            }
        }
        .navigationTitle("Health")
        .confirmationDialog("Stop Health imports?", isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button("Stop imports, keep imported values") {
                appModel.disconnectHealth(clearImportedCopies: false)
            }
            Button("Stop imports and remove imported copies", role: .destructive) {
                appModel.disconnectHealth(clearImportedCopies: true)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Reminder settings (DEVICE-004).
struct RemindersSettingsView: View {
    @State private var service = ReminderService()
    @State private var showAddSheet = false

    var body: some View {
        Form {
            if service.permissionState == .denied {
                Section {
                    Label("Notifications are turned off for this app in iOS Settings. Reminders cannot be delivered until you allow them there.", systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("Reminders") {
                ForEach(service.rules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.title)
                            Text(ruleSchedule(rule))
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { enabled in Task { await service.setEnabled(rule, enabled: enabled) } }
                        ))
                        .labelsHidden()
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await service.remove(rule) }
                        }
                    }
                }
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add reminder…", systemImage: "plus.circle")
                }
            } footer: {
                Text("Reminders are ones you create — nothing is inferred from your data, and a delivered reminder is never recorded as a completed task.")
            }

            Section("Quiet hours") {
                Toggle("Enable quiet hours", isOn: Binding(
                    get: { service.quietHoursEnabled },
                    set: { service.quietHoursEnabled = $0 }
                ))
                if service.quietHoursEnabled {
                    minutePicker("From", minute: Binding(
                        get: { service.quietStartMinute },
                        set: { service.quietStartMinute = $0 }
                    ))
                    minutePicker("Until", minute: Binding(
                        get: { service.quietEndMinute },
                        set: { service.quietEndMinute = $0 }
                    ))
                }
            } footer: {
                Text("A reminder scheduled inside quiet hours is delivered when the quiet window ends.")
            }
        }
        .navigationTitle("Reminders")
        .sheet(isPresented: $showAddSheet) {
            AddReminderSheet { rule in
                Task { await service.add(rule) }
            }
        }
        .task { await service.resync() }
    }

    private func ruleSchedule(_ rule: ReminderRule) -> String {
        let time = String(format: "%02d:%02d", rule.hour, rule.minute)
        if rule.weekdays.isEmpty { return "Daily at \(time)" }
        let symbols = Calendar.current.shortWeekdaySymbols
        let days = rule.weekdays.compactMap { $0 >= 1 && $0 <= 7 ? symbols[$0 - 1] : nil }
        return "\(days.joined(separator: ", ")) at \(time)"
    }

    private func minutePicker(_ title: String, minute: Binding<Int>) -> some View {
        Picker(title, selection: minute) {
            ForEach(Array(stride(from: 0, to: 24 * 60, by: 30)), id: \.self) { value in
                Text(String(format: "%02d:%02d", value / 60, value % 60)).tag(value)
            }
        }
    }
}

struct AddReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (ReminderRule) -> Void

    @State private var title = ""
    @State private var time = Date()
    @State private var selectedWeekdays: Set<Int> = []

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title (e.g. Water break)", text: $title)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                Section("Days (none = every day)") {
                    let symbols = Calendar.current.shortWeekdaySymbols
                    ForEach(1...7, id: \.self) { weekday in
                        Toggle(symbols[weekday - 1], isOn: Binding(
                            get: { selectedWeekdays.contains(weekday) },
                            set: { on in
                                if on { selectedWeekdays.insert(weekday) } else { selectedWeekdays.remove(weekday) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Add reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                        onAdd(ReminderRule(
                            title: title.trimmingCharacters(in: .whitespaces),
                            hour: components.hour ?? 9,
                            minute: components.minute ?? 0,
                            weekdays: Array(selectedWeekdays).sorted()
                        ))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
