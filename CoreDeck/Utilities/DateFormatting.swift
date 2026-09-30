import Foundation

enum DateFormatting {
    static func timestamp(for date: Date) -> String {
        date.formatted(
            .dateTime
                .year(.defaultDigits)
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
    }
}
