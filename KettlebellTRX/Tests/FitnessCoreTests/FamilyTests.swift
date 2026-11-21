import XCTest
@testable import FitnessCore

final class FamilyOnboardingTests: XCTestCase {
    func testFreshInstallNeedsOnboardingAndCompletes() throws {
        let dir = TS.tempDir()
        let repo = try AppRepository(store: LocalStore(directory: dir))
        XCTAssertFalse(repo.hasStoredProfile)
        XCTAssertNil(repo.plan)

        var p = UserProfile.blank(now: TS.date(21))
        p.displayName = "Anna"
        p.birthYear = 1995
        p.kettlebellsKg = [6, 10]
        p.trainingDays = [.tuesday, .thursday]
        try repo.completeOnboarding(profile: p, library: TS.library, startDate: TS.monday)
        XCTAssertTrue(repo.hasStoredProfile)
        XCTAssertEqual(repo.plan?.weeks.first?.workouts.map(\.weekday), [.tuesday, .thursday])
        XCTAssertEqual(repo.plan?.weeks.first?.workouts.map(\.dayType), [.strength, .conditioning])
        let weights = Set(repo.plan!.allWorkouts.flatMap(\.exercises).compactMap(\.weightKg))
        XCTAssertTrue(weights.isSubset(of: [6, 10]))

        let reopened = try AppRepository(store: LocalStore(directory: dir))
        XCTAssertTrue(reopened.hasStoredProfile)
        XCTAssertEqual(reopened.profile.displayName, "Anna")

        try reopened.deleteAllPersonalData()
        XCTAssertFalse(reopened.hasStoredProfile, "Nach dem Löschen startet der Assistent erneut")
    }

    func testBlankProfileIsNeutral() {
        let p = UserProfile.blank(now: TS.date(21))
        XCTAssertEqual(p.age(on: TS.date(21)), 40)
        XCTAssertEqual(p.experience, .beginner)
        XCTAssertTrue(p.sports.isEmpty)
    }

    func testScreeningIsConservative() {
        var p = UserProfile.blank()
        let none = HealthScreening()
        XCTAssertFalse(none.recommendsMedicalClearance)
        none.apply(to: &p)
        XCTAssertFalse(p.health.hasCardiovascularRestriction)

        let s = HealthScreening(yes: [.bloodPressureOrHeartMedication])
        XCTAssertTrue(s.recommendsMedicalClearance)
        s.apply(to: &p)
        XCTAssertTrue(p.health.hasCardiovascularRestriction)
        XCTAssertEqual(p.health.intensityFactor, 1.0)

        var q = UserProfile.blank()
        HealthScreening(yes: [.chestPainOnExertion]).apply(to: &q)
        XCTAssertEqual(q.health.intensityFactor, 0.8)
        XCTAssertTrue(HealthScreening(yes: [.pregnancy]).notices.contains { $0.contains("Schwangerschaft") })

        // Screening mit Herz-Kreislauf-Antwort entfernt Swings aus dem Plan, auch mit Technikbestätigung
        q.health.ballisticTechniqueConfirmed = true
        let plan = PlanGenerator(library: TS.library, profile: q).generate(startDate: TS.monday)
        XCTAssertFalse(plan.allWorkouts.flatMap(\.exercises).contains { $0.exerciseId == "kb_swing" })
    }

    func testProfileWithScreeningRoundTrips() throws {
        let dir = TS.tempDir()
        let repo = try AppRepository(store: LocalStore(directory: dir))
        var p = UserProfile.blank()
        p.screening = HealthScreening(yes: [.jointOrSpineProblem], answeredAt: TS.date(21))
        try repo.updateProfile(p)
        XCTAssertEqual(try AppRepository(store: LocalStore(directory: dir)).profile.screening?.yes, [.jointOrSpineProblem])
    }
}
