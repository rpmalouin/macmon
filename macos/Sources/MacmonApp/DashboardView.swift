import MacmonCore
import SwiftUI

/// The panel's state: what the status item is showing, in a form the panel can render.
@Observable
final class PanelModel {
  var dashboard: Dashboard?
  /// The history block's series, nil while the window is too short to draw.
  var sparkline: Sparkline?
  var failure: String?
}

/// The panel behind the status item.
struct DashboardView: View {
  let model: PanelModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 1) {
        Text(model.dashboard?.title ?? "macmon").font(.system(size: 12, weight: .semibold))
        if let detail = model.dashboard?.detail {
          Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
        }
      }

      if let failure = model.failure {
        Text(failure)
          .font(.system(size: 10))
          .foregroundStyle(.red)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }

      let sections = model.dashboard?.sections ?? []
      let head = sections.prefix { $0.id == "cpu" || $0.id == "gpu" }
      let tail = sections.drop { $0.id == "cpu" || $0.id == "gpu" }

      ForEach(head) { section in SectionView(section: section) }
      if let sparkline = model.sparkline {
        HistoryView(sparkline: sparkline)
      }
      ForEach(tail) { section in SectionView(section: section) }

      Divider()
      HStack {
        Button("Quit") { NSApplication.shared.terminate(nil) }
          .font(.system(size: 10))
        Spacer()
      }
    }
    .padding(12)
    .frame(width: 300, alignment: .leading)
  }
}

/// One titled group of rows.
private struct SectionView: View {
  let section: DashboardSection

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      if let title = section.title {
        Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
      }
      ForEach(section.rows) { row in RowView(row: row) }
    }
  }
}

/// One row: label, optional bar, value, optional detail. Every column is one line: a wrapped value
/// reflows the whole panel, which is how the memory row first rendered.
private struct RowView: View {
  let row: DashboardRow

  var body: some View {
    HStack(spacing: 6) {
      Text(row.label)
        .font(.system(size: 11))
        .lineLimit(1)
        .padding(.leading, row.indented ? 10 : 0)
        .frame(width: 62, alignment: .leading)
      if let fraction = row.fraction {
        ProgressView(value: fraction, total: 1)
          .progressViewStyle(.linear)
          .frame(height: 4)
      } else {
        Spacer(minLength: 0)
      }
      Text(row.value)
        .font(.system(size: 11, design: .monospaced))
        .lineLimit(1)
        .frame(width: 84, alignment: .trailing)
      Text(row.detail ?? "")
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: 60, alignment: .trailing)
    }
  }
}
