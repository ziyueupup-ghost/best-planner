import Foundation

/// Option-like values stored as text. A value this version doesn't know (written by a
/// newer version on another Mac, or a damaged entry) becomes `fallback` instead of making
/// the whole data file unreadable.
protocol LenientEnum: RawRepresentable, Codable where RawValue == String {
    static var fallback: Self { get }
}

extension LenientEnum {
    init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = raw.flatMap(Self.init(rawValue:)) ?? Self.fallback
    }
}

extension FoldMode: LenientEnum { static var fallback: FoldMode { .off } }
extension Recurrence: LenientEnum { static var fallback: Recurrence { .none } }
extension SortMode: LenientEnum { static var fallback: SortMode { .manual } }
extension DateKind: LenientEnum { static var fallback: DateKind { .deadline } }
extension HistoryKind: LenientEnum { static var fallback: HistoryKind { .edited } }
extension TagShape: LenientEnum { static var fallback: TagShape { .capsule } }
extension TagStyle: LenientEnum { static var fallback: TagStyle { .soft } }
extension TagBorder: LenientEnum { static var fallback: TagBorder { .auto } }
