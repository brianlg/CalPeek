import Foundation
import SwiftUI
import Testing

@testable import CalPeek

/// The order of a day's rows: all-day items first (events ahead of
/// reminders), then timed items by time, then by title so a refresh never
/// shuffles two items that share a time.
struct DayListOrderTests {
    private static let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func item(
        _ title: String,
        kind: DayItem.Kind = .event,
        allDay: Bool = false,
        at minutes: Double = 0
    ) -> DayItem {
        DayItem(
            id: title, title: title, timeText: "", color: .red,
            joinURL: nil, openURL: nil, eventIdentifier: nil, isEditable: true,
            kind: kind, sortsAsAllDay: allDay,
            sortDate: Self.noon.addingTimeInterval(minutes * 60), endDate: nil)
    }

    private func titles(_ items: [DayItem]) -> [String] {
        items.sorted(by: DayItem.dayListOrder).map(\.title)
    }

    @Test func allDayItemsComeBeforeTimedOnesRegardlessOfTime() {
        let items = [
            item("Standup", at: -180),
            item("Company holiday", allDay: true, at: 600),
        ]
        #expect(titles(items) == ["Company holiday", "Standup"])
    }

    @Test func withinAllDayEventsComeBeforeReminders() {
        let items = [
            item("Pay rent", kind: .reminder(isCompleted: false, reminderID: "r"), allDay: true, at: -60),
            item("Company holiday", allDay: true, at: 60),
        ]
        #expect(titles(items) == ["Company holiday", "Pay rent"])
    }

    @Test func timedItemsSortByTimeAcrossKinds() {
        let items = [
            item("Design review", at: 120),
            item("Submit timesheet", kind: .reminder(isCompleted: false, reminderID: "r"), at: 30),
            item("Standup", at: -180),
        ]
        #expect(titles(items) == ["Standup", "Submit timesheet", "Design review"])
    }

    @Test func itemsSharingATimeSortByTitle() {
        let items = [item("Budget", at: 0), item("All hands", at: 0), item("1:1", at: 0)]
        #expect(titles(items) == ["1:1", "All hands", "Budget"])
    }
}
