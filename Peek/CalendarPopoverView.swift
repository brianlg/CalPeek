import SwiftUI

/// Compact month calendar shown in the popover. Fixed 300pt wide, adapts to
/// light/dark automatically, and keeps a stable height by always laying out
/// six week rows of fixed height.
struct CalendarPopoverView: View {
    // MARK: - Constants
    
    private enum Layout {
        static let popoverWidth: CGFloat = 300
        static let popoverHeight: CGFloat = 340
        static let rowHeight: CGFloat = 36
        static let padding: CGFloat = 16
        static let daysPerWeek = 7
        static let numberOfWeeks = 6
        static let totalDays = daysPerWeek * numberOfWeeks // 42
        static let todayCircleSize: CGFloat = 32
        static let headerSpacing: CGFloat = 5
        static let contentSpacing: CGFloat = 12
    }
    
    // MARK: - State

    /// Months away from the current month. Chevrons shift it; "Today" resets it.
    @State private var monthOffset = 0
    /// Direction the grid slides when the month changes.
    @State private var slideEdge: Edge = .trailing
    /// Drives keyboard focus so arrow keys are received while the popover is open.
    @FocusState private var isFocused: Bool
    /// Controls presentation of the scrolling year picker popover.
    @State private var isYearPickerPresented = false

    /// macOS accent red — respects a system accent override.
    private let accent = Color(nsColor: .systemRed)
    
    // MARK: - Cached Formatters
    
    /// Reusable formatter for month names to avoid recreating on each render.
    /// Thread-safe because it's only accessed from the main thread (SwiftUI View).
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    /// Sunday-first calendar so the grid and the S–S header always align.
    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        return calendar
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: Layout.daysPerWeek)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.contentSpacing) {
            header
            weekdayRow
            grid
        }
        .padding(Layout.padding)
        .frame(width: Layout.popoverWidth)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { changeMonth(by: -1); return .handled }
        .onKeyPress(.rightArrow) { changeMonth(by: 1); return .handled }
        .onAppear { isFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.headerSpacing) {
            monthMenu
            yearButton

            Spacer()

            Button(String(localized: "Today"), action: goToToday)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.trailing, 4)
                .accessibilityLabel(String(localized: "Today"))

            Button { changeMonth(by: -1) } label: { chevron("chevron.left") }
                .buttonStyle(.plain)
            Button { changeMonth(by: 1) } label: { chevron("chevron.right") }
                .buttonStyle(.plain)
        }
    }

    /// Compact pop-up button for month selection (macOS standard for compact pickers).
    private var monthMenu: some View {
        Menu {
            Picker(selection: monthBinding) {
                ForEach(0..<calendar.monthSymbols.count, id: \.self) { index in
                    Text(calendar.monthSymbols[index]).tag(index)
                }
            } label: {
                Text(String(localized: "Month"))
            }
            .pickerStyle(.inline)
        } label: {
            Text(monthName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(String(localized: "Select month"))
    }

    /// Tappable year label that presents a scrolling year picker popover.
    private var yearButton: some View {
        Button {
            isYearPickerPresented.toggle()
        } label: {
            Text(yearString)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Select year"))
        .popover(isPresented: $isYearPickerPresented, arrowEdge: .bottom) {
            YearPickerPopover(
                selectedYear: displayedYear,
                yearRange: yearRange,
                accent: accent
            ) { newYear in
                isYearPickerPresented = false
                jumpTo(monthIndex: displayedMonthIndex, year: newYear)
            }
        }
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
    }

    // MARK: - Weekday header

    private var weekdayRow: some View {
        // Weekday short symbols repeat across the week ("S" for Sun/Sat,
        // "T" for Tue/Thu in en), so they can't serve as stable IDs. Index
        // the row by column position instead.
        let symbols = calendar.veryShortWeekdaySymbols
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(symbols.indices, id: \.self) { index in
                Text(symbols[index])
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Day grid

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(monthDays, id: \.self) { date in
                dayCell(for: date)
            }
        }
        // Re-identify per month so the transition plays on change.
        .id(monthOffset)
        .transition(
            .asymmetric(
                insertion: .move(edge: slideEdge).combined(with: .opacity),
                removal: .move(edge: slideEdge == .trailing ? .leading : .trailing)
                    .combined(with: .opacity)
            )
        )
        .frame(maxWidth: .infinity, alignment: .top)
        .clipped()
    }

    private func dayCell(for date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let inMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)

        return Text(String(calendar.component(.day, from: date)))
            .font(.system(size: 15, weight: isToday ? .semibold : .regular))
            .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color.primary.opacity(0.25)))
            .frame(maxWidth: .infinity)
            .frame(height: Layout.rowHeight)
            .background {
                if isToday {
                    Circle().fill(accent).frame(width: Layout.todayCircleSize, height: Layout.todayCircleSize)
                }
            }
    }

    // MARK: - Actions

    private func changeMonth(by value: Int) {
        slideEdge = value > 0 ? .trailing : .leading
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            monthOffset += value
        }
    }

    private func goToToday() {
        guard monthOffset != 0 else { return }
        slideEdge = monthOffset > 0 ? .leading : .trailing
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            monthOffset = 0
        }
    }

    /// Jumps the calendar to the first day of a specific month/year, computing
    /// the offset from "this month" and matching the existing slide animation.
    private func jumpTo(monthIndex: Int, year: Int) {
        let components = DateComponents(year: year, month: monthIndex + 1, day: 1)
        guard let target = calendar.date(from: components) else { return }
        let currentMonthStart = calendar.startOfMonth(for: Date())
        let monthsDiff = calendar.dateComponents([.month], from: currentMonthStart, to: target).month ?? 0
        guard monthsDiff != monthOffset else { return }
        slideEdge = monthsDiff > monthOffset ? .trailing : .leading
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            monthOffset = monthsDiff
        }
    }

    // MARK: - Picker bindings

    private var monthBinding: Binding<Int> {
        Binding(
            get: { displayedMonthIndex },
            set: { newIndex in jumpTo(monthIndex: newIndex, year: displayedYear) }
        )
    }

    private var displayedMonthIndex: Int {
        calendar.component(.month, from: displayedMonth) - 1
    }

    private var displayedYear: Int {
        calendar.component(.year, from: displayedMonth)
    }

    /// 200-year window centered on the current year — wide enough to feel like
    /// an open-ended scrolling picker without being unbounded.
    private var yearRange: ClosedRange<Int> {
        let thisYear = calendar.component(.year, from: Date())
        return (thisYear - 100)...(thisYear + 100)
    }

    // MARK: - Derived values

    private var displayedMonth: Date {
        let base = calendar.startOfMonth(for: Date())
        return calendar.date(byAdding: .month, value: monthOffset, to: base) ?? base
    }

    private var monthName: String {
        // Update the cached formatter's calendar and locale to match current settings
        Self.monthFormatter.calendar = calendar
        Self.monthFormatter.locale = calendar.locale
        return Self.monthFormatter.string(from: displayedMonth)
    }

    private var yearString: String {
        String(calendar.component(.year, from: displayedMonth))
    }

    /// Always 42 days (six weeks) so the popover height is stable regardless of
    /// whether a month spans five or six visual rows.
    private var monthDays: [Date] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else {
            assertionFailure("Failed to compute calendar intervals for \(displayedMonth)")
            return []
        }

        var dates: [Date] = []
        var date = firstWeek.start
        for _ in 0..<Layout.totalDays {
            dates.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return dates
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}

/// Scrolling year picker presented in a popover. Auto-scrolls to the selected
/// year on appear and highlights it with the calendar's accent color.
private struct YearPickerPopover: View {
    let selectedYear: Int
    let yearRange: ClosedRange<Int>
    let accent: Color
    let onSelect: (Int) -> Void

    private enum Layout {
        static let width: CGFloat = 120
        static let height: CGFloat = 220
        static let rowHeight: CGFloat = 28
        static let verticalPadding: CGFloat = 4
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(yearRange), id: \.self) { year in
                        yearRow(year)
                    }
                }
                .padding(.vertical, Layout.verticalPadding)
            }
            .frame(width: Layout.width, height: Layout.height)
            .onAppear {
                proxy.scrollTo(selectedYear, anchor: .center)
            }
        }
    }

    private func yearRow(_ year: Int) -> some View {
        let isSelected = year == selectedYear
        return Button {
            onSelect(year)
        } label: {
            HStack {
                Text(verbatim: String(year))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: Layout.rowHeight)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accent)
                        .padding(.horizontal, 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(year)
    }
}

#Preview {
    CalendarPopoverView()
}
