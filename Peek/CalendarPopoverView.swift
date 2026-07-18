import SwiftUI

/// Compact month calendar shown in the popover. Fixed 300pt wide, adapts to
/// light/dark automatically, and keeps a stable height by always laying out
/// six week rows of fixed height.
struct CalendarPopoverView: View {
    /// App-lifetime next-meeting source owned by `AppDelegate`; nil in
    /// previews, which simply hides the banner.
    var nextMeetingModel: NextMeetingModel?

    /// App-lifetime badge source owned by `AppDelegate`; clicking today's cell
    /// acknowledges the agenda and clears the menu bar dot. Nil in previews.
    var todayBadgeModel: TodayBadgeModel?

    // MARK: - Constants
    
    private enum Layout {
        static let popoverWidth: CGFloat = 300
        static let rowHeight: CGFloat = 36
        static let padding: CGFloat = 16
        static let daysPerWeek = 7
        static let numberOfWeeks = 6
        static let totalDays = daysPerWeek * numberOfWeeks // 42
        static let todayCircleSize: CGFloat = 32
        static let eventDotSize: CGFloat = 4
        static let eventDotSpacing: CGFloat = 2
        static let eventDotNudge: CGFloat = -1
        static let headerSpacing: CGFloat = 5
        /// Height of the header nav chips (chevron circles and Today capsule),
        /// with the shared grey fill that adapts to light/dark mode.
        static let navChipSize: CGFloat = 24
        static let navChipFill = Color.primary.opacity(0.08)
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
    /// Source of which displayed days have events or due reminders, and the
    /// per-day rows behind each cell's popover.
    @State private var events = CalendarEventsModel()
    /// The day whose events popover is currently open, if any.
    @State private var selectedDate: Date?
    /// The day currently under the pointer, for the hover highlight.
    @State private var hoveredDate: Date?

    /// Calendar-style red used for the "today" circle and the year picker
    /// selection, matching Apple's Calendar app regardless of the user's
    /// system accent color.
    private let accent = Color(nsColor: .systemRed)
    
    /// The user's calendar, honoring their system "first day of week" setting so
    /// the grid aligns with Apple's Calendar app and the current region.
    private var calendar: Calendar { Calendar.current }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: Layout.daysPerWeek)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.contentSpacing) {
            if let model = nextMeetingModel, let meeting = model.nextMeeting {
                NextMeetingBanner(meeting: meeting, accent: accent) {
                    model.joinNextMeeting()
                }
            }
            header
            weekdayRow
            grid
            if events.accessDenied {
                accessDeniedFooter
            }
        }
        .padding(Layout.padding)
        .frame(width: Layout.popoverWidth)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { changeMonth(by: -1); return .handled }
        .onKeyPress(.rightArrow) { changeMonth(by: 1); return .handled }
        .onKeyPress(.upArrow) { changeMonth(by: -12); return .handled }
        .onKeyPress(.downArrow) { changeMonth(by: 12); return .handled }
        .onAppear {
            isFocused = true
            events.load(days: monthDays, calendar: calendar)
        }
        .onChange(of: monthOffset) {
            selectedDate = nil
            hoveredDate = nil
            events.load(days: monthDays, calendar: calendar)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.headerSpacing) {
            monthMenu
            yearButton

            Spacer()

            // Previous / Today / Next cluster, matching Calendar.app's grey
            // chip styling: circular chips for the chevrons, a capsule for
            // "Today". Center-aligned within its own stack so the chip
            // outlines line up regardless of the row's baseline alignment.
            HStack(spacing: Layout.headerSpacing) {
                Button { changeMonth(by: -1) } label: { chevron("chevron.left") }
                    .buttonStyle(.plain)
                Button(action: goToToday) {
                    Text(String(localized: "Today"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        // Never let the label compress away when the header
                        // runs tight; the month/year side yields instead.
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: Layout.navChipSize)
                        .background(Capsule().fill(Layout.navChipFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Today"))
                Button { changeMonth(by: 1) } label: { chevron("chevron.right") }
                    .buttonStyle(.plain)
            }
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

    // MARK: - Access-denied footer

    /// Shown when calendar access is denied so users know why no event dots
    /// appear, with a shortcut to the relevant System Settings pane.
    private var accessDeniedFooter: some View {
        HStack(spacing: 4) {
            Text(String(localized: "Calendar access is off."))
                .foregroundStyle(.secondary)
            Button(String(localized: "Open Settings")) {
                let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                if let url = URL(string: pane) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity)
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: Layout.navChipSize, height: Layout.navChipSize)
            .background(Circle().fill(Layout.navChipFill))
            .contentShape(Circle())
    }

    // MARK: - Weekday header

    private var weekdayRow: some View {
        // Weekday short symbols repeat across the week ("S" for Sun/Sat,
        // "T" for Tue/Thu in en), so they can't serve as stable IDs. Index
        // the row by column position instead.
        //
        // `veryShortWeekdaySymbols` is always Sunday-first, so rotate it to
        // match the calendar's `firstWeekday` and the day grid below.
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        let ordered = Array(symbols[shift...] + symbols[..<shift])
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(ordered.indices, id: \.self) { index in
                Text(ordered[index])
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
        let hasEvent = events.hasEvents(on: date, calendar: calendar)
        let hasReminder = events.hasReminders(on: date, calendar: calendar)
        let isSelected = isSameDay(selectedDate, date)
        let isHovered = isSameDay(hoveredDate, date)

        return VStack(spacing: 2) {
            Text(String(calendar.component(.day, from: date)))
                .font(.system(size: 15, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color.primary.opacity(0.25)))
                .frame(maxWidth: .infinity)
                .background {
                    dayHighlight(isToday: isToday, isSelected: isSelected, isHovered: isHovered)
                }

            // Reserve the dots' space on every cell so row height stays
            // stable; the HStack centers whichever dots are present.
            HStack(spacing: Layout.eventDotSpacing) {
                if hasEvent {
                    agendaDot(events.eventDotColor, isToday: isToday, inMonth: inMonth)
                }
                if hasReminder {
                    agendaDot(events.reminderDotColor, isToday: isToday, inMonth: inMonth)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.eventDotSize)
            // Nudge the dots toward the digit without affecting layout.
            .offset(y: Layout.eventDotNudge)
        }
        .frame(height: Layout.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { toggleSelection(date) }
        .onHover { hovering in
            if hovering {
                hoveredDate = date
            } else if isSameDay(hoveredDate, date) {
                hoveredDate = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .popover(isPresented: selectionBinding(for: date), arrowEdge: .bottom) {
            DayEventsPopover(
                date: date,
                items: events.items(on: date, calendar: calendar),
                accent: accent,
                toggleReminder: { events.setReminderCompleted($0, $1) }
            )
        }
    }

    /// Circular highlight behind a day number. Precedence: today (filled accent)
    /// over the selected day (system grey selection fill) over hover (faint
    /// fill). Sizes all states to the same circle so they swap without shifting
    /// the layout.
    @ViewBuilder
    private func dayHighlight(isToday: Bool, isSelected: Bool, isHovered: Bool) -> some View {
        let size = Layout.todayCircleSize
        if isToday {
            Circle().fill(accent).frame(width: size, height: size)
        } else if isSelected {
            // Apple's standard grey for selected, unemphasized content —
            // adapts to light and dark mode automatically.
            Circle().fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                .frame(width: size, height: size)
        } else if isHovered {
            Circle().fill(Color.primary.opacity(0.08)).frame(width: size, height: size)
        }
    }

    private func isSameDay(_ lhs: Date?, _ rhs: Date) -> Bool {
        lhs.map { calendar.isDate($0, inSameDayAs: rhs) } ?? false
    }

    /// A single agenda dot in the given calendar/list color.
    private func agendaDot(_ color: Color, isToday: Bool, inMonth: Bool) -> some View {
        // Today's dots overlap the filled accent circle behind the day number,
        // so they must contrast with the circle, not the popover background.
        let fill = isToday ? Color.white : (inMonth ? color : color.opacity(0.4))
        return Circle()
            .fill(fill)
            .frame(width: Layout.eventDotSize, height: Layout.eventDotSize)
    }

    // MARK: - Day selection

    private func toggleSelection(_ date: Date) {
        selectedDate = isSameDay(selectedDate, date) ? nil : date
        // Opening today's agenda counts as having seen it, wherever today's
        // cell appears (it can be an adjacent-month cell in the grid).
        if selectedDate != nil, calendar.isDateInToday(date) {
            todayBadgeModel?.acknowledgeToday()
        }
    }

    /// Per-cell presentation binding so the popover anchors to the tapped day.
    private func selectionBinding(for date: Date) -> Binding<Bool> {
        Binding(
            get: { isSameDay(selectedDate, date) },
            set: { isPresented in if !isPresented { selectedDate = nil } }
        )
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
        displayedMonth.formatted(.dateTime.month(.wide))
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

/// Popover listing a single day's events and reminders, presented when a day
/// cell is tapped. Events show a filled dot in their calendar's color;
/// reminders show a circular checkbox in their list's color that toggles
/// completion, matching Calendar.app. Falls back to "No Events" when the day
/// is empty.
private struct DayEventsPopover: View {
    let date: Date
    let items: [DayItem]
    let accent: Color
    let toggleReminder: (String, Bool) -> Void

    private enum Layout {
        static let width: CGFloat = 240
        static let maxListHeight: CGFloat = 240
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if items.isEmpty {
                Text(String(localized: "No Events"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { item in
                            itemRow(item)
                        }
                    }
                }
                .frame(maxHeight: Layout.maxListHeight)
            }
        }
        .padding(14)
        .frame(width: Layout.width)
    }

    private func itemRow(_ item: DayItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            switch item.kind {
            case .event:
                Circle()
                    .fill(item.color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 3)
            case .reminder(let isCompleted, let reminderID):
                Button {
                    toggleReminder(reminderID, !isCompleted)
                } label: {
                    Image(systemName: isCompleted ? "circle.inset.filled" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(item.color)
                }
                .buttonStyle(.plain)
                .help(isCompleted
                    ? String(localized: "Mark reminder incomplete")
                    : String(localized: "Mark reminder complete"))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isCompletedReminder(item) ? .secondary : .primary)
                    .lineLimit(2)
                Text(item.timeText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let url = item.joinURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(accent)
                .help(String(localized: "Join meeting"))
            }
        }
    }

    private func isCompletedReminder(_ item: DayItem) -> Bool {
        if case .reminder(let isCompleted, _) = item.kind { return isCompleted }
        return false
    }
}

/// Banner pinned above the month header showing the next joinable meeting,
/// with a one-click Join button. The countdown re-renders each minute.
private struct NextMeetingBanner: View {
    let meeting: NextMeeting
    let accent: Color
    let join: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "video.fill")
                .font(.system(size: 13))
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                TimelineView(.everyMinute) { context in
                    Text("\(meeting.countdownText(at: context.date)) · \(meeting.startDate.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Button(String(localized: "Join"), action: join)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(accent)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }
}

#Preview {
    CalendarPopoverView()
}
