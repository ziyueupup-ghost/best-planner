import SwiftUI

/// A number you can type, with ↑/↓ arrows next to it. Values outside `range` are pulled
/// back in when typing finishes.
struct NumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 48

    var body: some View {
        HStack(spacing: 4) {
            // Text, not a number format: a number format only applies on Return, so clicking
            // a button right after typing would still use the old value.
            TextField("", text: Binding(
                get: { String(value) },
                set: { text in
                    guard let n = Int(text.filter(\.isNumber)) else { return }
                    value = min(max(n, range.lowerBound), range.upperBound)
                }))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: width)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
    }
}
