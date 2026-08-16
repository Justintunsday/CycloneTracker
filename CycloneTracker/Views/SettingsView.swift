import SwiftUI

struct SettingsView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("部署目标", value: "iOS 26")
                } header: {
                    Text("关于")
                }

                Section {
                    LabeledContent("实时数据", value: "NHC / JTWC(经 IBTrACS 实时合并)")
                    LabeledContent("历史数据", value: "IBTrACS v04r01 (1851–今)")
                    LabeledContent("历史缓存", value: "Caches/IBTrACSCache")
                } header: {
                    Text("数据来源")
                } footer: {
                    Text("实时判定:与 IBTrACS 文件内最新数据时间对比,落后超过 18 小时或最后定位距今超过 60 小时视为已消散。数据仅供信息参考,请以官方发布为准。")
                }
            }
            .navigationTitle("设置")
        }
    }
}

#Preview {
    SettingsView()
}
