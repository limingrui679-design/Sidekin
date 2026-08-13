import Foundation

// Sidekin's deterministic care and growth rules live in this core module.

public enum PetLifecycleEngine {
    private static let maximumOfflineInterval: TimeInterval = 12 * 60 * 60

    public static func advance(_ snapshot: inout PetSnapshot, to date: Date = Date()) {
        let rawInterval = date.timeIntervalSince(snapshot.lastUpdatedAt)
        guard rawInterval > 0 else { return }

        let interval = min(rawInterval, maximumOfflineInterval)
        let hours = interval / 3_600

        if snapshot.isSleeping {
            snapshot.stats.hunger -= hours * 2.0
            snapshot.stats.mood += hours * 1.0
            snapshot.stats.energy += hours * 18.0
            if snapshot.stats.energy >= 99 {
                snapshot.isSleeping = false
            }
        } else {
            snapshot.stats.hunger -= hours * 4.0
            snapshot.stats.mood -= hours * 1.3
            snapshot.stats.energy -= hours * 2.2
        }

        snapshot.stats.clamp()
        snapshot.lastUpdatedAt = date

        if snapshot.codexActivity == .completed || snapshot.codexActivity == .failed {
            if date.timeIntervalSince(snapshot.activityChangedAt) > 12 {
                snapshot.codexActivity = .idle
                snapshot.activityChangedAt = date
            }
        }

        recalculateStage(&snapshot)
    }

    public static func perform(
        _ action: PetCareAction,
        on snapshot: inout PetSnapshot,
        at date: Date = Date()
    ) {
        advance(&snapshot, to: date)

        switch action {
        case .feed:
            snapshot.isSleeping = false
            snapshot.stats.hunger += 28
            snapshot.stats.mood += 5
            snapshot.stats.energy += 2
            snapshot.experience += 7
            snapshot.careAffinity += 3
            snapshot.feedCount += 1

        case .play:
            snapshot.isSleeping = false
            snapshot.stats.mood += 25
            snapshot.stats.energy -= 8
            snapshot.stats.hunger -= 4
            snapshot.experience += 9
            snapshot.sparkAffinity += 4
            snapshot.playCount += 1

        case .sleepOrWake:
            if snapshot.isSleeping {
                snapshot.isSleeping = false
                snapshot.stats.mood += 2
            } else {
                snapshot.isSleeping = true
                snapshot.stats.energy += 18
                snapshot.stats.hunger -= 3
                snapshot.experience += 4
                snapshot.careAffinity += 1
                snapshot.restCount += 1
            }
        }

        snapshot.stats.clamp()
        snapshot.lastUpdatedAt = date
        recalculateStage(&snapshot)
    }

    @discardableResult
    public static func apply(
        _ activity: CodexActivity,
        to snapshot: inout PetSnapshot,
        at date: Date = Date(),
        eventID: String? = nil,
        deduplicate: Bool = true
    ) -> Bool {
        let signalKey = eventID.map { "\(activity.rawValue):\($0)" }

        if deduplicate {
            if let signalKey,
               (snapshot.processedCodexSignals ?? []).contains(signalKey) {
                return false
            }

            if signalKey == nil, let previousDate = snapshot.lastCodexSignalAt {
                if date < previousDate {
                    return false
                }
                if snapshot.lastCodexSignalActivity == activity,
                   date.timeIntervalSince(previousDate) < 5 {
                    return false
                }
            }
        }

        let effectiveDate = max(date, snapshot.lastUpdatedAt)
        advance(&snapshot, to: effectiveDate)

        snapshot.lastCodexSignalAt = date
        snapshot.lastCodexSignalActivity = activity
        if let signalKey {
            var signals = snapshot.processedCodexSignals ?? []
            signals.append(signalKey)
            snapshot.processedCodexSignals = Array(signals.suffix(64))
        }

        snapshot.codexActivity = activity
        snapshot.activityChangedAt = effectiveDate

        switch activity {
        case .idle:
            break
        case .running:
            snapshot.isSleeping = false
            snapshot.stats.energy -= 1
            snapshot.stats.hunger -= 0.5
        case .completed:
            snapshot.isSleeping = false
            snapshot.experience += 15
            snapshot.stats.mood += 10
            snapshot.stats.energy -= 2
            snapshot.careAffinity += 4
            snapshot.completedTasks += 1
        case .failed:
            snapshot.isSleeping = false
            snapshot.experience += 4
            snapshot.stats.mood -= 4
            snapshot.stats.energy -= 3
            snapshot.careAffinity += 1
            snapshot.failedTasks += 1
        }

        snapshot.stats.clamp()
        snapshot.lastUpdatedAt = effectiveDate
        recalculateStage(&snapshot)
        return true
    }

    private static func recalculateStage(_ snapshot: inout PetSnapshot) {
        let earnedStage: PetStage
        switch snapshot.experience {
        case ..<20:
            earnedStage = .egg
        case ..<75:
            earnedStage = .hatchling
        case ..<180:
            earnedStage = .juvenile
        case ..<360:
            earnedStage = .ascended
        default:
            earnedStage = .legendary
        }

        // Progress is monotonic. In particular, a legacy guardian/dreamer save
        // decodes as ascended and must never be demoted by the new thresholds.
        if earnedStage.rank > snapshot.stage.rank {
            snapshot.stage = earnedStage
        }
    }
}
