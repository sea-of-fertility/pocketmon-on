//
//  PetManager.swift
//  poketmon
//
//  중앙 관리자 싱글턴 — 모든 하위 컴포넌트 소유
//  SwiftUI/AppKit 어디서든 PetManager.shared로 접근
//

import AppKit
import Observation

@Observable
final class PetManager {

    // MARK: - 싱글턴

    static let shared = PetManager()

    // MARK: - 하위 컴포넌트

    let spriteAnimator = SpriteAnimator()
    let stateMachine = PetStateMachine()
    let gameLoop = GameLoop()
    let pokemonDataManager = PokemonDataManager()
    let settingsManager = SettingsManager.shared

    // MARK: - 상태

    /// 현재 포켓몬 ID
    private(set) var currentPokemonID: Int = 25

    /// 스프라이트 배율 (화면 높이 / 450 × 사용자 배율)
    var spriteScale: CGFloat {
        let baseScale = ScreenGeometry.shared.primaryScreenHeight / 450.0
        return baseScale * settingsManager.spriteScaleMultiplier
    }

    /// 일시정지 여부
    private(set) var isPaused = false

    /// 위치 저장 쓰로틀링용 타이머
    private var lastPositionSaveTime: Date = Date()

    /// Sleep 상태에서 게임 루프 정지 여부 (유저 일시정지와 독립)
    private var isGameLoopPausedForSleep = false

    // MARK: - 초기화

    private init() {
        setupGameLoop()

        // 저장된 포켓몬 로드 (없으면 기본 25 = 피카츄)
        let savedID = settingsManager.savedPokemonID
        loadPokemon(id: savedID)

        // 저장된 위치 복원 (화면 내 유효한 경우만)
        if let savedPosition = settingsManager.loadLastPosition() {
            let geo = ScreenGeometry.shared
            if geo.isOnScreen(savedPosition, margin: 20) {
                stateMachine.position = savedPosition
            }
        }
    }

    // MARK: - 포켓몬 로드

    /// 포켓몬 교체
    func loadPokemon(id: Int) {
        currentPokemonID = id
        spriteAnimator.load(pokemonID: id)
        stateMachine.transition(to: .idle)

        // 초기 위치 설정 (주 모니터 중앙 하단 1/3)
        let primaryFrame = ScreenGeometry.shared.screenFrames.first ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        stateMachine.position = CGPoint(
            x: primaryFrame.midX,
            y: primaryFrame.minY + primaryFrame.height * 0.3
        )
    }

    /// 포켓몬 교체 + 설정 저장 (현재 위치 유지, 선택기에서 확정 시 호출)
    func changePokemon(to id: Int) {
        previewPokemon(id)
        settingsManager.savedPokemonID = id
    }

    /// 포켓몬 미리보기 — 화면만 바꾸고 설정에는 저장하지 않는다
    ///
    /// 선택기에서 초상화를 클릭할 때 사용한다. 저장은 Select(확정) 시점에만
    /// 일어나므로, 취소하거나 창을 닫으면 저장된 포켓몬으로 되돌릴 수 있다.
    /// 위치는 유지하고 애니메이션 상태만 Idle로 초기화한다.
    func previewPokemon(_ id: Int) {
        guard id != currentPokemonID else { return }
        resumeGameLoopFromSleep()
        currentPokemonID = id
        spriteAnimator.loadWithTransition(pokemonID: id)
        stateMachine.resetToIdle()
    }

    // MARK: - 게임 루프 연결

    private func setupGameLoop() {
        gameLoop.onUpdate = { [weak self] in
            self?.tick()
        }
        gameLoop.start()
    }

    /// 매 프레임 호출
    private func tick() {
        let geo = ScreenGeometry.shared
        let screenBounds = geo.unionFrame

        // 상태 머신 업데이트 — 전환 필요 시 애니메이션 변경
        if let newAnim = stateMachine.update(screenBounds: screenBounds) {
            spriteAnimator.switchAnimation(to: newAnim)

            // Run 상태면 속도 배율 1.5, 아니면 1.0
            spriteAnimator.speedMultiplier = (stateMachine.currentState == .run) ? 1.5 : 1.0

            // 자동 수면 전환 시 게임 루프 정지 (이동 불필요)
            if stateMachine.currentState == .sleep {
                pauseGameLoopForSleep()
                return
            }
        }

        // 방향 동기화
        spriteAnimator.setDirection(stateMachine.currentDirection)

        // 30초마다 위치 저장 (강제 종료 대비)
        if Date().timeIntervalSince(lastPositionSaveTime) >= 30 {
            savePosition()
        }
    }

    // MARK: - 위치 저장

    /// 현재 위치를 UserDefaults에 저장
    func savePosition() {
        settingsManager.saveLastPosition(stateMachine.position)
        lastPositionSaveTime = Date()
    }

    // MARK: - Sleep 시 게임 루프 제어

    /// Sleep 진입 시 게임 루프 정지 + 위치 저장
    private func pauseGameLoopForSleep() {
        isGameLoopPausedForSleep = true
        gameLoop.pause()
        savePosition()
    }

    /// Sleep 탈출 시 게임 루프 재개 (유저 일시정지 상태면 재개하지 않음)
    private func resumeGameLoopFromSleep() {
        guard isGameLoopPausedForSleep else { return }
        isGameLoopPausedForSleep = false
        if !isPaused {
            gameLoop.resume()
        }
    }

    // MARK: - 외부 제어

    /// 일시정지 토글
    func togglePause() {
        isPaused.toggle()
        if isPaused {
            gameLoop.pause()
            spriteAnimator.pause()
        } else {
            // Sleep으로 게임 루프가 정지된 상태면 재개하지 않음
            if !isGameLoopPausedForSleep {
                gameLoop.resume()
            }
            spriteAnimator.resume()
        }
    }

    /// 강제 Sleep
    func sleep() {
        stateMachine.sleep()
        spriteAnimator.switchAnimation(to: .sleep)
        pauseGameLoopForSleep()
    }

    /// 깨우기
    func wake() {
        stateMachine.wake()
        spriteAnimator.switchAnimation(to: .idle)
        resumeGameLoopFromSleep()
    }

    /// 강제 Run (10초)
    func run() {
        resumeGameLoopFromSleep()
        stateMachine.run()
        spriteAnimator.switchAnimation(to: .walk)
        spriteAnimator.speedMultiplier = 1.5
    }

    /// Run → Walk 전환 (달리기 취소)
    func walk() {
        guard stateMachine.currentState == .run else { return }
        stateMachine.transition(to: .walk)
        spriteAnimator.speedMultiplier = 1.0
    }

    /// 모니터 해제 시 포켓몬이 화면 밖에 있으면 가장 가까운 모니터로 이동
    func relocateIfOffScreen() {
        let geo = ScreenGeometry.shared
        let pos = stateMachine.position
        if !geo.isOnScreen(pos, margin: 20) {
            stateMachine.position = geo.clampToNearestScreen(pos, margin: 40)
        }
    }

    /// 드래그 시작 — Dragged 상태 전환 + Idle 프레임 고정
    func startDrag() {
        stateMachine.startDrag()
        spriteAnimator.switchAnimation(to: .idle)
    }

    /// 드래그 종료 — 드래그 전 상태로 복원
    func endDrag() {
        stateMachine.endDrag()
        let restored = stateMachine.currentState
        switch restored {
        case .sleep:
            spriteAnimator.switchAnimation(to: .sleep)
            savePosition()
            pauseGameLoopForSleep()
        case .walk, .run:
            spriteAnimator.switchAnimation(to: .walk)
            spriteAnimator.speedMultiplier = (restored == .run) ? 1.5 : 1.0
            savePosition()
        default:
            spriteAnimator.switchAnimation(to: .idle)
            savePosition()
        }
    }

    /// 클릭 반응
    func react() {
        let previousState = stateMachine.currentState
        stateMachine.react()

        if previousState == .sleep {
            resumeGameLoopFromSleep()
            spriteAnimator.switchAnimation(to: .idle)
        } else if stateMachine.currentState == .reaction {
            // 사용 가능한 Reaction 애니메이션 중 랜덤 선택
            if let reactionAnim = spriteAnimator.availableReactions.randomElement() {
                spriteAnimator.playOnce(reactionAnim) { [weak self] in
                    self?.stateMachine.reactionFinished()
                    self?.spriteAnimator.switchAnimation(to: .idle)
                }
            } else {
                // Reaction 애니메이션 없으면 바로 Idle
                stateMachine.reactionFinished()
                spriteAnimator.switchAnimation(to: .idle)
            }
        }
    }
}
