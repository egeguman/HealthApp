import Foundation

extension Collection where Element == Double {
    nonisolated var mean: Double? {
        isEmpty ? nil : reduce(0, +) / Double(count)
    }

    /// Sample standard deviation.
    nonisolated var standardDeviation: Double? {
        guard count >= 2, let mean else { return nil }
        let variance = reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(count - 1)
        return variance.squareRoot()
    }

    /// Linear-interpolated percentile, `p` in 0...1.
    nonisolated func percentile(_ p: Double) -> Double? {
        guard !isEmpty else { return nil }
        let sorted = self.sorted()
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}

extension Collection where Element == Reading {
    nonisolated var meanValue: Double? { map(\.value).mean }
    nonisolated var maxValue: Double? { map(\.value).max() }
}

extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
