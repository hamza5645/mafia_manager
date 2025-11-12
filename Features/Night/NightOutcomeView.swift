import SwiftUI

struct NightOutcomeView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selection: OutcomeSelection?
    @State private var goToMorning = false

    private enum OutcomeSelection: CaseIterable {
        case killed
        case saved

        var title: String {
            switch self {
            case .killed: return "Player Died"
            case .saved: return "Doctor Saved"
            }
        }

        var subtitle: String {
            switch self {
            case .killed: return "Remove the targeted player before the day begins"
            case .saved: return "Keep the targeted player alive for the next day"
            }
        }

        var icon: String {
            switch self {
            case .killed: return "skull.fill"
            case .saved: return "cross.case.fill"
            }
        }

        var accent: Color {
            switch self {
            case .killed: return Design.Colors.dangerRed
            case .saved: return Design.Colors.successGreen
            }
        }
    }

    private var lastNight: NightAction? { store.state.nightHistory.last }

    private var targetedPlayer: Player? {
        store.player(by: lastNight?.mafiaTargetPlayerID)
    }

    private var defaultSelection: OutcomeSelection? {
        guard let night = lastNight, targetedPlayer != nil else { return nil }
        if night.doctorProtectedPlayerID == night.mafiaTargetPlayerID {
            return .saved
        }
        return .killed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                targetCard

                doctorHint

                outcomePicker

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(
            NavigationLink(destination: MorningSummaryView(), isActive: $goToMorning) { EmptyView() }
                .hidden()
        )
        .navigationTitle("Resolve Night")
        .background(Design.Colors.surface0.ignoresSafeArea())
        .onAppear {
            if selection == nil, let suggested = defaultSelection {
                selection = suggested
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button {
                    guard let selection else { return }
                    store.resolveNightOutcome(targetWasSaved: selection == .saved)
                    goToMorning = true
                } label: {
                    Text("Continue to Morning")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButtonStyle(kind: .primary))
                .disabled(targetedPlayer == nil || selection == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Design.Colors.surface0.opacity(0.95))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Night \(lastNight?.nightIndex ?? store.currentNightIndex)")
                .font(.system(size: 26, weight: .heavy))
                .kerning(1)
            Text("Confirm whether the mafia's target survived.")
                .foregroundStyle(Design.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private var targetCard: some View {
        if let target = targetedPlayer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mafia Target")
                    .font(.headline)
                    .foregroundStyle(Design.Colors.textPrimary)

                HStack(spacing: 12) {
                    Chip(text: "#\(target.number)", style: .outline(Design.Colors.textSecondary))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(target.name)
                            .font(.title3.bold())
                        Text(target.role.displayName)
                            .font(.subheadline)
                            .foregroundStyle(target.role.accentColor)
                    }
                    Spacer()
                }

                if target.alive == false {
                    Label("Already removed earlier", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Design.Colors.dangerRed)
                }
            }
            .cardStyle()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No mafia target recorded.")
                    .font(.headline)
                Text("Return to the previous step to pick a target before resolving the night.")
                    .foregroundStyle(Design.Colors.textSecondary)
            }
            .cardStyle()
        }
    }

    @ViewBuilder
    private var doctorHint: some View {
        let doctorNumbers = store.state.players.filter { $0.role == .doctor && $0.alive }.map { $0.number }.sorted()
        if !doctorNumbers.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(Design.Colors.successGreen)
                Text("Doctor on duty: \(doctorNumbers.map { "#\($0)" }.joined(separator: ", "))")
                    .foregroundStyle(Design.Colors.textSecondary)
                    .font(.footnote)
            }
        }
    }

    private var outcomePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Outcome")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(OutcomeSelection.allCases, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle().fill(option.accent.opacity(0.2))
                                Image(systemName: option.icon)
                                    .foregroundStyle(option.accent)
                            }
                            .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title)
                                    .font(.subheadline.bold())
                                Text(option.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(Design.Colors.textSecondary)
                            }
                            Spacer()

                            if selection == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(option.accent)
                                    .font(.title3)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .background(selection == option ? option.accent.opacity(0.15) : Design.Colors.surface2)
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radii.card, style: .continuous)
                                .stroke(selection == option ? option.accent : Design.Colors.stroke, lineWidth: 1.2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radii.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
