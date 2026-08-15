import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "设置",
                systemImage: "gearshape",
                description: Text("设置页面即将推出")
            )
            .navigationTitle("设置")
        }
    }
}

#Preview {
    SettingsView()
}
