import Foundation

/// Round values to mark a chart's amount axis with: evenly spaced, a step of
/// 1, 2, 2.5 or 5 times a power of ten, all inside the range drawn.
///
/// Worked out here rather than left to Swift Charts because the labels need
/// the step: a line fitted to 15,050…15,600 is marked every 100, and a label
/// rounded to whole thousands would read "15k" on every one of them.
struct AxisTicks: Equatable {
    /// Lowest first.
    let values: [Decimal]
    /// The gap between neighbouring values; zero when there is only one.
    let step: Decimal

    /// About `count` ticks between `low` and `high`, inclusive.
    init(from low: Decimal, to high: Decimal, about count: Int = 4) {
        guard high > low, count > 0 else {
            self.values = [low]
            self.step = 0
            return
        }
        let step = Self.niceStep(atLeast: (high - low) / Decimal(count))
        var values: [Decimal] = []
        var tick = Self.roundedUp(low / step) * step
        while tick <= high {
            values.append(tick)
            tick += step
        }
        self.values = values
        self.step = step
    }

    /// The smallest of 1, 2, 2.5, 5 or 10 times a power of ten that is at
    /// least `raw`.
    private static func niceStep(atLeast raw: Decimal) -> Decimal {
        let exponent = Int(log10(raw.plotted).rounded(.down))
        let power = Decimal(sign: .plus, exponent: exponent, significand: 1)
        let multiples: [Decimal] = [1, 2, Decimal(25) / 10, 5, 10]
        return multiples.lazy.map { $0 * power }.first { $0 >= raw } ?? 10 * power
    }

    private static func roundedUp(_ value: Decimal) -> Decimal {
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, 0, .up)
        return result
    }
}
