import SwiftUI

struct MonthCalendarView: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date

    private var month: CalendarMonth { CalendarMonth(containing: displayedMonth) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        let month = self.month
        VStack(spacing: 8) {
            HStack {
                monthButton("chevron.left", label: "Previous month", direction: -1)
                Spacer(minLength: 0)
                Button("Today") {
                    displayedMonth = Date()
                    selectedDate = Date()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(white: 0.8))
                .frame(minHeight: 26)
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                monthButton("chevron.right", label: "Next month", direction: 1)
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<7, id: \.self) { index in
                    Text(month.weekdaySymbols[index])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(white: 0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 18)
                        .accessibilityLabel(month.weekdayNames[index])
                }
                ForEach(month.days.indices, id: \.self) { index in
                    let date = month.days[index]
                    if month.contains(date) {
                        dayButton(date, in: month)
                    } else {
                        Color.clear
                            .frame(height: 24)
                            .accessibilityHidden(true)
                    }
                }
            }

            Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.caption)
                .foregroundStyle(Color(white: 0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(selectedDate.formatted(date: .complete, time: .omitted))
        }
        .buttonStyle(.plain)
    }

    private func monthButton(_ icon: String, label: LocalizedStringKey, direction: Int) -> some View {
        Button {
            // Keep grid positions stable rather than animating reused dates between cells.
            displayedMonth = month.moving(by: direction)
            selectedDate = displayedMonth
        } label: {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.65))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .help(label)
    }

    private func dayButton(_ date: Date, in month: CalendarMonth) -> some View {
        let isSelected = month.calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = month.calendar.isDateInToday(date)
        return Button {
            selectedDate = date
        } label: {
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(isSelected || isToday ? .white : Color(white: 0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background {
                    if isToday {
                        Circle()
                            .fill(Color.effectiveAccent)
                            .frame(width: 20, height: 20)
                    }
                }
                .background(isSelected ? Color.effectiveAccentBackground : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.effectiveAccent, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(isToday ? "Today" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MonthCalendarPreview: View {
    @State private var month = Date()
    @State private var selection = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.semibold))
            MonthCalendarView(displayedMonth: $month, selectedDate: $selection)
        }
        .padding(12)
        .background(.black)
        .preferredColorScheme(.dark)
    }
}

#Preview("Month · calendar width") {
    MonthCalendarPreview().frame(width: 239)
}

#Preview("Month · with camera") {
    MonthCalendarPreview().frame(width: 194)
}
