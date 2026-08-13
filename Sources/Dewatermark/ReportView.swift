import SwiftUI
import DewatermarkCore

struct ReportView: View {
    let report: TextInspectReport

    var body: some View {
        GroupBox("Inspect report") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    Label("\(report.length) chars", systemImage: "text.alignleft")
                    Label(
                        report.suspiciousTotal == 0 ? "No suspicious characters" : "\(report.suspiciousTotal) suspicious",
                        systemImage: report.suspiciousTotal == 0 ? "checkmark.circle" : "exclamationmark.triangle"
                    )
                    .foregroundStyle(report.suspiciousTotal == 0 ? Color.green : Color.orange)
                }
                .font(.callout)

                if !report.hits.isEmpty {
                    Divider()
                    ForEach(report.hits) { hit in
                        HStack(alignment: .firstTextBaseline) {
                            Text(hit.codepoint)
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 62, alignment: .leading)
                            Text(hit.kind)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                            Text(hit.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("×\(hit.count)")
                                .font(.caption)
                        }
                    }
                    Text("Layer A only — statistical token-sampling marks need a Layer B rewrite.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
