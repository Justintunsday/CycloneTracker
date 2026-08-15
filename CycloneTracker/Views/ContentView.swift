import SwiftUI

struct ContentView: View {
    @State private var store = CycloneStore()

    var body: some View {
        CycloneMapView(store: store)
            .task {
                await store.refreshActive()
            }
    }
}

#Preview {
    ContentView()
}
