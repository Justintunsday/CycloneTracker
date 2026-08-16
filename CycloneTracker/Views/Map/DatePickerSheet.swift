import SwiftUI

struct DatePickerSheet: View {
    @Bindable var store: CycloneStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker(
                    L("日期"),
                    selection: $store.selectedDate,
                    in: store.historicalDateRange,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)

                Button {
                    dismiss()
                } label: {
                    Text(L("确定"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
            }
            .padding()
            .navigationTitle(L("选择日期"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
