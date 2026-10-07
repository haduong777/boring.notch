import Foundation

/// Date-only month geometry, independent of EventKit permissions and agenda state.
struct CalendarMonth {
    let calendar: Calendar
    let start: Date
    let days: [Date]

    init(containing date: Date, calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        start = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
        days = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    var weekdayNames: [String] {
        let symbols = calendar.standaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    func contains(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: start, toGranularity: .month)
    }

    func moving(by months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: start) ?? start
    }
}
