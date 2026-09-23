import Foundation

/// Swift Charts' `Plottable` does not include `Decimal`, so values cross into
/// the chart as `Double`. This is the only place that conversion is allowed:
/// the loss of precision is confined to pixels, never to a stored or summed
/// figure.
extension Decimal {
    var plotted: Double {
        (self as NSDecimalNumber).doubleValue
    }
}
