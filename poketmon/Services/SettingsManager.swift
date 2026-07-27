//
//  SettingsManager.swift
//  poketmon
//
//  UserDefaults 기반 설정 관리자
//  @Observable로 SwiftUI 바인딩 + PetStateMachine 동적 반영
//  변경 즉시 저장, 앱 실행 시 자동 로드
//

import AppKit
import Observation
import ServiceManagement

// MARK: - 표시 위치 옵션

enum WindowLevelOption: Int, CaseIterable {
    case alwaysOnTop = 0   // 항상 위 (모든 창 위)
    case normal = 1        // 일반 (다른 창에 가려짐)
    case desktopOnly = 2   // 바탕화면만 (모든 창 아래)

    var displayName: String {
        switch self {
        case .alwaysOnTop: String(localized: "Always on top (above all windows)")
        case .normal: String(localized: "Normal (can be covered)")
        case .desktopOnly: String(localized: "Desktop only (below all windows)")
        }
    }

    var windowLevel: NSWindow.Level {
        switch self {
        case .alwaysOnTop: .floating
        case .normal: .normal
        case .desktopOnly: NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)))
        }
    }
}

// MARK: - SettingsManager

@Observable
final class SettingsManager {

    static let shared = SettingsManager()

    // MARK: - UserDefaults 키

    private enum Key {
        static let spriteScale = "com.poketmon.settings.spriteScale"
        static let opacity = "com.poketmon.settings.opacity"
        static let windowLevel = "com.poketmon.settings.windowLevel"
        static let movementSpeed = "com.poketmon.settings.movementSpeed"
        static let activityFrequency = "com.poketmon.settings.activityFrequency"
        static let sleepTimeout = "com.poketmon.settings.sleepTimeout"
        static let autoLaunch = "com.poketmon.settings.autoLaunch"
        static let currentPokemonID = "com.poketmon.settings.currentPokemonID"
        static let lastPositionX = "com.poketmon.settings.lastPositionX"
        static let lastPositionY = "com.poketmon.settings.lastPositionY"
        static let restrictedMonitor = "com.poketmon.settings.restrictedMonitor"
    }

    // MARK: - 기본값

    private enum Default {
        static let spriteScale: Double = 100       // 100%
        static let opacity: Double = 100           // 100%
        static let windowLevel: Int = 0            // 항상 위
        static let movementSpeed: Int = 3          // 보통
        static let activityFrequency: Int = 3      // 보통
        static let sleepTimeout: Int = 3           // 3분
        static let autoLaunch: Bool = false
    }

    // MARK: - 표시 설정

    /// 로딩 중 didSet 부작용 억제
    private var isLoading = false

    /// 크기 배율 (50~200, 기본 100)
    var spriteScale: Double = Default.spriteScale {
        didSet {
            guard !isLoading else { return }
            save(spriteScale, forKey: Key.spriteScale)
        }
    }

    /// 투명도 (30~100, 기본 100)
    var opacity: Double = Default.opacity {
        didSet {
            guard !isLoading else { return }
            save(opacity, forKey: Key.opacity)
            applyOpacity()
        }
    }

    /// 표시 위치
    var windowLevelOption: WindowLevelOption = .alwaysOnTop {
        didSet {
            guard !isLoading else { return }
            save(windowLevelOption.rawValue, forKey: Key.windowLevel)
            applyWindowLevel()
        }
    }

    /// 이동 범위 제한 모니터 (nil이면 모든 모니터)
    var restrictedMonitorName: String? = nil {
        didSet {
            guard !isLoading else { return }
            if let name = restrictedMonitorName {
                save(name, forKey: Key.restrictedMonitor)
            } else {
                defaults.removeObject(forKey: Key.restrictedMonitor)
            }
            applyMonitorRestriction()
        }
    }

    // MARK: - 행동 설정

    /// 이동 속도 (1~5, 기본 3)
    var movementSpeed: Int = Default.movementSpeed {
        didSet {
            guard !isLoading else { return }
            save(movementSpeed, forKey: Key.movementSpeed)
        }
    }

    /// 활동 빈도 (1~5, 기본 3)
    var activityFrequency: Int = Default.activityFrequency {
        didSet {
            guard !isLoading else { return }
            save(activityFrequency, forKey: Key.activityFrequency)
        }
    }

    /// 수면까지 (분 단위, 0 = 잠들지 않음, 기본 3분)
    ///
    /// 저장은 분 값 그대로 — UI 슬라이더는 sleepTimeoutOptions의 인덱스로 다룬다.
    var sleepTimeout: Int = Default.sleepTimeout {
        didSet {
            guard !isLoading else { return }
            save(sleepTimeout, forKey: Key.sleepTimeout)
        }
    }

    // MARK: - 시스템 설정

    /// 로그인 시 자동 실행
    var autoLaunch: Bool = Default.autoLaunch {
        didSet {
            guard !isLoading else { return }
            save(autoLaunch, forKey: Key.autoLaunch)
            applyAutoLaunch()
        }
    }

    // MARK: - 계산 프로퍼티

    /// 실제 스프라이트 배율 (0.5~2.0)
    var spriteScaleMultiplier: CGFloat {
        CGFloat(spriteScale / 100.0)
    }

    /// 실제 윈도우 불투명도 (0.3~1.0)
    var windowOpacity: CGFloat {
        CGFloat(opacity / 100.0)
    }

    /// Walk 속도 (px/frame)
    var walkSpeedValue: CGFloat {
        // 1단계=1.0, 2=1.5, 3=2.0(기본), 4=3.0, 5=4.0
        switch movementSpeed {
        case 1: return 1.0
        case 2: return 1.5
        case 3: return 2.0
        case 4: return 3.0
        case 5: return 4.0
        default: return 2.0
        }
    }

    /// Run 속도 (Walk의 2배)
    var runSpeedValue: CGFloat {
        walkSpeedValue * 2.0
    }

    /// Idle → Walk 전환 시간 범위 (초)
    var idleToWalkRange: ClosedRange<Double> {
        // 1(조용)=4~8, 2=3~7, 3=2~5(기본), 4=1~3, 5=0.5~2(활발)
        switch activityFrequency {
        case 1: return 4.0...8.0
        case 2: return 3.0...7.0
        case 3: return 2.0...5.0
        case 4: return 1.0...3.0
        case 5: return 0.5...2.0
        default: return 2.0...5.0
        }
    }

    /// Walk → Idle 전환 시간 범위 (초)
    var walkToIdleRange: ClosedRange<Double> {
        // 1(조용)=2.5~5, 2=2.5~6, 3=3~10(기본), 4=5~15, 5=8~20(활발)
        switch activityFrequency {
        case 1: return 2.5...5.0
        case 2: return 2.5...6.0
        case 3: return 3.0...10.0
        case 4: return 5.0...15.0
        case 5: return 8.0...20.0
        default: return 3.0...10.0
        }
    }

    /// 수면까지 선택 가능한 값 (분) — 0은 "잠들지 않음"
    ///
    /// 뒤로 갈수록 간격을 넓힌 로그 스케일. 3분과 4분의 차이는 체감되지 않지만
    /// 10분과 30분의 차이는 확실히 체감되므로 균일 간격이 적절하지 않다.
    static let sleepTimeoutOptions: [Int] = [2, 3, 5, 10, 15, 30, 60, 0]

    /// 잠들지 않음 설정 여부
    var isSleepDisabled: Bool {
        sleepTimeout <= 0
    }

    /// 수면 타임아웃 (초) — 잠들지 않음이면 무한
    var sleepTimeoutSeconds: Double {
        isSleepDisabled ? .infinity : Double(sleepTimeout) * 60.0
    }

    /// 현재 sleepTimeout의 슬라이더 인덱스 (없는 값이면 가장 가까운 단계)
    var sleepTimeoutIndex: Int {
        let options = Self.sleepTimeoutOptions
        if let exact = options.firstIndex(of: sleepTimeout) { return exact }
        // 구버전에서 저장된 값(1, 4분 등) 보정 — Never를 제외하고 가장 가까운 단계
        let minutes = options.dropLast()
        let nearest = minutes.enumerated().min {
            abs($0.element - sleepTimeout) < abs($1.element - sleepTimeout)
        }
        return nearest?.offset ?? options.firstIndex(of: Default.sleepTimeout) ?? 1
    }

    /// 슬라이더 인덱스로 sleepTimeout 설정
    func setSleepTimeout(index: Int) {
        let options = Self.sleepTimeoutOptions
        guard options.indices.contains(index) else { return }
        sleepTimeout = options[index]
    }

    /// 수면까지 표시 텍스트
    var sleepTimeoutLabel: String {
        if isSleepDisabled { return String(localized: "Never") }
        if sleepTimeout >= 60 { return String(localized: "1 hr") }
        return String(localized: "\(sleepTimeout) min")
    }

    /// 이동 속도 표시 텍스트
    var movementSpeedLabel: String {
        switch movementSpeed {
        case 1: return String(localized: "Very slow")
        case 2: return String(localized: "Slow")
        case 3: return String(localized: "Moderate")
        case 4: return String(localized: "Fast")
        case 5: return String(localized: "Very fast")
        default: return String(localized: "Moderate")
        }
    }

    /// 활동 빈도 표시 텍스트
    var activityFrequencyLabel: String {
        switch activityFrequency {
        case 1: return String(localized: "Very calm")
        case 2: return String(localized: "Calm")
        case 3: return String(localized: "Moderate")
        case 4: return String(localized: "Active")
        case 5: return String(localized: "Very active")
        default: return String(localized: "Moderate")
        }
    }

    // MARK: - 데이터 영속성 (포켓몬 ID / 위치)

    /// 저장된 포켓몬 ID (없으면 25 = 피카츄)
    var savedPokemonID: Int {
        get {
            defaults.object(forKey: Key.currentPokemonID) != nil
                ? defaults.integer(forKey: Key.currentPokemonID)
                : 25
        }
        set {
            defaults.set(newValue, forKey: Key.currentPokemonID)
        }
    }

    /// 마지막 위치 저장
    func saveLastPosition(_ position: CGPoint) {
        defaults.set(position.x, forKey: Key.lastPositionX)
        defaults.set(position.y, forKey: Key.lastPositionY)
    }

    /// 마지막 위치 로드 (저장된 적 없으면 nil)
    func loadLastPosition() -> CGPoint? {
        guard defaults.object(forKey: Key.lastPositionX) != nil else { return nil }
        let x = defaults.double(forKey: Key.lastPositionX)
        let y = defaults.double(forKey: Key.lastPositionY)
        return CGPoint(x: x, y: y)
    }

    // MARK: - 초기화

    private let defaults = UserDefaults.standard

    init() {
        loadFromDefaults()
    }

    // MARK: - 로드

    private func loadFromDefaults() {
        isLoading = true
        defer { isLoading = false }

        if defaults.object(forKey: Key.spriteScale) != nil {
            spriteScale = defaults.double(forKey: Key.spriteScale)
        }
        if defaults.object(forKey: Key.opacity) != nil {
            opacity = defaults.double(forKey: Key.opacity)
        }
        if defaults.object(forKey: Key.windowLevel) != nil {
            let raw = defaults.integer(forKey: Key.windowLevel)
            windowLevelOption = WindowLevelOption(rawValue: raw) ?? .alwaysOnTop
        }
        if defaults.object(forKey: Key.movementSpeed) != nil {
            movementSpeed = defaults.integer(forKey: Key.movementSpeed)
        }
        if defaults.object(forKey: Key.activityFrequency) != nil {
            activityFrequency = defaults.integer(forKey: Key.activityFrequency)
        }
        if defaults.object(forKey: Key.sleepTimeout) != nil {
            sleepTimeout = defaults.integer(forKey: Key.sleepTimeout)
        }
        if defaults.object(forKey: Key.autoLaunch) != nil {
            autoLaunch = defaults.bool(forKey: Key.autoLaunch)
        }
        if let saved = defaults.string(forKey: Key.restrictedMonitor), !saved.isEmpty {
            restrictedMonitorName = saved
        }
        applyMonitorRestriction()
    }

    // MARK: - 저장

    private func save(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: - 기본값 복원

    func resetToDefaults() {
        spriteScale = Default.spriteScale
        opacity = Default.opacity
        windowLevelOption = .alwaysOnTop
        movementSpeed = Default.movementSpeed
        activityFrequency = Default.activityFrequency
        sleepTimeout = Default.sleepTimeout
        autoLaunch = Default.autoLaunch
        restrictedMonitorName = nil
    }

    // MARK: - 실시간 반영

    /// 모든 오버레이 윈도우에 투명도 적용
    func applyOpacity() {
        NotificationCenter.default.post(name: .settingsOpacityChanged, object: nil)
    }

    /// 모든 오버레이 윈도우에 level 적용
    func applyWindowLevel() {
        NotificationCenter.default.post(name: .settingsWindowLevelChanged, object: nil)
    }

    /// 모니터 제한 설정을 ScreenGeometry에 반영
    func applyMonitorRestriction() {
        ScreenGeometry.shared.restrictedScreenName = restrictedMonitorName
    }

    /// 연결된 모니터 목록 (UI용)
    var availableMonitors: [(name: String, frame: CGRect)] {
        let geo = ScreenGeometry.shared
        return zip(geo.screenNames, geo.screenFrames).map { (name: $0, frame: $1) }
    }

    /// 로그인 시 자동 실행 설정
    private func applyAutoLaunch() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if autoLaunch {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                print("[SettingsManager] 자동 실행 설정 실패: \(error)")
            }
        }
    }
}

// MARK: - 설정 변경 알림

extension Notification.Name {
    static let settingsOpacityChanged = Notification.Name("settingsOpacityChanged")
    static let settingsWindowLevelChanged = Notification.Name("settingsWindowLevelChanged")
}
