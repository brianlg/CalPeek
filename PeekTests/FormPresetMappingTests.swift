import EventKit
import Foundation
import Testing
@testable import Peek

/// Mapping from an item's stored recurrence rules to the editor's Repeat
/// presets. Nil means "Custom": the rules are preserved untouched on save.
struct RepeatOptionMappingTests {
    @Test func noRulesIsNever() {
        #expect(RepeatOption.matching(nil) == .never)
        #expect(RepeatOption.matching([]) == .never)
    }

    @Test func simpleFrequenciesMapToPresets() {
        let cases: [(EKRecurrenceFrequency, RepeatOption)] = [
            (.daily, .daily), (.weekly, .weekly), (.monthly, .monthly), (.yearly, .yearly),
        ]
        for (frequency, expected) in cases {
            let rule = EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)
            #expect(RepeatOption.matching([rule]) == expected)
        }
    }

    @Test func intervalAboveOneIsCustom() {
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil)
        #expect(RepeatOption.matching([rule]) == nil)
    }

    @Test func ruleWithEndIsCustom() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 5))
        #expect(RepeatOption.matching([rule]) == nil)
    }

    @Test func weeklyPinnedToOneWeekdayIsStillWeekly() {
        // Calendar.app's own quick-create weekly rule stores the start's
        // weekday explicitly.
        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday)],
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
            daysOfTheYear: nil, setPositions: nil, end: nil)
        #expect(RepeatOption.matching([rule]) == .weekly)
    }

    @Test func weeklyOnSeveralWeekdaysIsCustom() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.thursday)],
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
            daysOfTheYear: nil, setPositions: nil, end: nil)
        #expect(RepeatOption.matching([rule]) == nil)
    }

    @Test func multipleRulesAreCustom() {
        let rules = [
            EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil),
            EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil),
        ]
        #expect(RepeatOption.matching(rules) == nil)
    }
}

/// Mapping from an item's stored alarms to the editor's Alert presets.
/// Nil means "Custom": the alarms are preserved untouched on save.
struct AlertOptionMappingTests {
    @Test func noEventAlarmsIsNone() {
        #expect(AlertOption.matching(eventAlarms: nil) == AlertOption.none)
        #expect(AlertOption.matching(eventAlarms: []) == AlertOption.none)
    }

    @Test func relativeEventAlarmsMapToPresets() {
        let cases: [(TimeInterval, AlertOption)] = [
            (0, .atTime), (5 * 60, .minutes5), (10 * 60, .minutes10),
            (30 * 60, .minutes30), (3600, .hour1), (86400, .day1),
        ]
        for (offset, expected) in cases {
            #expect(AlertOption.matching(eventAlarms: [EKAlarm(relativeOffset: -offset)]) == expected)
        }
    }

    @Test func offPresetEventOffsetIsCustom() {
        #expect(AlertOption.matching(eventAlarms: [EKAlarm(relativeOffset: -15 * 60)]) == nil)
    }

    @Test func absoluteEventAlarmIsCustom() {
        #expect(AlertOption.matching(eventAlarms: [EKAlarm(absoluteDate: Date())]) == nil)
    }

    @Test func twoEventAlarmsAreCustom() {
        let alarms = [EKAlarm(relativeOffset: 0), EKAlarm(relativeOffset: -300)]
        #expect(AlertOption.matching(eventAlarms: alarms) == nil)
    }

    @Test func dueTimeOnlyReminderAlarmIsNone() {
        let due = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(AlertOption.matching(reminderAlarms: [EKAlarm(absoluteDate: due)], due: due) == AlertOption.none)
    }

    @Test func dueTimePlusEarlyReminderAlarmMapsToPreset() {
        let due = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let alarms = [EKAlarm(absoluteDate: due), EKAlarm(absoluteDate: due.addingTimeInterval(-600))]
        #expect(AlertOption.matching(reminderAlarms: alarms, due: due) == .minutes10)
    }

    @Test func reminderAlarmMissingDueTimeIsCustom() {
        let due = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let alarms = [EKAlarm(absoluteDate: due.addingTimeInterval(-600))]
        #expect(AlertOption.matching(reminderAlarms: alarms, due: due) == nil)
    }

    @Test func noReminderAlarmsIsCustom() {
        // A timed reminder deliberately saved without alarms keeps that state
        // rather than gaining an at-due alarm on an unrelated edit.
        let due = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(AlertOption.matching(reminderAlarms: [], due: due) == nil)
        #expect(AlertOption.matching(reminderAlarms: nil, due: due) == nil)
    }

    @Test func offPresetEarlyReminderAlarmIsCustom() {
        let due = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let alarms = [EKAlarm(absoluteDate: due), EKAlarm(absoluteDate: due.addingTimeInterval(-123))]
        #expect(AlertOption.matching(reminderAlarms: alarms, due: due) == nil)
    }
}
