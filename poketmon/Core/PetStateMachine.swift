//
//  PetStateMachine.swift
//  poketmon
//
//  6개 상태(Idle, Walk, Run, Sleep, Reaction, Dragged) 전환 로직
//  상태별 진입 시간 추적, 전환 조건 판단
//

import Foundation
import Observation

// MARK: - 포켓몬 상태

enum PetState: String {
    case idle, walk, run, sleep, reaction, dragged

    /// 상태 표시 텍스트 (시스템 언어 반영)
    var displayName: String {
        switch self {
        case .idle: String(localized: "Idle")
        case .walk: String(localized: "Walking")
        case .run: String(localized: "Running")
        case .sleep: String(localized: "Sleeping")
        case .reaction: String(localized: "Reacting")
        case .dragged: String(localized: "Dragging")
        }
    }
}

// MARK: - 상태 머신

@Observable
final class PetStateMachine {

    /// 현재 상태
    private(set) var currentState: PetState = .idle

    /// 현재 이동 방향
    private(set) var currentDirection: Direction = .down

    /// 포켓몬 위치 (macOS 좌표계)
    var position: CGPoint = .zero

    /// 현재 상태 진입 시각
    private var stateEnteredAt: Date = Date()

    /// 현재 상태에서 경과한 시간(초)
    var elapsedInCurrentState: TimeInterval {
        Date().timeIntervalSince(stateEnteredAt)
    }

    /// Run 지속 시간 (초)
    var runDuration: Double = 10.0

    // MARK: - 내부 상태

    /// 현재 전환까지 남은 시간
    private var transitionTime: Double = 0

    /// 랜덤 목표점
    private(set) var targetPoint: CGPoint? = nil

    /// 목표점 설정 시각 (도달 제한 시간 기준)
    private var targetSetAt: Date = Date()

    /// 현재 목표점의 도달 제한 시간(초) — 거리/속도 기반으로 동적 계산
    private var targetDeadline: Double = 0

    /// 드래그 진입 전 상태 (드래그 종료 시 복원용)
    private var stateBeforeDrag: PetState = .idle

    /// 마지막 사용자 상호작용 시각 (수면 타이머 기준 — Idle↔Walk 자율 순환과 무관)
    private var lastInteractionAt: Date = Date()

    // MARK: - 상태 전환

    /// 상태를 변경하고 진입 시각 갱신
    func transition(to state: PetState) {
        guard currentState != state else { return }
        currentState = state
        stateEnteredAt = Date()

        let settings = SettingsManager.shared
        switch state {
        case .idle:
            transitionTime = Double.random(in: settings.idleToWalkRange)
            // 목표점 유지 — 여러 Walk 사이클에 걸쳐 같은 방향으로 이동
        case .walk:
            transitionTime = Double.random(in: settings.walkToIdleRange)
        case .run:
            transitionTime = runDuration
        case .sleep:
            transitionTime = 0
            // 수면은 무기한 상태 — 깨어나면 주변을 새로 살피도록 목표점을 버린다
            clearTarget()
        case .reaction, .dragged:
            transitionTime = 0
        }
    }

    /// 매 프레임 호출 — 전환 조건 확인 + 위치 업데이트
    /// - Parameter screenBounds: 화면 경계 (포켓몬 이동 범위)
    /// - Returns: 애니메이션 전환이 필요하면 새 AnimationType 반환
    func update(screenBounds: CGRect) -> AnimationType? {
        let elapsed = elapsedInCurrentState

        switch currentState {
        case .idle:
            // Idle → Sleep (장시간 비활동) — "잠들지 않음" 설정이면 건너뜀
            let settings = SettingsManager.shared
            if !settings.isSleepDisabled,
               Date().timeIntervalSince(lastInteractionAt) >= settings.sleepTimeoutSeconds {
                transition(to: .sleep)
                return .sleep
            }
            // Idle → Walk (랜덤 타이밍)
            if elapsed >= transitionTime {
                transition(to: .walk)
                // 기존 목표점이 없거나 제한 시간이 지났으면 새로 생성
                if targetPoint == nil || isTargetExpired {
                    setTarget(randomTarget(in: screenBounds))
                }
                updateDirection()
                return .walk
            }
            return nil

        case .walk:
            // Walk → Idle (랜덤 타이밍)
            if elapsed >= transitionTime {
                transition(to: .idle)
                return .idle
            }
            // 목표점 도달 시 새 목표점
            moveTowardTarget(speed: SettingsManager.shared.walkSpeedValue, screenBounds: screenBounds)
            return nil

        case .run:
            // Run → Walk (시간 경과)
            if elapsed >= transitionTime {
                transition(to: .walk)
                setTarget(randomTarget(in: screenBounds))
                updateDirection()
                return .walk
            }
            moveTowardTarget(speed: SettingsManager.shared.runSpeedValue, screenBounds: screenBounds)
            return nil

        case .sleep, .reaction, .dragged:
            return nil
        }
    }

    // MARK: - 외부 트리거

    /// 클릭 → Reaction (Sleep이면 깨우기)
    func react() {
        lastInteractionAt = Date()
        if currentState == .sleep {
            transition(to: .idle)
        } else if currentState != .dragged && currentState != .reaction {
            transition(to: .reaction)
        }
    }

    /// 강제 Sleep
    func sleep() {
        if currentState != .dragged {
            transition(to: .sleep)
        }
    }

    /// 깨우기 (Sleep → Idle)
    func wake() {
        lastInteractionAt = Date()
        if currentState == .sleep {
            transition(to: .idle)
        }
    }

    /// 강제 Run (10초 후 Walk 복귀)
    func run() {
        lastInteractionAt = Date()
        if currentState != .dragged {
            transition(to: .run)
            // 기존 목표점을 유지하되 Run 속도 기준으로 제한 시간 재계산
            setTarget(targetPoint ?? ScreenGeometry.shared.randomTarget(margin: 40))
            updateDirection()
        }
    }

    /// 드래그 시작 — 현재 상태를 기억
    func startDrag() {
        lastInteractionAt = Date()
        stateBeforeDrag = currentState
        transition(to: .dragged)
    }

    /// 드래그 종료 → 드래그 전 상태로 복원
    func endDrag() {
        transition(to: stateBeforeDrag)
        // 드래그로 위치가 바뀌었으므로 새 위치 기준으로 제한 시간 재계산
        restartTargetDeadline()
    }

    /// Reaction 완료 → Idle
    func reactionFinished() {
        if currentState == .reaction {
            transition(to: .idle)
        }
    }

    /// 상태를 Idle로 강제 리셋 (포켓몬 교체 시 — 타이머 재설정)
    func resetToIdle() {
        lastInteractionAt = Date()
        currentState = .idle
        stateEnteredAt = Date()
        transitionTime = Double.random(in: SettingsManager.shared.idleToWalkRange)
        clearTarget()
    }

    // MARK: - 목표점 관리

    /// 목표점 설정 + 도달 제한 시간 계산 (targetPoint는 항상 이 메서드로만 변경)
    ///
    /// 제한 시간 = min((남은 거리 / 현재 속도) × 여유 배수 + 하한, 상한)
    /// - 여유 배수: 활동 빈도에서 산출 (Idle로 쉬는 시간을 감수)
    /// - 상한: 수면 타임아웃의 절반 (잠들기 전 최소 2회는 목표점을 재시도)
    private func setTarget(_ point: CGPoint) {
        targetPoint = point
        targetSetAt = Date()

        let dx = point.x - position.x
        let dy = point.y - position.y
        let distance = sqrt(dx * dx + dy * dy)

        // 현재 상태의 이동 속도(px/frame) → px/sec
        let settings = SettingsManager.shared
        let speed = (currentState == .run) ? settings.runSpeedValue : settings.walkSpeedValue
        let pixelsPerSecond = max(speed * Self.framesPerSecond, 1)

        let travelTime = Double(distance / pixelsPerSecond)
        let deadline = travelTime * Self.deadlineSlackMultiplier + Self.deadlineMinimum
        targetDeadline = min(deadline, Self.deadlineCap)
    }

    /// 제한 시간 상한 (초) — 수면 타임아웃의 절반, 단 절대 상한 이내
    ///
    /// 상한이 없으면 조용한 설정(활동 빈도 1 + 느린 속도)에서 제한 시간이
    /// 수면 타임아웃보다 길어져, 목표점이 만료되기 전에 잠들어 제한 시간이
    /// 무의미해진다. 절반으로 묶어 어떤 설정 조합에서도 최소 2회는 작동하게 한다.
    ///
    /// 수면 타임아웃이 길거나(30분, 1시간) 잠들지 않음(무한)이면 절반 규칙만으로는
    /// 상한이 사라지므로, 교착 방지가 유지되도록 절대 상한을 함께 적용한다.
    private static var deadlineCap: Double {
        let half = SettingsManager.shared.sleepTimeoutSeconds * 0.5
        return max(min(half, deadlineAbsoluteCap), deadlineMinimum)
    }

    /// 제한 시간 절대 상한 (초) — 수면 설정과 무관하게 목표점을 재시도하는 주기
    private static let deadlineAbsoluteCap: Double = 120.0

    /// 예상 이동 시간에 곱하는 여유 배수
    ///
    /// Walk↔Idle 순환에서 걷는 시간의 비율(walk / (idle + walk))의 역수.
    /// 여기에 랜덤 편차와 경계 반사로 인한 우회를 감수하는 1.3배를 더 곱한다.
    /// 활동 빈도가 낮으면 쉬는 시간이 길어 배수가 커진다(빈도 1: 약 4.6배, 빈도 5: 약 1.4배).
    /// 배수가 커져 제한 시간이 과도해지는 것은 deadlineCap이 막는다.
    private static var deadlineSlackMultiplier: Double {
        let settings = SettingsManager.shared
        let idleMid = (settings.idleToWalkRange.lowerBound + settings.idleToWalkRange.upperBound) / 2
        let walkMid = (settings.walkToIdleRange.lowerBound + settings.walkToIdleRange.upperBound) / 2
        let walkRatio = walkMid / (idleMid + walkMid)
        return (1.0 / max(walkRatio, 0.1)) * 1.3
    }

    /// 목표점 폐기 — 다음 Walk 진입 시 새로 생성된다
    private func clearTarget() {
        targetPoint = nil
        targetDeadline = 0
    }

    /// 기존 목표점을 유지한 채 제한 시간만 다시 시작
    ///
    /// 드래그처럼 이동이 멈춘 채 위치가 바뀐 뒤, 남은 거리 기준으로
    /// 제한 시간을 다시 계산해 즉시 만료되는 것을 막는다.
    private func restartTargetDeadline() {
        guard let target = targetPoint else { return }
        setTarget(target)
    }

    /// 목표점 도달 제한 시간 초과 여부
    private var isTargetExpired: Bool {
        targetPoint != nil && Date().timeIntervalSince(targetSetAt) >= targetDeadline
    }

    /// 게임 루프 주기 (GameLoop와 동일)
    private static let framesPerSecond: CGFloat = 30.0

    /// 제한 시간 하한 (초) — 가까운 목표점에서 즉시 만료되는 것 방지
    private static let deadlineMinimum: Double = 5.0

    // MARK: - 이동 로직

    /// 목표점을 향해 이동 + 경계 반사
    private func moveTowardTarget(speed: CGFloat, screenBounds: CGRect) {
        guard let target = targetPoint else {
            setTarget(randomTarget(in: screenBounds))
            updateDirection()
            return
        }

        // 제한 시간 내 도달 실패 — 새 목표점으로 교체
        if isTargetExpired {
            setTarget(randomTarget(in: screenBounds))
            updateDirection()
            return
        }

        let dx = target.x - position.x
        let dy = target.y - position.y
        let distance = sqrt(dx * dx + dy * dy)

        // 목표점 도달
        if distance < speed * 2 {
            setTarget(randomTarget(in: screenBounds))
            updateDirection()
            return
        }

        // 이동
        let moveX = (dx / distance) * speed
        let moveY = (dy / distance) * speed
        position.x += moveX
        position.y += moveY

        // 방향 갱신
        currentDirection = Direction.from(dx: moveX, dy: moveY)

        // 스프라이트 크기 기반 경계 반사 — 몸이 화면 밖으로 나가지 않도록
        let pet = PetManager.shared
        let scale = pet.spriteScale
        let animator = pet.spriteAnimator
        let halfW = animator.currentFrameSize.width * scale / 2
        let h = animator.currentFrameSize.height * scale
        let walkHalfH = animator.walkFrameSize.height * scale / 2

        let geo = ScreenGeometry.shared
        var (clampedPos, bounced) = geo.clampSpritePosition(
            position, halfWidth: halfW, height: h, walkHalfHeight: walkHalfH)

        // dead zone 보정 — 실제 모니터 밖(빈 영역)에 빠지면 가장 가까운 모니터로 이동
        if !geo.isOnScreen(clampedPos) {
            clampedPos = geo.clampToNearestScreen(clampedPos, margin: max(halfW, walkHalfH))
            bounced = true
        }

        position = clampedPos

        if bounced {
            setTarget(geo.randomTarget(margin: 40))
            updateDirection()
        }
    }

    /// 실제 모니터 위의 랜덤 목표점 생성
    private func randomTarget(in bounds: CGRect) -> CGPoint {
        return ScreenGeometry.shared.randomTarget(margin: 40)
    }

    /// 목표점 방향으로 currentDirection 갱신
    private func updateDirection() {
        guard let target = targetPoint else { return }
        let dx = target.x - position.x
        let dy = target.y - position.y
        currentDirection = Direction.from(dx: dx, dy: dy)
    }
}
