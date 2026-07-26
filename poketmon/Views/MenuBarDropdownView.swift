//
//  MenuBarDropdownView.swift
//  poketmon
//
//  메뉴바 드롭다운 콘텐츠 — 현재 포켓몬 정보 + 상태 제어
//

import SwiftUI

struct MenuBarDropdownView: View {

    var body: some View {
        let pet = PetManager.shared
        let data = pet.pokemonDataManager.pokemon(id: pet.currentPokemonID)
        let state = pet.stateMachine.currentState
        let isSleeping = state == .sleep

        VStack(alignment: .leading, spacing: 0) {

            // MARK: 헤더 — 현재 포켓몬 정보
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(stateColor(state))
                        .frame(width: 8, height: 8)
                    Text("\(data?.localizedName ?? "???") \(data?.displayNumber ?? "")")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text("Status: \(state.displayName)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            Divider()

            // MARK: 내비게이션
            DropdownMenuItem("Change Pokémon...", icon: "arrow.triangle.2.circlepath") {
                DispatchQueue.main.async {
                    PokemonSelectorWindowController.shared.open()
                }
            }
            DropdownMenuItem("Settings...", icon: "gearshape") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.open()
                }
            }

            Divider()

            // MARK: 상태 제어
            DropdownPauseItem()

            DropdownMenuItem(isSleeping ? "Wake up" : "Put to sleep",
                             icon: isSleeping ? "sun.max.fill" : "moon.fill") {
                if isSleeping { pet.wake() } else { pet.sleep() }
            }

            DropdownMenuItem(state == .run ? "Make it walk" : "Make it run",
                             icon: state == .run ? "tortoise.fill" : "hare.fill") {
                if state == .run { pet.walk() } else { pet.run() }
            }

            Divider()

            // MARK: 종료
            DropdownMenuItem("Quit", icon: "xmark.circle", isDestructive: true) {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 240)
    }

    // MARK: - 상태별 색상

    private func stateColor(_ state: PetState) -> Color {
        switch state {
        case .idle: .green
        case .walk: .blue
        case .run: .orange
        case .sleep: .purple
        case .reaction: .pink
        case .dragged: .gray
        }
    }
}

// MARK: - 메뉴 아이템

private struct DropdownMenuItem: View {
    let title: LocalizedStringKey
    let icon: String
    var isDestructive: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(_ title: LocalizedStringKey, icon: String, isDestructive: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .foregroundStyle(isDestructive ? .red : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                isHovered ? Color.accentColor.opacity(0.15) : .clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 4)
    }
}

// MARK: - 일시정지 토글

private struct DropdownPauseItem: View {
    @State private var isHovered = false

    var body: some View {
        let isPaused = PetManager.shared.isPaused

        Button {
            PetManager.shared.togglePause()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pause.fill")
                    .frame(width: 18)
                Text("Pause")
                Spacer()
                // 토글 스위치 인디케이터
                Capsule()
                    .fill(isPaused ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 30, height: 16)
                    .overlay(alignment: isPaused ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .padding(2)
                    }
                    .animation(.easeInOut(duration: 0.15), value: isPaused)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                isHovered ? Color.accentColor.opacity(0.15) : .clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 4)
    }
}
