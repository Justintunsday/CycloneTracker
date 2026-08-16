import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(L("语言"), selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    Picker(L("外观"), selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { appearance in
                            Text(appearance.displayName).tag(appearance)
                        }
                    }
                } header: {
                    Text(L("外观"))
                } footer: {
                    Text(L("语言设置立即生效,无需重启 App。"))
                }

                Section {
                    LabeledContent(L("版本"), value: appVersion)
                    LabeledContent(L("部署目标"), value: "iOS 26")
                } header: {
                    Text(L("关于"))
                }

                Section {
                    LabeledContent(L("实时数据"), value: "NHC / JTWC")
                    LabeledContent(L("历史数据"), value: L("IBTrACS v04r01 (1851–今)"))
                    LabeledContent(L("历史缓存"), value: "Caches/IBTrACSCache")
                } header: {
                    Text(L("数据来源"))
                } footer: {
                    Text(L("实时判定:与 IBTrACS 文件内最新数据时间对比,落后超过 18 小时或最后定位距今超过 60 小时视为已消散。数据仅供信息参考,请以官方发布为准。"))
                }
            }
            .navigationTitle(L("设置"))
        }
    }
}

#Preview {
    SettingsView()
}
