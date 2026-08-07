#if os(iOS)
import SwiftUI

/// One instruction at a time, because the people this screen exists for are the
/// ones who have never managed to see a stereogram — a wall of tips is exactly
/// what already failed them.
enum TrainerStep: Int, CaseIterable, Identifiable {
    case armsLength = 1
    case lookThrough
    case doubleUp
    case sphere

    var id: Int { rawValue }

    static let count = TrainerStep.allCases.count

    var progress: Double { Double(rawValue) / Double(TrainerStep.count) }

    var title: LocalizedStringKey {
        switch self {
        case .armsLength: "trainer.step1_title"
        case .lookThrough: "trainer.step2_title"
        case .doubleUp: "trainer.step3_title"
        case .sphere: "trainer.step4_title"
        }
    }

    var body: LocalizedStringKey {
        switch self {
        case .armsLength: "trainer.step1_body"
        case .lookThrough: "trainer.step2_body"
        case .doubleUp: "trainer.step3_body"
        case .sphere: "trainer.step4_body"
        }
    }

    var primaryTitle: LocalizedStringKey {
        switch self {
        case .armsLength: "trainer.step1_primary"
        case .lookThrough: "trainer.step2_primary"
        case .doubleUp: "trainer.step3_primary"
        case .sphere: "trainer.step4_primary"
        }
    }

    /// Step 3 has nothing useful to offer as an escape hatch — you are either
    /// holding the doubling or you are not.
    var secondaryTitle: LocalizedStringKey? {
        switch self {
        case .armsLength: "trainer.step1_secondary"
        case .lookThrough: "trainer.step2_secondary"
        case .doubleUp: nil
        case .sphere: "trainer.step4_secondary"
        }
    }

    var next: TrainerStep? { TrainerStep(rawValue: rawValue + 1) }
    var previous: TrainerStep? { TrainerStep(rawValue: rawValue - 1) }
}
#endif
