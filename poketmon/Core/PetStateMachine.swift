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
        case .sleep, .reaction, .dragged:
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
            // Idle → Sleep (장시간 비활동)
            if Date().timeIntervalSince(lastInteractionAt) >= SettingsManager.shared.sleepTimeoutSeconds {
                transition(to: .sleep)
                return .sleep
            }
            // Idle → Walk (랜덤 타이밍)
            if elapsed >= transitionTime {
                transition(to: .walk)
                // 기존 목표점이 없을 때만 새로 생성
                if targetPoint == nil {
                    targetPoint = randomTarget(in: screenBounds)
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
                targetPoint = randomTarget(in: screenBounds)
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
            targetPoint = targetPoint ?? ScreenGeometry.shared.randomTarget(margin: 40)
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
        targetPoint = nil
    }

    // MARK: - 이동 로직

    /// 목표점을 향해 이동 + 경계 반사
    private func moveTowardTarget(speed: CGFloat, screenBounds: CGRect) {
        guard let target = targetPoint else {
            targetPoint = randomTarget(in: screenBounds)
            updateDirection()
            return
        }

        let dx = target.x - position.x
        let dy = target.y - position.y
        let distance = sqrt(dx * dx + dy * dy)

        // 목표점 도달
        if distance < speed * 2 {
            targetPoint = randomTarget(in: screenBounds)
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
            targetPoint = geo.randomTarget(margin: 40)
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
