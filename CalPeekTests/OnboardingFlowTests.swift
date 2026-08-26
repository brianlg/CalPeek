import EventKit
import Testing

@testable import CalPeek

/// The welcome flow's navigation is a pure value; these pin the clamping so
/// Back on the first page and Continue past the last can never walk off the
/// enum.
struct OnboardingFlowTests {
    @Test func startsOnTheWelcomePage() {
        let flow = OnboardingFlow()
        #expect(flow.step == .welcome)
        #expect(flow.isFirst)
        #expect(!flow.isLast)
    }

    @Test func advanceStopsAtTheFinalStep() {
        var flow = OnboardingFlow()
        for _ in 0..<10 { flow.advance() }
        #expect(flow.step == .finish)
        #expect(flow.isLast)
    }

    @Test func goBackStopsAtTheFirstStep() {
        var flow = OnboardingFlow()
        flow.advance()
        for _ in 0..<10 { flow.goBack() }
        #expect(flow.step == .welcome)
        #expect(flow.isFirst)
    }

    @Test func stepNumberIsOneBasedAndBoundedByStepCount() {
        var flow = OnboardingFlow()
        #expect(flow.stepNumber == 1)
        while !flow.isLast { flow.advance() }
        #expect(flow.stepNumber == OnboardingFlow.stepCount)
    }
}

/// The permission row's affordance is derived purely from the EventKit
/// status, and two of those statuses (write-only, denied) can never be
/// re-prompted in-process — mapping either to `.canRequest` would show an
/// Allow button that silently does nothing.
struct PermissionRowStateTests {
    @Test func notDeterminedCanBeRequested() {
        #expect(PermissionRowState(.notDetermined) == .canRequest)
    }

    @Test func fullAccessIsGranted() {
        #expect(PermissionRowState(.fullAccess) == .granted)
    }

    @Test func writeOnlyNeedsFullAccessRatherThanReadingAsDenied() {
        #expect(PermissionRowState(.writeOnly) == .needsFullAccess)
    }

    @Test func deniedOffersNoRequest() {
        #expect(PermissionRowState(.denied) == .denied)
    }

    @Test func restrictedOffersNoRequest() {
        #expect(PermissionRowState(.restricted) == .restricted)
    }
}
