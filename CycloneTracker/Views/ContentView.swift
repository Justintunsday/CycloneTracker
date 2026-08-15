import SwiftUI

struct ContentView: View {
    @State private var store = CycloneStore()

    var body: some View {
        TabView {
            Tab("地图", systemImage: "map") {
                CycloneMapView(store: store)
            }
            Tab("设置", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .task {
            await store.refreshActive()
        }
    }
}

#Preview {
    ContentView()
}
