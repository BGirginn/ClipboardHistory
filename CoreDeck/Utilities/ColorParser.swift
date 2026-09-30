import Foundation

enum ColorParser {
    static func hexColor(from text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.range(of: #"^#[0-9A-F]{6}([0-9A-F]{2})?$"#, options: .regularExpression) != nil {
            return value
        }
        if value.range(of: #"^#[0-9A-F]{3}$"#, options: .regularExpression) != nil {
            let digits = value.dropFirst()
            return "#" + digits.map { "\($0)\($0)" }.joined()
        }
        guard let match = value.firstMatch(
            of: /RGB\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)/
        ), let red = Int(match.output.1), let green = Int(match.output.2),
           let blue = Int(match.output.3), [red, green, blue].allSatisfy({ (0...255).contains($0) }) else {
            return nil
        }
        return "#\(hexByte(red))\(hexByte(green))\(hexByte(blue))"
    }

    private static func hexByte(_ value: Int) -> String {
        let hexadecimal = String(value, radix: 16, uppercase: true)
        return hexadecimal.count == 1 ? "0\(hexadecimal)" : hexadecimal
    }
}
