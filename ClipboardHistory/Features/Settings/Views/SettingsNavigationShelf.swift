import SwiftUI

struct SettingsNavigationShelf<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let systemImage: (Item) -> String
    let buttonIdentifier: (Item) -> String
    let shelfIdentifier: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollTarget: Item?

    init(
        items: [Item],
        selection: Binding<Item>,
        title: @escaping (Item) -> String,
        systemImage: @escaping (Item) -> String,
        buttonIdentifier: @escaping (Item) -> String,
        shelfIdentifier: String
    ) {
        self.items = items
        _selection = selection
        self.title = title
        self.systemImage = systemImage
        self.buttonIdentifier = buttonIdentifier
        self.shelfIdentifier = shelfIdentifier
        _scrollTarget = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    SettingsShelfButton(
                        title: title(item),
                        systemImage: systemImage(item),
                        isSelected: selection == item,
                        action: { selection = item }
                    )
                    .id(item)
                    .accessibilityIdentifier(buttonIdentifier(item))
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .scrollPosition(id: $scrollTarget, anchor: .center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier(shelfIdentifier)
        .task {
            scrollTarget = nil
            await Task.yield()
            scrollTarget = selection
        }
        .onChange(of: selection) { _, selectedItem in
            if reduceMotion {
                scrollTarget = selectedItem
            } else {
                withAnimation(.easeInOut(duration: 0.12)) {
                    scrollTarget = selectedItem
                }
            }
        }
    }
}
