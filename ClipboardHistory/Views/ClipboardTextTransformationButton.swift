import SwiftUI

struct ClipboardTextTransformationButton: View {
    let transformation: TextTransformation
    @Binding var text: String

    var body: some View {
        Button(transformation.title, action: apply)
    }

    func apply() {
        text = transformation.apply(to: text)
    }
}
