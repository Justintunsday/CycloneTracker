import SwiftUI

struct ContentView: View {
    @State private var store = CycloneStore()

    var body: some View {
        TabView {
            Tab(L("地图"), systemImage: "map") {
                NavigationStack {
                    CycloneMapView(store: store)
                }
            }
            Tab(L("设置"), systemImage: "gearshape") {
                SettingsView()
            }
        }
        .preferredColorScheme(AppSettings.shared.appearance.colorScheme)
        .environment(\.locale, AppSettings.shared.language.locale ?? .current)
        .task {
            await store.refreshActive()
        }
    }
}

#Preview {
    ContentView()
}
