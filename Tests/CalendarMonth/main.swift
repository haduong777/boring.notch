import Foundation

func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Chicago")!
calendar.locale = Locale(identifier: "en_US")

// Both common week starts, all month lengths, and four/five/six-week layouts.
for firstWeekday in [1, 2] {
    calendar.firstWeekday = firstWeekday
    for year in [2024, 2025, 2026] {
        for monthNumber in 1...12 {
            let grid = CalendarMonth(containing: date(year, monthNumber, 15, in: calendar), calendar: calendar)
            let inMonth = grid.days.filter(grid.contains)
            assert(grid.days.count == 42)
            assert(calendar.component(.weekday, from: grid.days[0]) == firstWeekday)
            assert(inMonth.count == calendar.range(of: .day, in: .month, for: grid.start)!.count)
            assert(calendar.component(.day, from: inMonth.first!) == 1)
            assert(Set(inMonth).count == inMonth.count)
            for pair in zip(grid.days, grid.days.dropFirst()) {
                assert(calendar.dateComponents([.day], from: pair.0, to: pair.1).day == 1)
            }
            assert(grid.weekdaySymbols.first == calendar.shortStandaloneWeekdaySymbols[firstWeekday - 1])
            assert(grid.weekdayNames.first == calendar.standaloneWeekdaySymbols[firstWeekday - 1])
        }
    }
}

let december = CalendarMonth(containing: date(2026, 12, 31, in: calendar), calendar: calendar)
assert(december.moving(by: 1) == date(2027, 1, 1, in: calendar))
let january = CalendarMonth(containing: date(2026, 1, 31, in: calendar), calendar: calendar)
assert(january.moving(by: 1) == date(2026, 2, 1, in: calendar))
assert(january.moving(by: -1) == date(2025, 12, 1, in: calendar))

// The spring DST day is 23 hours, but occupies exactly one calendar cell.
let march = CalendarMonth(containing: date(2026, 3, 8, in: calendar), calendar: calendar)
let eighth = march.days.firstIndex(of: date(2026, 3, 8, in: calendar))!
assert(march.days[eighth + 1].timeIntervalSince(march.days[eighth]) == 23 * 60 * 60)

print("CalendarMonth checks passed: 72 month/week-start combinations, year rollover, month-end navigation and DST.")
