import SwiftUI

struct RenameReviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Review Image Names")
                        .font(.title2.weight(.semibold))
                    Text("Names read from \(model.renameReviewSource). Correct anything before applying.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("\(completedCount) of \(model.renameReviewRows.count)", systemImage: "checkmark.circle")
                    .foregroundStyle(completedCount == model.renameReviewRows.count ? .green : .orange)
            }
            .padding(20)

            Divider()

            HStack {
                Text("Original image")
                    .frame(width: 260, alignment: .leading)
                Text("New filename")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($model.renameReviewRows) { $row in
                        HStack(spacing: 14) {
                            Text(row.originalFilename)
                                .lineLimit(1)
                                .frame(width: 260, alignment: .leading)
                            TextField("Enter new filename", text: $row.newFilename)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 10)
            }

            Divider()

            HStack {
                Text("Filename extensions are changed automatically to match the selected export formats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: model.cancelRenameReview)
                    .keyboardShortcut(.cancelAction)
                Button("Apply Names", action: model.applyRenameReview)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(completedCount == 0)
            }
            .padding(16)
        }
        .frame(width: 760, height: 520)
    }

    private var completedCount: Int {
        model.renameReviewRows.filter {
            !$0.newFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }
}
