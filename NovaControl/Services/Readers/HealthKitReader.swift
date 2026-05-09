// NovaControl — HealthKit Reader
// Written by Jordan Koch
// Requires HealthKit capability in Xcode project (add via Signing & Capabilities).
// Add to Info.plist: NSHealthShareUsageDescription

import Foundation
import HealthKit

@available(macOS 13.0, *)
actor HealthKitReader {
    static let shared = HealthKitReader()

    private let store = HKHealthStore()
    private var authorized = false

    private let typesToRead: Set<HKObjectType> = [
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
    ]

    private init() {}

    // MARK: - Authorization

    func requestAuthorizationIfNeeded() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthError.notAvailable
        }
        try await store.requestAuthorization(toShare: [], read: typesToRead)
        authorized = true
    }

    // MARK: - Queries

    func latestHealthSnapshot() async throws -> HealthSnapshot {
        if !authorized { try await requestAuthorizationIfNeeded() }

        async let sleep    = fetchSleepHours(daysBack: 1)
        async let hrv      = fetchLatestQuantity(.heartRateVariabilitySDNN, unit: .init(from: "ms"))
        async let rhr      = fetchLatestQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute()))
        async let steps    = fetchSumQuantity(.stepCount, unit: .count(), daysBack: 1)
        async let calories = fetchSumQuantity(.activeEnergyBurned, unit: .kilocalorie(), daysBack: 1)
        async let weight   = fetchLatestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))

        let (s, h, r, st, c, w) = try await (sleep, hrv, rhr, steps, calories, weight)

        return HealthSnapshot(
            date: Date(),
            sleepHours: s,
            hrvSDNN: h,
            restingHeartRate: r,
            stepCount: st.flatMap { Int($0) },
            activeCalories: c.flatMap { Int($0) },
            bodyMassKg: w
        )
    }

    // MARK: - Private helpers

    private func fetchSleepHours(daysBack: Int) async throws -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let hours = (samples as? [HKCategorySample])?.filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue  ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue
                }.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 3600 }
                continuation.resume(returning: hours)
            }
            store.execute(query)
        }
    }

    private func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func fetchSumQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, daysBack: Int) async throws -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let start = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -daysBack + 1, to: Date())!)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}

// MARK: - Models

struct HealthSnapshot: Codable {
    let date: Date
    let sleepHours: Double?
    let hrvSDNN: Double?
    let restingHeartRate: Double?
    let stepCount: Int?
    let activeCalories: Int?
    let bodyMassKg: Double?
}

enum HealthError: Error {
    case notAvailable
    case authorizationDenied
}
