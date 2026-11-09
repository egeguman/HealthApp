import Foundation
import HealthKit

protocol HealthDataSource {
    func requestAuthorization() async throws
    func fetchSnapshot(in interval: DateInterval) async throws -> HealthSnapshot
}

enum HealthDataError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: "Health data isn't available on this device."
        }
    }
}

/// Reads Apple Watch data from Apple Health. Read-only: nothing is ever written back.
final class HealthKitService: HealthDataSource {
    static let shared = HealthKitService()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        let quantities: [HKQuantityTypeIdentifier] = [
            .heartRate, .heartRateVariabilitySDNN, .restingHeartRate, .respiratoryRate, .oxygenSaturation,
            .appleSleepingWristTemperature, .stepCount, .activeEnergyBurned,
            .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
        ]
        var types = Set<HKObjectType>(quantities.map { HKQuantityType($0) })
        types.insert(HKCategoryType(.sleepAnalysis))
        types.insert(HKObjectType.workoutType())
        types.insert(HKCharacteristicType(.dateOfBirth))
        types.insert(HKCharacteristicType(.biologicalSex))
        return types
    }

    func requestAuthorization() async throws {
        guard Self.isAvailable else { throw HealthDataError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchSnapshot(in interval: DateInterval) async throws -> HealthSnapshot {
        guard Self.isAvailable else { throw HealthDataError.unavailable }
        let bpm = HKUnit.count().unitDivided(by: .minute())

        async let heartRate = heartRateReadings(in: interval)
        async let hrv = readings(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), in: interval)
        async let resting = readings(.restingHeartRate, unit: bpm, in: interval)
        async let respiratory = readings(.respiratoryRate, unit: bpm, in: interval)
        async let oxygen = readings(.oxygenSaturation, unit: .percent(), in: interval)
        async let temperature = readings(.appleSleepingWristTemperature, unit: .degreeCelsius(), in: interval)
        async let sleep = sleepSamples(in: interval)
        async let workouts = workoutRecords(in: interval)
        async let steps = dailyTotals(.stepCount, unit: .count(), in: interval)
        async let energy = dailyTotals(.activeEnergyBurned, unit: .kilocalorie(), in: interval)

        var snapshot = HealthSnapshot(interval: interval)
        snapshot.heartRate = await heartRate
        snapshot.hrv = await hrv
        snapshot.restingHeartRate = await resting
        snapshot.respiratoryRate = await respiratory
        snapshot.oxygenSaturation = await oxygen.map { Reading(date: $0.date, value: $0.value * 100) }
        snapshot.wristTemperature = await temperature
        snapshot.sleep = await sleep
        snapshot.workouts = await workouts
        snapshot.dailySteps = await steps
        snapshot.dailyActiveEnergy = await energy
        snapshot.profile = profile()
        return snapshot
    }

    // MARK: - Queries
    //
    // Each query fails soft: HealthKit doesn't reveal which read permissions were denied, and one
    // missing data type shouldn't hide everything else.

    private func readings(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, in interval: DateInterval) async -> [Reading] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            return try await descriptor.result(for: store)
                .map { Reading(date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
        } catch {
            return []
        }
    }

    /// Heart rate is by far the largest data set (continuous during workouts), so fetch it a day at a time in parallel.
    private func heartRateReadings(in interval: DateInterval) async -> [Reading] {
        var chunks: [DateInterval] = []
        var cursor = interval.start
        while cursor < interval.end {
            let next = min(Calendar.current.date(byAdding: .day, value: 1, to: cursor)!, interval.end)
            chunks.append(DateInterval(start: cursor, end: next))
            cursor = next
        }
        return await withTaskGroup(of: [Reading].self) { group in
            for chunk in chunks {
                group.addTask { await self.readings(.heartRate, unit: .count().unitDivided(by: .minute()), in: chunk) }
            }
            var all: [Reading] = []
            for await part in group {
                all.append(contentsOf: part)
            }
            return all.sorted { $0.date < $1.date }
        }
    }

    private func sleepSamples(in interval: DateInterval) async -> [SleepSample] {
        // Reach back a day so a night that started before the interval is complete.
        let predicate = HKQuery.predicateForSamples(withStart: interval.start.addingTimeInterval(-24 * 3600), end: interval.end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            return try await descriptor.result(for: store).compactMap { sample in
                guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
                let stage: SleepStage
                switch value {
                case .inBed: stage = .inBed
                case .awake: stage = .awake
                case .asleepCore: stage = .core
                case .asleepDeep: stage = .deep
                case .asleepREM: stage = .rem
                case .asleepUnspecified: stage = .unspecified
                @unknown default: return nil
                }
                return SleepSample(start: sample.startDate, end: sample.endDate, stage: stage,
                                   source: sample.sourceRevision.source.bundleIdentifier)
            }
        } catch {
            return []
        }
    }

    private func workoutRecords(in interval: DateInterval) async -> [WorkoutRecord] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        do {
            return try await descriptor.result(for: store).map { workout in
                let info = WorkoutCatalog.info(for: workout.workoutActivityType)
                let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
                let distance = [HKQuantityTypeIdentifier.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
                    .lazy
                    .compactMap { workout.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter()) }
                    .first
                return WorkoutRecord(id: workout.uuid, name: info.name, symbol: info.symbol,
                                     start: workout.startDate, end: workout.endDate, activeEnergy: energy, distance: distance)
            }
        } catch {
            return []
        }
    }

    private func dailyTotals(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, in interval: DateInterval) async -> [Date: Double] {
        let calendar = Calendar.current
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier),
                                       predicate: HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)),
            options: .cumulativeSum,
            anchorDate: calendar.startOfDay(for: interval.start),
            intervalComponents: DateComponents(day: 1)
        )
        do {
            var totals: [Date: Double] = [:]
            for statistics in try await descriptor.result(for: store).statistics() {
                if let sum = statistics.sumQuantity() {
                    totals[calendar.startOfDay(for: statistics.startDate)] = sum.doubleValue(for: unit)
                }
            }
            return totals
        } catch {
            return [:]
        }
    }

    private func profile() -> UserProfile {
        var profile = UserProfile()
        if let birthday = try? store.dateOfBirthComponents(), let date = Calendar.current.date(from: birthday) {
            profile.age = Calendar.current.dateComponents([.year], from: date, to: .now).year
        }
        switch (try? store.biologicalSex())?.biologicalSex {
        case .female: profile.sex = .female
        case .male: profile.sex = .male
        default: break
        }
        return profile
    }
}

enum WorkoutCatalog {
    static func info(for type: HKWorkoutActivityType) -> (name: String, symbol: String) {
        switch type {
        case .running: ("Running", "figure.run")
        case .walking: ("Walking", "figure.walk")
        case .cycling: ("Cycling", "figure.outdoor.cycle")
        case .swimming: ("Swimming", "figure.pool.swim")
        case .hiking: ("Hiking", "figure.hiking")
        case .traditionalStrengthTraining: ("Strength Training", "figure.strengthtraining.traditional")
        case .functionalStrengthTraining: ("Functional Training", "figure.strengthtraining.functional")
        case .highIntensityIntervalTraining: ("HIIT", "figure.highintensity.intervaltraining")
        case .crossTraining: ("Cross Training", "figure.cross.training")
        case .mixedCardio: ("Mixed Cardio", "figure.mixed.cardio")
        case .coreTraining: ("Core Training", "figure.core.training")
        case .rowing: ("Rowing", "figure.rower")
        case .elliptical: ("Elliptical", "figure.elliptical")
        case .stairClimbing: ("Stair Climbing", "figure.stair.stepper")
        case .yoga: ("Yoga", "figure.yoga")
        case .pilates: ("Pilates", "figure.pilates")
        case .flexibility: ("Flexibility", "figure.flexibility")
        case .cooldown: ("Cooldown", "figure.cooldown")
        case .mindAndBody: ("Mind & Body", "figure.mind.and.body")
        case .dance, .cardioDance, .socialDance: ("Dance", "figure.dance")
        case .boxing: ("Boxing", "figure.boxing")
        case .kickboxing: ("Kickboxing", "figure.kickboxing")
        case .martialArts: ("Martial Arts", "figure.martial.arts")
        case .climbing: ("Climbing", "figure.climbing")
        case .soccer: ("Soccer", "figure.soccer")
        case .basketball: ("Basketball", "figure.basketball")
        case .tennis: ("Tennis", "figure.tennis")
        case .pickleball: ("Pickleball", "figure.pickleball")
        case .golf: ("Golf", "figure.golf")
        case .snowboarding: ("Snowboarding", "figure.snowboarding")
        case .downhillSkiing: ("Skiing", "figure.skiing.downhill")
        default: ("Workout", "figure.mixed.cardio")
        }
    }
}
