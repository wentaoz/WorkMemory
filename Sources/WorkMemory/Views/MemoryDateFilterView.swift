import SwiftUI

struct MemoryDateFilterView: View {
    @Binding var preset: MemoryDateFilterPreset
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    let filteredCount: Int
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    header
                    picker
                    customDatePickers
                    Spacer()
                    countLabel
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        header
                        picker
                    }

                    customDatePickers
                    countLabel
                }
            }

            Text(preset.rangeDescription(customStartDate: customStartDate, customEndDate: customEndDate))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        Label("日期筛选", systemImage: "calendar")
            .font(.headline)
    }

    private var picker: some View {
        Picker("日期筛选", selection: $preset) {
            ForEach(MemoryDateFilterPreset.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 130)
    }

    @ViewBuilder
    private var customDatePickers: some View {
        if preset.usesCustomRange {
            HStack(spacing: 8) {
                DatePicker("开始", selection: $customStartDate, displayedComponents: .date)
                    .datePickerStyle(.compact)

                DatePicker("结束", selection: $customEndDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }
        }
    }

    private var countLabel: some View {
        Label("\(filteredCount) / \(totalCount) 条", systemImage: "line.3.horizontal.decrease.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
