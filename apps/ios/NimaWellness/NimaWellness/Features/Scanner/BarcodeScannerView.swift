import SwiftUI
import WellnessCore

/// Barcode entry (DEVICE-001): on-device detection when the camera and
/// VisionKit scanner are available, with a manual-entry fallback that covers
/// the simulator and denied camera access. Either path feeds the same
/// validated-GTIN resolver; nothing is inferred from a partial code.
struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCode: (String) -> Void

    @State private var manualCode = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                #if canImport(VisionKit)
                if LiveBarcodeScanner.isSupported {
                    LiveBarcodeScanner { code in
                        onCode(code)
                        dismiss()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxHeight: 360)
                } else {
                    unavailableNotice
                }
                #else
                unavailableNotice
                #endif

                HStack {
                    TextField("Or type the barcode digits", text: $manualCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Use") {
                        onCode(manualCode)
                        dismiss()
                    }
                    .disabled(manualCode.filter(\.isNumber).count < 8)
                }
                Text("An unreadable or unknown barcode falls back to typed search — the app never guesses a product from a partial code.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
            }
            .padding()
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var unavailableNotice: some View {
        ContentUnavailableView(
            "Camera scanning unavailable",
            systemImage: "barcode.viewfinder",
            description: Text("Live scanning needs a supported device and camera access. You can type the digits below instead.")
        )
    }
}

#if canImport(VisionKit)
import VisionKit

/// Thin wrapper over DataScannerViewController limited to barcode symbologies.
@MainActor
struct LiveBarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce, .code128])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var delivered = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            deliverFirstBarcode(from: addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            deliverFirstBarcode(from: [item])
        }

        private func deliverFirstBarcode(from items: [RecognizedItem]) {
            guard !delivered else { return }
            for item in items {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    delivered = true
                    onCode(payload)
                    return
                }
            }
        }
    }
}
#endif
