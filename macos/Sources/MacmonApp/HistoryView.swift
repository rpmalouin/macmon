import MacmonCore
import SwiftUI

/// The history block: the last minute of CPU, and of GPU where the machine reports one.
///
/// The geometry is `Sparkline`'s; this only strokes what it is given, so a gap the window found
/// stays a break in the drawing.
struct HistoryView: View {
  let sparkline: Sparkline
  var height: CGFloat = 30

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ZStack(alignment: .topLeading) {
        line(sparkline.cpu, colour: .primary, opacity: 0.75)
        if sparkline.hasGPU {
          line(sparkline.gpu, colour: .primary, opacity: 0.35)
        }
      }
      .frame(height: height)
      Text(caption)
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }
  }

  private var caption: String {
    let seconds = Int(sparkline.span.rounded())
    return sparkline.hasGPU ? "CPU · GPU · last \(seconds) s" : "CPU · last \(seconds) s"
  }

  private func line(_ runs: [Sparkline.Run], colour: Color, opacity: Double) -> some View {
    GeometryReader { geometry in
      Path { path in
        for run in runs {
          let points = Sparkline.points(values: run.values, size: geometry.size, scale: sparkline.scale)
          guard let first = points.first else { continue }
          path.move(to: first)
          for point in points.dropFirst() { path.addLine(to: point) }
        }
      }
      .stroke(colour, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
      .opacity(opacity)
    }
  }
}
