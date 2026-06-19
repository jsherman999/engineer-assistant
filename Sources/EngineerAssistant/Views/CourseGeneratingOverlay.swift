import SwiftUI

/// Full-screen, multi-color working indicator shown while Claude designs a course.
struct CourseGeneratingOverlay: View {
    let subject: String?

    @State private var spin = false
    @State private var pulse = false
    @State private var phase = false

    private let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .indigo, .purple]

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()

            VStack(spacing: 30) {
                indicator
                VStack(spacing: 6) {
                    Text("Designing your course…")
                        .font(.system(size: 26, weight: .bold))
                    if let subject, !subject.isEmpty {
                        Text("“\(subject)”")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Text("Claude is writing lessons, demos, and hands-on challenges.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { phase = true }
        }
    }

    private var indicator: some View {
        ZStack {
            // Rotating rainbow ring
            Circle()
                .stroke(
                    AngularGradient(colors: colors + [colors[0]], center: .center),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .shadow(color: .blue.opacity(0.25), radius: 12)

            // Counter-rotating orbit of colored dots
            ZStack {
                ForEach(0..<colors.count, id: \.self) { i in
                    Circle()
                        .fill(colors[i])
                        .frame(width: 18, height: 18)
                        .offset(y: -92)
                        .rotationEffect(.degrees(Double(i) / Double(colors.count) * 360))
                        .shadow(color: colors[i].opacity(0.6), radius: 5)
                }
            }
            .rotationEffect(.degrees(spin ? -360 : 0))
            .scaleEffect(pulse ? 1.06 : 0.92)

            // Soft pulsing core
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.9), .blue.opacity(0.15)], center: .center, startRadius: 2, endRadius: 40))
                .frame(width: 46, height: 46)
                .scaleEffect(phase ? 1.15 : 0.85)
                .opacity(0.8)
        }
        .frame(width: 220, height: 220)
    }
}
