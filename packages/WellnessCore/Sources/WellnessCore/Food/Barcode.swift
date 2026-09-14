import Foundation

/// Barcode identity handling (DEVICE-001). A scanned code resolves through the
/// same food resolver as typed search; an unreadable or unverified code falls
/// back to typed search and never infers a product without confirmation.
public enum Barcode {

    /// Normalize and checksum-validate a GTIN-8/12/13/14. Returns the digits
    /// when valid, nil otherwise — an incomplete or corrupted code is rejected
    /// rather than "repaired" into a guess.
    public static func validatedGTIN(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard [8, 12, 13, 14].contains(digits.count) else { return nil }
        guard isValidCheckDigit(digits) else { return nil }
        return digits
    }

    /// Standard GS1 mod-10 check: weight 3 on positions counted from the
    /// right, starting immediately left of the check digit.
    static func isValidCheckDigit(_ digits: String) -> Bool {
        let values = digits.compactMap { $0.wholeNumberValue }
        guard values.count == digits.count, let check = values.last else { return false }
        let body = values.dropLast().reversed()
        var sum = 0
        for (index, digit) in body.enumerated() {
            sum += digit * (index % 2 == 0 ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }

    /// Candidate keys to match against stored identifiers: the exact digits
    /// plus the zero-padded GTIN-13/14 forms, since catalogs store either.
    public static func lookupKeys(for gtin: String) -> [String] {
        var keys: Set<String> = [gtin]
        if gtin.count < 13 { keys.insert(String(repeating: "0", count: 13 - gtin.count) + gtin) }
        if gtin.count < 14 { keys.insert(String(repeating: "0", count: 14 - gtin.count) + gtin) }
        keys.insert(gtin.drop(while: { $0 == "0" }).isEmpty ? gtin : String(gtin.drop(while: { $0 == "0" })))
        return Array(keys)
    }
}
