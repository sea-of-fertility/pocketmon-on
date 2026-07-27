//
//  SettingsView.swift
//  poketmon
//
//  설정 패널 — NSPanel + SwiftUI 구현
//  표시(크기/투명도/표시위치), 행동(속도/빈도/수면), 시스템(자동실행)
//  변경 즉시 반영, UserDefaults 저장
//

import SwiftUI
import AppKit

// MARK: - 설정 윈도우 컨트롤러

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var panel: NSPanel?

    /// 설정 윈도우 열기 (이미 열려있으면 앞으로 가져오기)
    func open() {
        if let existing = panel, existing.isVisible {
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKey()
            return
        }

        panel = nil

        let newPanel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newPanel.title = String(localized: "Settings")
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces]
        newPanel.isMovableByWindowBackground = true
        newPanel.animationBehavior = .utilityWindow
        newPanel.isReleasedWhenClosed = false
        newPanel.delegate = self

        // 포켓몬 현재 위치의 모니터 중앙에 배치
        let petPos = PetManager.shared.stateMachine.position
        let screen = NSScreen.screens.first { $0.frame.contains(petPos) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let screen {
            let visible = screen.visibleFrame
            let size = newPanel.frame.size
            newPanel.setFrameOrigin(CGPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            ))
        }

        newPanel.contentView = NSHostingView(rootView: SettingsView())

        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = newPanel
    }

    /// 설정 윈도우 닫기
    func close() {
        panel?.close()
        panel = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}

// MARK: - 설정 메인 뷰

struct SettingsView: View {

    var body: some View {
        let settings = PetManager.shared.settingsManager

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    displaySection(settings)
                    behaviorSection(settings)
                    systemSection(settings)
                }
                .padding(20)
            }

            Divider()
            footerButtons(settings)
        }
    }

    // MARK: - 표시 섹션

    @ViewBuilder
    private func displaySection(_ settings: SettingsManager) -> some View {
        SettingsSectionHeader(title: "Display")

        // 크기
        SettingsSliderRow(
            label: "Size",
            value: Binding(
                get: { settings.spriteScale },
                set: { settings.spriteScale = $0 }
            ),
            range: 50...200,
            step: 1,
            minLabel: "50%",
            maxLabel: "200%",
            valueLabel: "\(Int(settings.spriteScale))%"
        )

        // 투명도
        SettingsSliderRow(
            label: "Opacity",
            value: Binding(
                get: { settings.opacity },
                set: { settings.opacity = $0 }
            ),
            range: 30...100,
            step: 1,
            minLabel: "Clear",
            maxLabel: "Opaque",
            valueLabel: "\(Int(settings.opacity))%"
        )

        // 표시 위치
        HStack {
            Text("Window level")
                .font(.system(size: 13))
                .frame(width: 70, alignment: .leading)

            Picker("", selection: Binding(
                get: { settings.windowLevelOption },
                set: { settings.windowLevelOption = $0 }
            )) {
                ForEach(WindowLevelOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }

        // 이동 범위
        HStack {
            Text("Movement area")
                .font(.system(size: 13))
                .frame(width: 70, alignment: .leading)

            Picker("", selection: Binding(
                get: { settings.restrictedMonitorName ?? "" },
                set: { settings.restrictedMonitorName = $0.isEmpty ? nil : $0 }
            )) {
                Text("All monitors").tag("")
                ForEach(settings.availableMonitors, id: \.name) { monitor in
                    Text(monitorLabel(monitor)).tag(monitor.name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    // MARK: - 행동 섹션

    @ViewBuilder
    private func behaviorSection(_ settings: SettingsManager) -> some View {
        SettingsSectionHeader(title: "Behavior")

        // 이동 속도
        SettingsStepSliderRow(
            label: "Speed",
            value: Binding(
                get: { settings.movementSpeed },
                set: { settings.movementSpeed = $0 }
            ),
            range: 1...5,
            minLabel: "Slow",
            maxLabel: "Fast",
            valueLabel: settings.movementSpeedLabel
        )

        // 활동 빈도
        SettingsStepSliderRow(
            label: "Activity",
            value: Binding(
                get: { settings.activityFrequency },
                set: { settings.activityFrequency = $0 }
            ),
            range: 1...5,
            minLabel: "Calm",
            maxLabel: "Active",
            valueLabel: settings.activityFrequencyLabel
        )

        // 수면까지 — 2/3/5/10/15/30분, 1시간, Never (인덱스로 조작)
        SettingsStepSliderRow(
            label: "Sleep after",
            value: Binding(
                get: { settings.sleepTimeoutIndex },
                set: { settings.setSleepTimeout(index: $0) }
            ),
            range: 0...(SettingsManager.sleepTimeoutOptions.count - 1),
            minLabel: "2 min",
            maxLabel: "Never",
            valueLabel: settings.sleepTimeoutLabel
        )
    }

    // MARK: - 시스템 섹션

    @ViewBuilder
    private func systemSection(_ settings: SettingsManager) -> some View {
        SettingsSectionHeader(title: "System")

        Toggle("Launch at login", isOn: Binding(
            get: { settings.autoLaunch },
            set: { settings.autoLaunch = $0 }
        ))
        .font(.system(size: 13))
        .toggleStyle(.checkbox)
    }

    // MARK: - 모니터 레이블

    private func monitorLabel(_ monitor: (name: String, frame: CGRect)) -> String {
        let geo = ScreenGeometry.shared
        guard let primaryFrame = geo.screenFrames.first else { return monitor.name }

        if monitor.frame == primaryFrame {
            return String(localized: "\(monitor.name) (Primary)")
        }
        if monitor.frame.midX < primaryFrame.minX {
            return String(localized: "\(monitor.name) (Left)")
        } else if monitor.frame.midX > primaryFrame.maxX {
            return String(localized: "\(monitor.name) (Right)")
        } else if monitor.frame.midY > primaryFrame.maxY {
            return String(localized: "\(monitor.name) (Above)")
        } else {
            return String(localized: "\(monitor.name) (Below)")
        }
    }

    // MARK: - 하단 버튼

    private func footerButtons(_ settings: SettingsManager) -> some View {
        HStack {
            Button("Restore Defaults") {
                settings.resetToDefaults()
            }

            Spacer()

            Button("Close") {
                SettingsWindowController.shared.close()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - 섹션 헤더

private struct SettingsSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Divider()
        }
    }
}

// MARK: - 슬라이더 행 (연속 값)

private struct SettingsSliderRow: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let minLabel: LocalizedStringKey
    let maxLabel: LocalizedStringKey
    let valueLabel: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: 70, alignment: .leading)

            VStack(spacing: 2) {
                Slider(value: $value, in: range)
                HStack {
                    Text(minLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(maxLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(valueLabel)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
        }
    }
}

// MARK: - 스텝 슬라이더 행 (정수 값)

private struct SettingsStepSliderRow: View {
    let label: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    let minLabel: LocalizedStringKey
    let maxLabel: LocalizedStringKey
    let valueLabel: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: 70, alignment: .leading)

            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { value = Int($0.rounded()) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                HStack {
                    Text(minLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(maxLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(valueLabel)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 60, alignment: .trailing)
        }
    }
}
