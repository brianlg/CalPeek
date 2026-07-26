import EventKit
import os
import SwiftUI

/// Compact month calendar shown in the popover. Fixed 300pt wide, adapts to
/// light/dark automatically, and keeps a stable height by always laying out
/// six week rows of fixed height.
struct CalendarPopoverView: View {
    // MARK: - Constants
    
    private enum Layout {
        static let popoverWidth: CGFloat = 300
        static let rowHeight: CGFloat = 36
        static let padding: CGFloat = 16
        static let daysPerWeek = 7
        static let numberOfWeeks = 6
        static let totalDays = daysPerWeek * numberOfWeeks // 42
        /// Today, hover, and selection circles share one size so highlight
        /// states swap without shifting the layout.
        static let todayCircleSize: CGFloat = 34
        static let dayCircleSize: CGFloat = 34
        static let eventDotSize: CGFloat = 4
        /// Width of the see-through ring punched out of the today circle
        /// around each dot.
        static let eventDotCutoutWidth: CGFloat = 0
        static let eventDotSpacing: CGFloat = 2
        static let eventDotNudge: CGFloat = -1.5
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

    /// Honors the system Reduce Motion setting (HIG requirement): month
    /// changes swap the slide-in grid transition for a plain crossfade.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(Preferences.todayMarkerColorKey)
    private var todayMarkerRaw = WeekdayColor.auto.rawValue
    @AppStorage(Preferences.calendarEventsColorKey)
    private var calendarEventsRaw = WeekdayColor.auto.rawValue
    @AppStorage(Preferences.remindersColorKey)
    private var remindersRaw = WeekdayColor.auto.rawValue

    /// Accent for the "today" circle, year picker selection, and other
    /// highlights. Automatic is Calendar-app red regardless of the system
    /// accent; the user can pick another color in Appearance settings.
    private var accent: Color {
        (WeekdayColor(rawValue: todayMarkerRaw) ?? .auto).overrideColor
            ?? Color(nsColor: .systemRed)
    }

    /// Month-grid dot tints, honoring the Appearance overrides and falling
    /// back to the user's default calendar/list colors.
    private var eventDotColor: Color {
        (WeekdayColor(rawValue: calendarEventsRaw) ?? .auto).overrideColor ?? events.eventDotColor
    }
    private var reminderDotColor: Color {
        (WeekdayColor(rawValue: remindersRaw) ?? .auto).overrideColor ?? events.reminderDotColor
    }
    
    /// The user's calendar, honoring their system "first day of week" setting so
    /// the grid aligns with Apple's Calendar app and the current region.
    private var calendar: Calendar { Calendar.current }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: Layout.daysPerWeek)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.contentSpacing) {
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
        // The popover's view (and its @State) lives for the app's lifetime
        // and `onAppear` fires only once, so `AppDelegate` signals each open;
        // every open starts fresh on the current month.
        .onReceive(NotificationCenter.default.publisher(for: .popoverWillShow)) { _ in
            monthOffset = 0
            selectedDate = nil
            hoveredDate = nil
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
        // The row centers the title block against the chip cluster (baseline
        // alignment would hang the 12pt chip text from the 17pt title's
        // baseline, floating the title ~2pt high); within the title block,
        // month and year still share a baseline.
        HStack(alignment: .center, spacing: Layout.headerSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: Layout.headerSpacing) {
                monthMenu
                yearButton
            }

            Spacer()

            // Previous / Today / Next cluster, matching Calendar.app's grey
            // chip styling: circular chips for the chevrons, a capsule for
            // "Today".
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
                // Never wrap the year onto a second line when the header runs
                // tight (September is the widest month name).
                .fixedSize()
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
        .transition(monthTransition)
        .frame(maxWidth: .infinity, alignment: .top)
        // Hide the horizontal month-slide transition without cutting off the
        // highlight circles, which overhang the top row's bounds (they're
        // taller than the day-number text they center on): clip the sides
        // tight but give the mask vertical slack.
        .mask(Rectangle().padding(.vertical, -Layout.todayCircleSize / 2))
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
                // Today's digit sits on the accent fill, so its color derives
                // from the accent — white on yellow would be unreadable.
                .foregroundStyle(isToday ? accent.contrastingForeground : (inMonth ? Color.primary : Color.primary.opacity(0.25)))
                .frame(maxWidth: .infinity)
                .background {
                    dayHighlight(isToday: isToday, isSelected: isSelected, isHovered: isHovered)
                }

            // Reserve the dots' space on every cell so row height stays
            // stable; the HStack centers whichever dots are present.
            HStack(spacing: Layout.eventDotSpacing) {
                if hasEvent {
                    agendaDot(eventDotColor, isToday: isToday, inMonth: inMonth)
                }
                if hasReminder {
                    agendaDot(reminderDotColor, isToday: isToday, inMonth: inMonth)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.eventDotSize)
            // Nudge the dots toward the digit without affecting layout.
            .offset(y: Layout.eventDotNudge)
        }
        // Flatten the cell so the dots' destinationOut cutout erases the
        // accent circle in this layer only, not views behind the grid.
        .compositingGroup()
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
            DayEventsPopover(date: date, model: events, calendar: calendar, accent: accent)
        }
    }

    /// Circular highlight behind a day number. Precedence: today (filled accent)
    /// over the selected day (system grey selection fill) over hover (faint
    /// fill). Selection and hover share one circle size so they swap without
    /// shifting the layout; today's circle is a touch larger.
    @ViewBuilder
    private func dayHighlight(isToday: Bool, isSelected: Bool, isHovered: Bool) -> some View {
        let size = Layout.dayCircleSize
        if isToday {
            Circle().fill(accent)
                .frame(width: Layout.todayCircleSize, height: Layout.todayCircleSize)
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
        let fill = isToday ? accent.contrastingForeground : (inMonth ? color : color.opacity(0.4))
        return Circle()
            .fill(fill)
            .frame(width: Layout.eventDotSize, height: Layout.eventDotSize)
            .background {
                // Punch a see-through ring out of the accent circle so the dot
                // looks cut into it; destinationOut erases the cell's layer
                // (see the compositingGroup on the cell) down to the popover
                // background rather than showing red under the ring.
                if isToday {
                    let cutout = Layout.eventDotSize + Layout.eventDotCutoutWidth * 2
                    Circle()
                        .frame(width: cutout, height: cutout)
                        .blendMode(.destinationOut)
                }
            }
    }

    // MARK: - Day selection

    private func toggleSelection(_ date: Date) {
        selectedDate = isSameDay(selectedDate, date) ? nil : date
    }

    /// Per-cell presentation binding so the popover anchors to the tapped day.
    private func selectionBinding(for date: Date) -> Binding<Bool> {
        Binding(
            get: { isSameDay(selectedDate, date) },
            set: { isPresented in if !isPresented { selectedDate = nil } }
        )
    }

    // MARK: - Actions

    /// The horizontal slide, or a short crossfade under Reduce Motion.
    private var monthTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: slideEdge).combined(with: .opacity),
            removal: .move(edge: slideEdge == .trailing ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    private var monthChangeAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.35, dampingFraction: 0.82)
    }

    private func changeMonth(by value: Int) {
        slideEdge = value > 0 ? .trailing : .leading
        withAnimation(monthChangeAnimation) {
            monthOffset += value
        }
    }

    private func goToToday() {
        guard monthOffset != 0 else { return }
        slideEdge = monthOffset > 0 ? .leading : .trailing
        withAnimation(monthChangeAnimation) {
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
        withAnimation(monthChangeAnimation) {
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
                    .foregroundStyle(isSelected ? accent.contrastingForeground : Color.primary)
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
/// completion, matching Calendar.app. Falls back to "Nothing here." when the
/// day is empty.
private struct DayEventsPopover: View {
    let date: Date
    let model: CalendarEventsModel
    let calendar: Calendar
    let accent: Color

    private enum Mode {
        case list, create, edit
        /// Shown instead of `create`/`edit` when the trial has ended and
        /// Peek Pro isn't purchased; offers a route to the unlock screen.
        case locked
    }

    private let store = Store.shared

    @State private var mode: Mode = .list
    /// The re-fetched item behind edit mode; set by `beginEditing` just
    /// before the mode switch and cleared on dismiss.
    @State private var editTarget: NewItemForm.EditTarget?
    /// Measured height of the list's row stack, so the ScrollView can report
    /// a real ideal height to the popover (see `listContent`).
    @State private var listHeight: CGFloat = 0

    @AppStorage(Preferences.calendarEventsColorKey)
    private var calendarEventsRaw = WeekdayColor.auto.rawValue
    @AppStorage(Preferences.remindersColorKey)
    private var remindersRaw = WeekdayColor.auto.rawValue

    /// Row glyph tint: the Appearance override for the item's kind, or the
    /// item's own calendar/list color when set to Automatic.
    private func tint(for item: DayItem) -> Color {
        switch item.kind {
        case .event:
            return (WeekdayColor(rawValue: calendarEventsRaw) ?? .auto).overrideColor ?? item.color
        case .reminder:
            return (WeekdayColor(rawValue: remindersRaw) ?? .auto).overrideColor ?? item.color
        }
    }

    private enum Layout {
        static let width: CGFloat = 240
        static let formWidth: CGFloat = 280
        static let maxListHeight: CGFloat = 240
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch mode {
            case .list:
                HStack(spacing: 6) {
                    Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    plusControl
                }
                listContent
            case .create:
                NewItemForm(date: date, model: model, calendar: calendar, accent: accent) { mode = .list }
            case .edit:
                if let editTarget {
                    NewItemForm(editing: editTarget, model: model, calendar: calendar, accent: accent) {
                        mode = .list
                        self.editTarget = nil
                    }
                }
            case .locked:
                lockedContent
            }
        }
        .padding(14)
        .frame(width: mode == .create || mode == .edit ? Layout.formWidth : Layout.width)
        .animation(.easeOut(duration: 0.12), value: mode)
    }

    @ViewBuilder
    private var listContent: some View {
        let items = model.items(on: date, calendar: calendar)
        if items.isEmpty {
            Text(String(localized: "Nothing here."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                // Menu-like agenda: bare rows on the popover material, each
                // highlighting under the pointer (see ItemRow), as in
                // Control Center and the system status menus.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        ItemRow(
                            item: item,
                            tint: tint(for: item),
                            accent: accent,
                            model: model,
                            onEdit: item.isEditable ? { beginEditing(item) } : nil,
                            onLocked: { mode = .locked }
                        )
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    listHeight = height
                }
            }
            // A ScrollView has no ideal height of its own, so after the
            // popover shrinks for a form it would stay small instead of
            // refitting the list. Sizing it to the measured row stack keeps
            // NSPopover's contentSize tracking the real list height.
            .frame(height: listHeight > 0 ? min(listHeight, Layout.maxListHeight) : nil)
        }
    }

    /// The header "+" control: opens the creation form (which defaults to a
    /// new event when events are writable). Hidden when nothing can be
    /// created.
    @ViewBuilder
    private var plusControl: some View {
        if model.canCreateEvents || model.canCreateReminders {
            Button {
                mode = store.hasFullAccess ? .create : .locked
            } label: {
                plusGlyph
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(model.canCreateEvents
                ? String(localized: "New Event")
                : String(localized: "New Reminder"))
        }
    }

    /// Upsell shown when a write affordance is used without full access:
    /// a short pitch and a route to the unlock screen. Deliberately quiet —
    /// the popover is something the user sees many times a day.
    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "Peek Pro"), systemImage: "sparkles")
                .font(.system(size: 13, weight: .semibold))
            Text(String(localized: "Creating and editing events and reminders needs Peek Pro. Viewing your calendar stays free."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(String(localized: "Not Now")) { mode = .list }
                Spacer(minLength: 0)
                Button(String(localized: "Unlock…")) {
                    mode = .list
                    NotificationCenter.default.post(name: .openProSettings, object: nil)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Plus icon styled to match the month header's chevron chips.
    private var plusGlyph: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.primary)
    }

    /// Re-fetches the clicked row's backing EK object and switches to the
    /// editor. Silently stays in the list if the item vanished from the
    /// store between render and click.
    private func beginEditing(_ item: DayItem) {
        guard store.hasFullAccess else {
            mode = .locked
            return
        }
        switch item.kind {
        case .event:
            guard let identifier = item.eventIdentifier,
                  let event = model.event(withIdentifier: identifier, startingAt: item.sortDate, calendar: calendar)
            else { return }
            editTarget = .event(event)
        case .reminder(_, let reminderID):
            guard let reminder = model.reminder(withIdentifier: reminderID) else { return }
            editTarget = .reminder(reminder)
        }
        mode = .edit
    }
}

/// One agenda row. A separate view so each row owns its hover state, which
/// reveals the open-in-app button on its trailing edge. Clicking the row
/// itself opens the in-popover editor when the item is editable.
private struct ItemRow: View {
    let item: DayItem
    let tint: Color
    let accent: Color
    let model: CalendarEventsModel
    /// Opens the editor for this row; nil when the item's calendar is
    /// read-only, which leaves the row inert.
    let onEdit: (() -> Void)?
    /// Invoked when a write affordance (the reminder checkbox) is used
    /// without full access, so the parent can show the unlock prompt.
    let onLocked: () -> Void

    /// Dismisses the day popover when the user jumps to Calendar/Reminders.
    @Environment(\.dismiss) private var dismiss
    @State private var isHovered = false

    var body: some View {
        // The open button sits outside the top-aligned content so it centers
        // against the full row height.
        HStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                switch item.kind {
                case .event:
                    // Same glyph metrics as the reminder checkbox below so the
                    // two dot styles line up in a mixed list.
                    Image(systemName: "circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(tint)
                case .reminder(let isCompleted, let reminderID):
                    Button {
                        if Store.shared.hasFullAccess {
                            model.setReminderCompleted(reminderID, !isCompleted)
                        } else {
                            onLocked()
                        }
                    } label: {
                        Image(systemName: isCompleted ? "circle.inset.filled" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                    .help(isCompleted
                        ? String(localized: "Mark reminder incomplete")
                        : String(localized: "Mark reminder complete"))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 13))
                        .foregroundStyle(isCompletedReminder ? .secondary : .primary)
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

            Button {
                switch item.kind {
                case .event:
                    // Sandbox-safe plain activation: Calendar has no deep
                    // link to a date or event, and AppleScript navigation
                    // would need an Apple-events entitlement the App Store
                    // doesn't allow. In-popover editing covers the rest.
                    if let app = NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: "com.apple.iCal"
                    ) {
                        NSWorkspace.shared.openApplication(at: app, configuration: .init())
                    }
                case .reminder:
                    // The deep link is a private scheme; if the OS stops
                    // handling it, still get the user into Reminders.
                    if let url = item.openURL, !NSWorkspace.shared.open(url) {
                        Logger.peek.error("Reminders deep link no longer handled; launching app instead")
                        if let app = NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: "com.apple.reminders"
                        ) {
                            NSWorkspace.shared.openApplication(at: app, configuration: .init())
                        }
                    }
                }
                dismiss()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            // Fades rather than inserts so revealing it never reflows
            // the row.
            .opacity(isHovered ? 1 : 0)
            .help(item.kind == .event
                ? String(localized: "Open Calendar")
                : String(localized: "Open in Reminders"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // Rounded hover highlight, like menu items in Control Center.
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(isHovered ? 0.08 : 0)))
        // The row's hover region is only its hit-testable content by default,
        // which excludes the spacer gap and the faded-out button — hovering
        // there would drop `isHovered` before the button could be clicked.
        .contentShape(Rectangle())
        // The nested buttons (checkbox, join, open-in-app) win their own
        // clicks; the gesture only sees the rest of the row.
        .onTapGesture { onEdit?() }
        .accessibilityAddTraits(onEdit == nil ? [] : .isButton)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var isCompletedReminder: Bool {
        if case .reminder(let isCompleted, _) = item.kind { return isCompleted }
        return false
    }
}

/// Borderless date/time field with individually clickable, typeable segments
/// (month, day, year, hour, minute, AM/PM), matching the Calendar app's event
/// inspector. SwiftUI's DatePicker always draws a bezel, so this wraps
/// NSDatePicker's text-field style directly.
private struct SegmentedDateField: NSViewRepresentable {
    @Binding var date: Date
    /// Which segments this field shows (date-only or time-only). Date and
    /// time are separate fields side by side rather than one combined picker,
    /// which would insert the locale's "," between them.
    var elements: NSDatePicker.ElementFlags
    /// Draws the system's bezeled text-field-and-stepper style instead of
    /// the borderless inline one.
    var showsStepper = false

    func makeNSView(context: Context) -> NSDatePicker {
        // Padded subclass so single-digit months/days render as "07/28/2026",
        // matching Calendar.app.
        let picker = PaddedDatePicker()
        picker.datePickerStyle = showsStepper ? .textFieldAndStepper : .textField
        picker.isBezeled = showsStepper
        picker.isBordered = false
        picker.drawsBackground = false
        picker.font = .systemFont(ofSize: 12)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        picker.datePickerElements = elements
        if picker.dateValue != date {
            picker.dateValue = date
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: SegmentedDateField

        init(_ parent: SegmentedDateField) {
            self.parent = parent
        }

        @objc func dateChanged(_ sender: NSDatePicker) {
            parent.date = sender.dateValue
        }
    }
}

/// Inline creation form shown inside the day popover. One view handles both
/// events and reminders, switched by a capsule segmented control in place of
/// the date heading; keeping it a single view preserves the title and each
/// kind's fields while the user flips between the two.
/// Repeat presets matching Calendar.app's quick-create options. An existing
/// item whose rule doesn't map to a preset keeps its rule untouched and shows
/// a read-only "Custom" in the editor.
enum RepeatOption: String, CaseIterable, Identifiable {
    case never, daily, weekly, monthly, yearly, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never: String(localized: "Never")
        case .daily: String(localized: "Every Day")
        case .weekly: String(localized: "Every Week")
        case .monthly: String(localized: "Every Month")
        case .yearly: String(localized: "Every Year")
        case .custom: String(localized: "Custom…")
        }
    }

    /// The preset's rule. Nil for Never and for Custom, whose rule lives in
    /// the form's `CustomRepeat` value instead.
    var rule: EKRecurrenceRule? {
        let frequency: EKRecurrenceFrequency
        switch self {
        case .never, .custom: return nil
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)
    }

    /// The preset equivalent to an item's recurrence rules, or nil when the
    /// rules carry anything a preset can't express (interval, end, specific
    /// days) and must be preserved as-is. A weekly rule pinned to a single
    /// weekday still counts as "Every Week" — that's how Calendar.app stores
    /// its own quick-create weekly rule.
    static func matching(_ rules: [EKRecurrenceRule]?) -> RepeatOption? {
        guard let rules, !rules.isEmpty else { return .never }
        guard rules.count == 1 else { return nil }
        let rule = rules[0]
        guard rule.interval == 1, rule.recurrenceEnd == nil,
              rule.daysOfTheMonth == nil, rule.monthsOfTheYear == nil,
              rule.weeksOfTheYear == nil, rule.daysOfTheYear == nil,
              rule.setPositions == nil,
              rule.daysOfTheWeek == nil
                  || (rule.frequency == .weekly && rule.daysOfTheWeek?.count == 1)
        else { return nil }
        switch rule.frequency {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        @unknown default: return nil
        }
    }
}

/// A recurrence the form's Custom dialog can express — the core of
/// Calendar.app's Custom repeat dialog: frequency, "every N" interval, and
/// specific weekdays when weekly. Rules carrying anything more (an end,
/// monthly/yearly day patterns, positional weekdays) stay read-only.
struct CustomRepeat: Equatable {
    var frequency: EKRecurrenceFrequency = .weekly
    var interval: Int = 1
    /// `EKWeekday` raw values (1 = Sunday); only meaningful for `.weekly`.
    /// Empty falls back to the item's start weekday, as EventKit itself
    /// does for a weekly rule with no explicit days.
    var weekdays: Set<Int> = []

    /// The dialog-expressible equivalent of an item's rules, or nil when
    /// they must be preserved read-only. Checked after `RepeatOption
    /// .matching`, so simple presets never reach here.
    static func matching(_ rules: [EKRecurrenceRule]?) -> CustomRepeat? {
        guard let rules, rules.count == 1 else { return nil }
        let rule = rules[0]
        guard rule.recurrenceEnd == nil, rule.interval >= 1,
              rule.daysOfTheMonth == nil, rule.monthsOfTheYear == nil,
              rule.weeksOfTheYear == nil, rule.daysOfTheYear == nil,
              rule.setPositions == nil
        else { return nil }
        var weekdays: Set<Int> = []
        if let days = rule.daysOfTheWeek {
            // Positional entries ("first Monday") only make sense for
            // monthly/yearly patterns the dialog doesn't cover.
            guard rule.frequency == .weekly, days.allSatisfy({ $0.weekNumber == 0 }) else { return nil }
            weekdays = Set(days.map { $0.dayOfTheWeek.rawValue })
        }
        switch rule.frequency {
        case .daily, .weekly, .monthly, .yearly:
            return CustomRepeat(frequency: rule.frequency, interval: rule.interval, weekdays: weekdays)
        @unknown default:
            return nil
        }
    }

    var rule: EKRecurrenceRule {
        let days: [EKRecurrenceDayOfWeek]? = frequency == .weekly && !weekdays.isEmpty
            ? weekdays.sorted().compactMap { EKWeekday(rawValue: $0).map { EKRecurrenceDayOfWeek($0) } }
            : nil
        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: max(1, interval),
            daysOfTheWeek: days,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
    }
}

/// Alert presets matching Calendar.app's quick-create options. `.atTime`
/// applies to events only — timed reminders already alert at their due
/// time, so their picker offers just the early offsets. As with repeats,
/// alarms no preset can express are preserved untouched and shown as
/// "Custom" in the editor.
enum AlertOption: String, CaseIterable, Identifiable {
    case none, atTime, minutes5, minutes10, minutes30, hour1, day1

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: String(localized: "None")
        case .atTime: String(localized: "At time of event")
        case .minutes5: String(localized: "5 minutes before")
        case .minutes10: String(localized: "10 minutes before")
        case .minutes30: String(localized: "30 minutes before")
        case .hour1: String(localized: "1 hour before")
        case .day1: String(localized: "1 day before")
        }
    }

    /// Seconds before the start/due time, or nil for no alert.
    var offset: TimeInterval? {
        switch self {
        case .none: nil
        case .atTime: 0
        case .minutes5: 5 * 60
        case .minutes10: 10 * 60
        case .minutes30: 30 * 60
        case .hour1: 60 * 60
        case .day1: 24 * 60 * 60
        }
    }

    /// The preset equivalent to an event's alarms, or nil when they can't be
    /// expressed as one (multiple alarms, absolute-date alarms, off-preset
    /// offsets) and must be preserved as-is.
    static func matching(eventAlarms alarms: [EKAlarm]?) -> AlertOption? {
        guard let alarms, !alarms.isEmpty else { return AlertOption.none }
        guard alarms.count == 1, alarms[0].absoluteDate == nil else { return nil }
        let offset = -alarms[0].relativeOffset
        return allCases.first { $0 != .none && $0.offset == offset }
    }

    /// The preset equivalent to a timed reminder's alarms, or nil when they
    /// must be preserved as-is. The form's created shape is an at-due-time
    /// alarm plus an optional early one, so exactly [due] maps to `.none`
    /// and [due, due − preset] maps to that preset.
    static func matching(reminderAlarms alarms: [EKAlarm]?, due: Date) -> AlertOption? {
        guard let alarms, !alarms.isEmpty else { return nil }
        let dates = alarms.compactMap(\.absoluteDate)
        guard dates.count == alarms.count, dates.contains(due) else { return nil }
        let extras = dates.filter { $0 != due }
        if extras.isEmpty { return AlertOption.none }
        guard extras.count == 1 else { return nil }
        let offset = due.timeIntervalSince(extras[0])
        guard offset > 0 else { return nil }
        return allCases.first { $0 != .none && $0 != .atTime && $0.offset == offset }
    }
}

private struct NewItemForm: View {
    enum Kind {
        case event, reminder
    }

    /// An existing item re-fetched for editing; the form prefills from it
    /// and saves back to it instead of creating.
    enum EditTarget {
        case event(EKEvent)
        case reminder(EKReminder)
    }

    let date: Date
    let model: CalendarEventsModel
    let calendar: Calendar
    let accent: Color
    let dismiss: () -> Void

    @State private var kind: Kind
    /// Tracks `kind` for the segmented control's sliding thumb, updated in
    /// its own `withAnimation` transaction. Animating off `kind` directly
    /// would also interpolate the popover-resize reposition (AppKit windows
    /// are bottom-origin), drifting the thumb vertically mid-slide.
    @State private var thumbKind: Kind
    @State private var title = ""
    @State private var isAllDay = false
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var selectedEventCalendarID: String
    @State private var selectedReminderListID: String
    @State private var reminderDate: Date
    @State private var reminderHasTime = false
    @State private var reminderTime: Date
    @State private var notes = ""
    @State private var repeatOption: RepeatOption = .never
    /// The Custom dialog's committed value; the active rule when
    /// `repeatOption == .custom`.
    @State private var customRepeat: CustomRepeat?
    @State private var showingCustomRepeat = false
    @State private var alertOption: AlertOption = .none
    /// True when the edited item's recurrence rules can't be expressed by a
    /// preset or the Custom dialog; the Repeat row shows a read-only
    /// "Custom" and saving leaves the rules untouched.
    @State private var customRecurrence = false
    /// Same as `customRecurrence`, for the item's alarms.
    @State private var customAlerts = false
    /// Which confirmation dialog is up: the recurring-item span choice on
    /// save/delete, or the plain delete confirmation.
    @State private var pendingConfirmation: PendingConfirmation?
    @State private var saveFailed = false
    @FocusState private var titleFocused: Bool
    /// Honors the system Reduce Motion setting: the segmented thumb snaps
    /// between segments instead of sliding.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let eventCalendars: [EKCalendar]
    private let reminderLists: [EKCalendar]
    /// Nil when creating; the item being edited otherwise.
    private let editTarget: EditTarget?

    private enum PendingConfirmation {
        case saveSpan, deleteSpan, delete
    }

    init(date: Date, model: CalendarEventsModel, calendar: Calendar, accent: Color, dismiss: @escaping () -> Void) {
        self.date = date
        self.model = model
        self.calendar = calendar
        self.accent = accent
        self.dismiss = dismiss
        editTarget = nil
        eventCalendars = model.writableEventCalendars()
        reminderLists = model.writableReminderCalendars()
        let initialKind: Kind = eventCalendars.isEmpty ? .reminder : .event
        _kind = State(initialValue: initialKind)
        _thumbKind = State(initialValue: initialKind)
        let start = Self.defaultStart(on: date, calendar: calendar)
        _startTime = State(initialValue: start)
        _endTime = State(initialValue: start.addingTimeInterval(3600))
        _reminderDate = State(initialValue: date)
        _reminderTime = State(initialValue: start)
        _selectedEventCalendarID = State(initialValue: eventCalendars.first?.calendarIdentifier ?? "")
        _selectedReminderListID = State(initialValue: reminderLists.first?.calendarIdentifier ?? "")
    }

    init(editing target: EditTarget, model: CalendarEventsModel, calendar: Calendar, accent: Color, dismiss: @escaping () -> Void) {
        self.model = model
        self.calendar = calendar
        self.accent = accent
        self.dismiss = dismiss
        editTarget = target
        eventCalendars = model.writableEventCalendars()
        reminderLists = model.writableReminderCalendars()

        switch target {
        case .event(let event):
            date = event.startDate
            _kind = State(initialValue: .event)
            _thumbKind = State(initialValue: .event)
            _title = State(initialValue: event.title ?? "")
            _isAllDay = State(initialValue: event.isAllDay)
            _startTime = State(initialValue: event.startDate)
            _endTime = State(initialValue: event.endDate)
            _reminderDate = State(initialValue: event.startDate)
            _reminderTime = State(initialValue: event.startDate)
            _selectedEventCalendarID = State(initialValue: event.calendar.calendarIdentifier)
            _selectedReminderListID = State(initialValue: reminderLists.first?.calendarIdentifier ?? "")
            _notes = State(initialValue: event.notes ?? "")
            let repeatState = Self.repeatState(for: event.recurrenceRules)
            _repeatOption = State(initialValue: repeatState.option)
            _customRepeat = State(initialValue: repeatState.custom)
            _customRecurrence = State(initialValue: repeatState.readOnly)
            // The all-day form hides the alert row entirely, so any alarms an
            // all-day event carries must survive a save untouched.
            let alertPreset = event.isAllDay && !(event.alarms ?? []).isEmpty
                ? nil
                : AlertOption.matching(eventAlarms: event.alarms)
            _alertOption = State(initialValue: alertPreset ?? .none)
            _customAlerts = State(initialValue: alertPreset == nil)
        case .reminder(let reminder):
            let components = reminder.dueDateComponents
            let due = components.flatMap { ($0.calendar ?? calendar).date(from: $0) } ?? Date()
            date = due
            _kind = State(initialValue: .reminder)
            _thumbKind = State(initialValue: .reminder)
            _title = State(initialValue: reminder.title ?? "")
            _isAllDay = State(initialValue: false)
            _startTime = State(initialValue: due)
            _endTime = State(initialValue: due.addingTimeInterval(3600))
            _reminderDate = State(initialValue: due)
            let hasTime = components?.hour != nil
            _reminderHasTime = State(initialValue: hasTime)
            _reminderTime = State(initialValue: due)
            _selectedEventCalendarID = State(initialValue: eventCalendars.first?.calendarIdentifier ?? "")
            _selectedReminderListID = State(initialValue: reminder.calendar.calendarIdentifier)
            _notes = State(initialValue: reminder.notes ?? "")
            let repeatState = Self.repeatState(for: reminder.recurrenceRules)
            _repeatOption = State(initialValue: repeatState.option)
            _customRepeat = State(initialValue: repeatState.custom)
            _customRecurrence = State(initialValue: repeatState.readOnly)
            let alertPreset: AlertOption? = hasTime
                ? AlertOption.matching(reminderAlarms: reminder.alarms, due: due)
                : ((reminder.alarms ?? []).isEmpty ? AlertOption.none : nil)
            _alertOption = State(initialValue: alertPreset ?? .none)
            _customAlerts = State(initialValue: alertPreset == nil)
        }
    }

    /// How an item's stored rules land in the Repeat row: a preset, the
    /// Custom dialog's value, or read-only preservation.
    private static func repeatState(
        for rules: [EKRecurrenceRule]?
    ) -> (option: RepeatOption, custom: CustomRepeat?, readOnly: Bool) {
        if let preset = RepeatOption.matching(rules) {
            return (preset, nil, false)
        }
        if let custom = CustomRepeat.matching(rules) {
            return (.custom, custom, false)
        }
        return (.never, nil, true)
    }

    /// Today opens at the next half-hour boundary (capped at 23:00); other
    /// days open at 9:00 AM.
    private static func defaultStart(on date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        guard calendar.isDateInToday(date) else {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
        }
        let now = Date()
        var hour = calendar.component(.hour, from: now)
        var minute = calendar.component(.minute, from: now)
        switch minute {
        case 0: break
        case 1...30: minute = 30
        default: minute = 0; hour += 1
        }
        if hour > 23 { hour = 23; minute = 0 }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart) ?? dayStart
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nil when the notes field is empty, so empty text never lands in the store.
    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Nil for no alert or an all-day event (whose picker is hidden).
    private var eventAlarm: EKAlarm? {
        guard !isAllDay, let offset = alertOption.offset else { return nil }
        return EKAlarm(relativeOffset: -offset)
    }

    /// The rule the current Repeat selection produces; nil for Never.
    private var selectedRecurrenceRule: EKRecurrenceRule? {
        repeatOption == .custom ? customRepeat?.rule : repeatOption.rule
    }

    private var canCreate: Bool {
        switch kind {
        case .event:
            return !trimmedTitle.isEmpty && (isAllDay || endTime > startTime)
        case .reminder:
            return !trimmedTitle.isEmpty
        }
    }

    var body: some View {
        formWithDialogs
            .onExitCommand(perform: dismiss)
            .onChange(of: kind) {
                saveFailed = false
                // "At time of event" isn't offered for reminders; drop it rather
                // than leave the picker pointing at a hidden option.
                if kind == .reminder, alertOption == .atTime {
                    alertOption = .none
                }
            }
            .onAppear {
                // The delayed request is load-bearing, not a hack: the popover
                // panel drops focus requests made while it swaps in the form.
                // Verified alternatives that do NOT work here: `defaultFocus`
                // (the focus scope activated when the popover opened, not when
                // the form appears), a synchronous set in `onAppear`, and
                // `.task` (still too early).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { titleFocused = true }
            }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            titleSection

            if kind == .event {
                eventFields
            } else {
                reminderFields
            }

            notesSection

            if saveFailed {
                Text(String(localized: "Couldn't save."))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            formFooter(
                primaryTitle: primaryTitle,
                primaryEnabled: canCreate,
                primary: primaryAction,
                delete: deleteAction,
                dismiss: dismiss
            )
        }
    }

    private var primaryTitle: String {
        editTarget == nil ? String(localized: "Create") : String(localized: "Save")
    }

    /// Nil when creating, which hides the footer's Delete button.
    private var deleteAction: (() -> Void)? {
        if editTarget == nil { return nil }
        return { deleteTapped() }
    }

    /// `formContent` with the editor's three dialogs attached — a separate
    /// computed view so each piece of `body` type-checks on its own.
    private var formWithDialogs: some View {
        formContent
            .confirmationDialog(
                String(localized: "This is a repeating event."),
                isPresented: confirmationBinding(.saveSpan),
                titleVisibility: .visible
            ) {
                Button(String(localized: "Save for This Event")) { applyEdits(span: .thisEvent) }
                Button(String(localized: "Save for All Future Events")) { applyEdits(span: .futureEvents) }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
            .confirmationDialog(
                String(localized: "This is a repeating event."),
                isPresented: confirmationBinding(.deleteSpan),
                titleVisibility: .visible
            ) {
                Button(String(localized: "Delete This Event"), role: .destructive) { deleteItem(span: .thisEvent) }
                Button(String(localized: "Delete All Future Events"), role: .destructive) { deleteItem(span: .futureEvents) }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
            .confirmationDialog(
                kind == .event
                    ? String(localized: "Delete this event?")
                    : String(localized: "Delete this reminder?"),
                isPresented: confirmationBinding(.delete),
                titleVisibility: .visible
            ) {
                Button(String(localized: "Delete"), role: .destructive) { deleteItem(span: .thisEvent) }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
    }

    /// Event/Reminder capsule switcher when creating and both kinds are
    /// writable, otherwise a plain heading — an existing item can't change
    /// kind, so the editor always gets the heading.
    @ViewBuilder
    private var header: some View {
        if editTarget != nil {
            Text(kind == .event
                ? String(localized: "Edit Event")
                : String(localized: "Edit Reminder"))
                .font(.system(size: 13, weight: .semibold))
        } else if !eventCalendars.isEmpty && !reminderLists.isEmpty {
            segmentedControl
        } else {
            Text(kind == .event
                ? String(localized: "New Event")
                : String(localized: "New Reminder"))
                .font(.system(size: 13, weight: .semibold))
        }
    }

    /// Capsule-style segmented control matching Calendar.app's Event/Reminder
    /// switcher; the selected segment fills with the today-circle accent.
    /// The selection thumb is a single persistent capsule that slides between
    /// segments (like the native control's) rather than a background inserted
    /// into the selected segment, which would animate in from its initial
    /// geometry while the popover is resizing.
    private var segmentedControl: some View {
        HStack(spacing: 0) {
            segment(String(localized: "Event"), .event)
            segment(String(localized: "Reminder"), .reminder)
        }
        .background(alignment: .leading) {
            GeometryReader { geo in
                Capsule()
                    .fill(accent)
                    .frame(width: geo.size.width / 2)
                    .offset(x: thumbKind == .reminder ? geo.size.width / 2 : 0)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private func segment(_ label: String, _ value: Kind) -> some View {
        Button {
            // The fields swap and the popover resizes instantly (as in
            // Calendar.app); only the thumb's slide is animated.
            kind = value
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { thumbKind = value }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(thumbKind == value ? accent.contrastingForeground : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(kind == value ? .isSelected : [])
    }

    // MARK: Sections

    /// Rounded card grouping related rows, styled after the inset sections
    /// in Calendar.app's event popover.
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
    }

    /// One labeled row inside a section card: label leading, control trailing.
    private func formRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
    }

    /// Separator between rows in a card, inset from the leading edge like
    /// grouped-form dividers.
    private var rowDivider: some View {
        Divider().padding(.leading, 10)
    }

    /// Prominent borderless title field with the calendar/list swatch picker
    /// on its trailing edge, matching Calendar.app's title section.
    private var titleSection: some View {
        sectionCard {
            HStack(spacing: 8) {
                TextField(
                    kind == .event
                        ? String(localized: "Event title")
                        : String(localized: "Reminder title"),
                    text: $title
                )
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .focused($titleFocused)
                .onSubmit { if canCreate { primaryAction() } }

                calendarSwatch
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
    }

    private var eventFields: some View {
        sectionCard {
            formRow(String(localized: "All Day")) {
                Toggle(String(localized: "All Day"), isOn: $isAllDay)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            }
            rowDivider
            formRow(String(localized: "Starts")) {
                dateTimeField($startTime)
            }
            rowDivider
            formRow(String(localized: "Ends")) {
                dateTimeField($endTime)
            }
            rowDivider
            formRow(String(localized: "Repeat")) {
                repeatPicker
            }
            // All-day events use day-based alert semantics that don't fit
            // these time offsets; that nuance stays with Calendar.app.
            if !isAllDay {
                rowDivider
                formRow(String(localized: "Alert")) {
                    alertPicker(includeAtTime: true)
                }
            }
        }
        .onChange(of: startTime) { old, new in
            // Keep the duration when the start moves.
            endTime = endTime.addingTimeInterval(new.timeIntervalSince(old))
        }
    }

    private var reminderFields: some View {
        sectionCard {
            formRow(String(localized: "Date")) {
                SegmentedDateField(date: $reminderDate, elements: [.yearMonthDay])
                    .fixedSize()
            }
            rowDivider
            formRow(String(localized: "Time")) {
                if reminderHasTime {
                    SegmentedDateField(date: $reminderTime, elements: [.hourMinute], showsStepper: true)
                        .fixedSize()
                }
                Toggle(String(localized: "Time"), isOn: $reminderHasTime)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            }
            rowDivider
            formRow(String(localized: "Repeat")) {
                repeatPicker
            }
            // A timed reminder already alerts at its due time; the picker
            // offers only extra early alerts, and needs a time to offset.
            if reminderHasTime {
                rowDivider
                formRow(String(localized: "Alert")) {
                    alertPicker(includeAtTime: false)
                }
            }
        }
    }

    private var notesSection: some View {
        sectionCard {
            TextField(String(localized: "Notes"), text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(2...4)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
    }

    // MARK: Detail rows

    @ViewBuilder
    private var repeatPicker: some View {
        if customRecurrence {
            customValueLabel
        } else {
            Picker(String(localized: "Repeat"), selection: repeatSelection) {
                ForEach(RepeatOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
            .font(.system(size: 12))
            .fixedSize()
            .popover(isPresented: $showingCustomRepeat, arrowEdge: .bottom) {
                CustomRepeatEditor(
                    initial: customRepeat ?? seedCustomRepeat,
                    calendar: calendar
                ) { committed in
                    customRepeat = committed
                    repeatOption = .custom
                }
            }
        }
    }

    /// Selecting "Custom…" opens the dialog instead of committing; the
    /// selection only becomes Custom when the dialog is confirmed, so
    /// Cancel keeps the previous choice — as in Calendar.app. Re-choosing
    /// "Custom…" while already custom reopens the dialog with its values.
    private var repeatSelection: Binding<RepeatOption> {
        Binding(
            get: { repeatOption },
            set: { newValue in
                if newValue == .custom {
                    showingCustomRepeat = true
                } else {
                    repeatOption = newValue
                }
            }
        )
    }

    /// Starting point for a fresh Custom dialog: weekly on the item's day,
    /// matching Calendar.app's default.
    private var seedCustomRepeat: CustomRepeat {
        let weekday = calendar.component(.weekday, from: kind == .event ? startTime : reminderDate)
        return CustomRepeat(frequency: .weekly, interval: 1, weekdays: [weekday])
    }

    @ViewBuilder
    private func alertPicker(includeAtTime: Bool) -> some View {
        if customAlerts {
            customValueLabel
        } else {
            Picker(String(localized: "Alert"), selection: $alertOption) {
                ForEach(AlertOption.allCases.filter { includeAtTime || $0 != .atTime }) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
            .font(.system(size: 12))
            .fixedSize()
        }
    }

    /// Read-only stand-in for a picker whose stored value no preset can
    /// express; saving preserves the value untouched.
    private var customValueLabel: some View {
        Text(String(localized: "Custom"))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .help(String(localized: "Set in Calendar or Reminders; kept as is."))
    }

    /// Compact calendar/list chooser in the title row: the selected
    /// calendar's color dot with a pop-up chevron, like Calendar.app's
    /// swatch picker. A single writable calendar shows just its static dot.
    @ViewBuilder
    private var calendarSwatch: some View {
        let options = kind == .event ? eventCalendars : reminderLists
        let selection = kind == .event ? $selectedEventCalendarID : $selectedReminderListID
        let selected = options.first { $0.calendarIdentifier == selection.wrappedValue } ?? options.first
        if let selected {
            if options.count > 1 {
                Menu {
                    Picker(
                        kind == .event
                            ? String(localized: "Calendar")
                            : String(localized: "List"),
                        selection: selection
                    ) {
                        ForEach(options, id: \.calendarIdentifier) { cal in
                            calendarOptionLabel(cal).tag(cal.calendarIdentifier)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    HStack(spacing: 4) {
                        swatchDot(selected)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(kind == .event
                    ? String(localized: "Calendar")
                    : String(localized: "List"))
            } else {
                swatchDot(selected)
            }
        }
    }

    private func swatchDot(_ cal: EKCalendar) -> some View {
        Circle()
            .fill(Color(cgColor: cal.cgColor))
            .frame(width: 11, height: 11)
    }

    /// Date field with a separate time field beside it when not all-day.
    private func dateTimeField(_ date: Binding<Date>) -> some View {
        HStack(spacing: 6) {
            SegmentedDateField(date: date, elements: [.yearMonthDay])
            if !isAllDay {
                SegmentedDateField(date: date, elements: [.hourMinute])
            }
        }
        .fixedSize()
    }

    /// Routes the footer's primary button (and title-field return) to create
    /// or save. Editing a recurring event first asks which span to apply to.
    private func primaryAction() {
        guard editTarget != nil else { return create() }
        if isRecurringEventEdit {
            pendingConfirmation = .saveSpan
        } else {
            applyEdits(span: .thisEvent)
        }
    }

    private func deleteTapped() {
        pendingConfirmation = isRecurringEventEdit ? .deleteSpan : .delete
    }

    /// Whether the edited item is a recurring event, which makes save and
    /// delete span-sensitive. Reminders have no span semantics — deleting a
    /// recurring reminder removes the series, as in Reminders.app.
    private var isRecurringEventEdit: Bool {
        if case .event(let event) = editTarget { return event.hasRecurrenceRules }
        return false
    }

    private func confirmationBinding(_ value: PendingConfirmation) -> Binding<Bool> {
        Binding(
            get: { pendingConfirmation == value },
            set: { if !$0 { pendingConfirmation = nil } }
        )
    }

    /// Writes the form's fields back onto the edited item and saves. Custom
    /// recurrence/alarm sets are left exactly as fetched (see the Custom
    /// labels); preset ones are rebuilt from the pickers, mirroring
    /// `createEvent`/`createReminder`.
    private func applyEdits(span: EKSpan) {
        guard let editTarget else { return }
        do {
            switch editTarget {
            case .event(let event):
                guard let target = eventCalendars.first(where: { $0.calendarIdentifier == selectedEventCalendarID }) else {
                    saveFailed = true
                    return
                }
                event.title = trimmedTitle
                if event.calendar.calendarIdentifier != target.calendarIdentifier {
                    event.calendar = target
                }
                event.isAllDay = isAllDay
                if isAllDay {
                    event.startDate = calendar.startOfDay(for: startTime)
                    event.endDate = calendar.startOfDay(for: max(startTime, endTime))
                } else {
                    event.startDate = startTime
                    event.endDate = endTime
                }
                event.notes = trimmedNotes
                if !customRecurrence {
                    (event.recurrenceRules ?? []).forEach(event.removeRecurrenceRule)
                    if let rule = selectedRecurrenceRule { event.addRecurrenceRule(rule) }
                }
                if !customAlerts {
                    (event.alarms ?? []).forEach(event.removeAlarm)
                    if let alarm = eventAlarm { event.addAlarm(alarm) }
                }
                try model.update(event: event, span: span)
            case .reminder(let reminder):
                guard let target = reminderLists.first(where: { $0.calendarIdentifier == selectedReminderListID }) else {
                    saveFailed = true
                    return
                }
                reminder.title = trimmedTitle
                if reminder.calendar.calendarIdentifier != target.calendarIdentifier {
                    reminder.calendar = target
                }
                var components = calendar.dateComponents([.year, .month, .day], from: reminderDate)
                if reminderHasTime {
                    components.hour = calendar.component(.hour, from: reminderTime)
                    components.minute = calendar.component(.minute, from: reminderTime)
                }
                reminder.dueDateComponents = components
                reminder.notes = trimmedNotes
                if !customRecurrence {
                    (reminder.recurrenceRules ?? []).forEach(reminder.removeRecurrenceRule)
                    if let rule = selectedRecurrenceRule { reminder.addRecurrenceRule(rule) }
                }
                if !customAlerts {
                    (reminder.alarms ?? []).forEach(reminder.removeAlarm)
                    if reminderHasTime, let fireDate = calendar.date(from: components) {
                        reminder.addAlarm(EKAlarm(absoluteDate: fireDate))
                        if let offset = alertOption.offset, offset > 0 {
                            reminder.addAlarm(EKAlarm(absoluteDate: fireDate.addingTimeInterval(-offset)))
                        }
                    }
                }
                try model.update(reminder: reminder)
            }
            dismiss()
        } catch {
            Logger.peek.error("Failed to save edits: \(error.localizedDescription)")
            saveFailed = true
        }
    }

    private func deleteItem(span: EKSpan) {
        guard let editTarget else { return }
        do {
            switch editTarget {
            case .event(let event):
                try model.remove(event: event, span: span)
            case .reminder(let reminder):
                try model.remove(reminder: reminder)
            }
            dismiss()
        } catch {
            Logger.peek.error("Failed to delete item: \(error.localizedDescription)")
            saveFailed = true
        }
    }

    private func create() {
        do {
            switch kind {
            case .event:
                guard let target = eventCalendars.first(where: { $0.calendarIdentifier == selectedEventCalendarID }) else {
                    saveFailed = true
                    return
                }
                try model.createEvent(
                    title: trimmedTitle,
                    start: startTime,
                    end: endTime,
                    isAllDay: isAllDay,
                    notes: trimmedNotes,
                    recurrence: selectedRecurrenceRule,
                    alarm: eventAlarm,
                    eventCalendar: target,
                    in: calendar
                )
            case .reminder:
                guard let target = reminderLists.first(where: { $0.calendarIdentifier == selectedReminderListID }) else {
                    saveFailed = true
                    return
                }
                try model.createReminder(
                    title: trimmedTitle,
                    dueDate: reminderDate,
                    time: reminderHasTime ? reminderTime : nil,
                    notes: trimmedNotes,
                    recurrence: selectedRecurrenceRule,
                    earlyAlertOffset: reminderHasTime ? alertOption.offset : nil,
                    reminderCalendar: target,
                    in: calendar
                )
            }
            dismiss()
        } catch {
            Logger.peek.error("Failed to save item: \(error.localizedDescription)")
            saveFailed = true
        }
    }
}

/// Calendar.app-style Custom repeat dialog: frequency popup, "Every N
/// <unit>" interval field, and a weekday strip when weekly. Edits a local
/// draft; only OK commits back to the form.
private struct CustomRepeatEditor: View {
    let calendar: Calendar
    let commit: (CustomRepeat) -> Void

    @State private var draft: CustomRepeat
    @Environment(\.dismiss) private var dismiss

    init(initial: CustomRepeat, calendar: Calendar, commit: @escaping (CustomRepeat) -> Void) {
        self.calendar = calendar
        self.commit = commit
        _draft = State(initialValue: initial)
    }

    /// The weekday strip's exact width (7 × 26pt cells + 6 × 1pt gaps) —
    /// the dialog's widest content, so every frequency lays out in the
    /// same footprint.
    private static let contentWidth: CGFloat = 188

    var body: some View {
        // Leading-aligned fixed-width rows: as the frequency or unit text
        // changes, controls stay put instead of re-centering.
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(String(localized: "Frequency:"))
                    .font(.system(size: 12))
                Picker(String(localized: "Frequency"), selection: $draft.frequency) {
                    Text(String(localized: "Daily")).tag(EKRecurrenceFrequency.daily)
                    Text(String(localized: "Weekly")).tag(EKRecurrenceFrequency.weekly)
                    Text(String(localized: "Monthly")).tag(EKRecurrenceFrequency.monthly)
                    Text(String(localized: "Yearly")).tag(EKRecurrenceFrequency.yearly)
                }
                .labelsHidden()
                .font(.system(size: 12))
                .fixedSize()
            }

            HStack(spacing: 6) {
                Text(String(localized: "Every"))
                    .font(.system(size: 12))
                TextField(String(localized: "Interval"), value: $draft.interval, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12))
                    .frame(width: 36)
                Text(unitLabel)
                    .font(.system(size: 12))
            }

            // Always in the layout so the dialog keeps one size; hidden
            // rather than removed outside weekly, which would resize the
            // popover on every frequency change.
            weekdayStrip
                .opacity(draft.frequency == .weekly ? 1 : 0)
                .disabled(draft.frequency != .weekly)
                .accessibilityHidden(draft.frequency != .weekly)

            HStack {
                Spacer(minLength: 0)
                Button(String(localized: "Cancel")) { dismiss() }
                    .font(.system(size: 12))
                Button(String(localized: "OK")) {
                    var value = draft
                    value.interval = min(999, max(1, value.interval))
                    commit(value)
                    dismiss()
                }
                .font(.system(size: 12))
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: Self.contentWidth)
        .padding(14)
        .onExitCommand(perform: dismiss.callAsFunction)
    }

    /// Pluralized interval unit, e.g. "Week" / "Weeks".
    private var unitLabel: String {
        let plural = draft.interval != 1
        switch draft.frequency {
        case .daily: return plural ? String(localized: "Days") : String(localized: "Day")
        case .weekly: return plural ? String(localized: "Weeks") : String(localized: "Week")
        case .monthly: return plural ? String(localized: "Months") : String(localized: "Month")
        case .yearly: return plural ? String(localized: "Years") : String(localized: "Year")
        @unknown default: return ""
        }
    }

    /// Seven joined weekday cells like Calendar.app's, ordered by the
    /// locale's first weekday. At least one day stays selected — clicking
    /// the last selected day is a no-op, as in Calendar.app.
    private var weekdayStrip: some View {
        HStack(spacing: 1) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                let selected = draft.weekdays.contains(weekday)
                Button {
                    if selected {
                        if draft.weekdays.count > 1 { draft.weekdays.remove(weekday) }
                    } else {
                        draft.weekdays.insert(weekday)
                    }
                } label: {
                    Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 26, height: 22)
                        .background(Color.primary.opacity(selected ? 0.25 : 0.06))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday - 1])
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    /// Weekday numbers (1 = Sunday) starting from the locale's first weekday.
    private var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}

/// A calendar/list picker item: colored dot plus title. The dot is
/// rasterized into an `NSImage` because menu items render `Label` icons
/// but drop arbitrary shape views.
private func calendarOptionLabel(_ cal: EKCalendar) -> some View {
    Label {
        Text(cal.title)
    } icon: {
        Image(nsImage: calendarDotImage(cal))
    }
}

private func calendarDotImage(_ cal: EKCalendar) -> NSImage {
    let color: CGColor = cal.cgColor
    return NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
        (NSColor(cgColor: color) ?? .systemBlue).setFill()
        NSBezierPath(ovalIn: rect).fill()
        return true
    }
}

/// Shared footer for the create and edit forms: optional destructive Delete
/// on the leading edge, Cancel and the primary action trailing.
private func formFooter(
    primaryTitle: String,
    primaryEnabled: Bool,
    primary: @escaping () -> Void,
    delete: (() -> Void)? = nil,
    dismiss: @escaping () -> Void
) -> some View {
    HStack {
        if let delete {
            Button(String(localized: "Delete"), role: .destructive, action: delete)
                .font(.system(size: 12))
        }
        Spacer(minLength: 0)
        Button(String(localized: "Cancel"), action: dismiss)
            .font(.system(size: 12))
        Button(primaryTitle, action: primary)
            .font(.system(size: 12))
            .keyboardShortcut(.defaultAction)
            .disabled(!primaryEnabled)
    }
}

#Preview {
    CalendarPopoverView()
}
