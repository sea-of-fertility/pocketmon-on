//
//  PetView.swift
//  poketmon
//
//  투명 윈도우의 콘텐츠 뷰 — 포켓몬 스프라이트 렌더링 + 클릭 통과
//  PetManager.shared에서 위치/프레임 정보를 가져와 렌더링
//  각 모니터마다 독립 PetView가 존재하며, 포켓몬이 해당 모니터 위에 있을 때만 렌더링
//

import AppKit

final class PetView: NSView {

    /// 이 뷰가 담당하는 모니터의 글로벌 frame
    var screenFrame: CGRect = .zero

    /// 드래그 중 여부 (드래그 중에는 ignoresMouseEvents 유지)
    private var isDragging = false

    /// 드래그 시작 시 마우스와 포켓몬 위치의 오프셋 (스냅 방지)
    private var dragOffset: CGPoint = .zero

    /// mouseDown 시 마우스 글로벌 위치 (드래그 판정용)
    private var mouseDownLocation: CGPoint = .zero

    /// 드래그 판정 임계값 (px) — 미세한 손떨림으로 드래그 오작동 방지
    private let dragThreshold: CGFloat = 3.0

    /// 스프라이트 배율 — PetManager에서 통합 관리
    private var spriteScale: CGFloat {
        PetManager.shared.spriteScale
    }

    /// 포켓몬 스프라이트 영역 (글로벌 좌표 → 이 윈도우의 로컬 좌표 변환)
    /// 원본 프레임 크기 × spriteScale로 렌더링. 하단(발) 고정.
    private var petRect: CGRect {
        let animator = PetManager.shared.spriteAnimator
        let frameSize = animator.currentFrameSize
        let scale = spriteScale
        let w = frameSize.width * scale
        let h = frameSize.height * scale
        let walkH = animator.walkFrameSize.height * scale
        let pos = PetManager.shared.stateMachine.position
        let localX = pos.x - screenFrame.origin.x
        let localY = pos.y - screenFrame.origin.y
        return CGRect(
            x: localX - w / 2,
            y: localY - walkH / 2,
            width: w,
            height: h
        )
    }

    // MARK: - 초기화

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupRendering()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupRendering()
    }

    private func setupRendering() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.ignoresMouseEvents = true
        }

        // 30fps 뷰 갱신 + 마우스 위치 체크
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            // 전환 진행도 업데이트 (draw 밖에서 처리 — @Observable 변경이 display 루프 유발 방지)
            PetManager.shared.spriteAnimator.updateTransition()
            self?.needsDisplay = true
            self?.updateMousePassthrough()
        }
    }

    // MARK: - 마우스 통과 제어

    private func updateMousePassthrough() {
        guard let window = self.window else { return }
        let pos = PetManager.shared.stateMachine.position
        // 포켓몬이 이 모니터 위에 없으면 항상 클릭 통과
        guard screenFrame.contains(pos) else {
            window.ignoresMouseEvents = true
            return
        }
        let screenLocation = NSEvent.mouseLocation
        let windowLocation = window.convertPoint(fromScreen: screenLocation)
        let isOverPet = petRect.contains(windowLocation)
        window.ignoresMouseEvents = !isOverPet && !isDragging
    }

    // MARK: - 렌더링

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill()

        let pos = PetManager.shared.stateMachine.position
        let animator = PetManager.shared.spriteAnimator
        let scale = spriteScale

        let walkSize = animator.walkFrameSize
        let walkH = walkSize.height * scale
        let walkW = walkSize.width * scale

        // 포켓몬이 이 모니터 근처에 없으면 그리지 않음
        let margin = max(walkW, walkH) * 1.5
        let expandedFrame = screenFrame.insetBy(dx: -margin, dy: -margin)
        guard expandedFrame.contains(pos) else { return }

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none

        // 전환 중: 이전 프레임 페이드 아웃
        if animator.isTransitioning, let prevFrame = animator.previousFrame {
            let prevSize = animator.previousFrameSize
            let prevWalkH = animator.previousWalkFrameSize.height * scale
            let prevWalkW = animator.previousWalkFrameSize.width * scale
            let pw = prevSize.width * scale
            let ph = prevSize.height * scale
            let localX = pos.x - screenFrame.origin.x
            let localY = pos.y - screenFrame.origin.y
            let prevRect = CGRect(
                x: localX - pw / 2,
                y: localY - prevWalkH / 2,
                width: pw, height: ph
            )
            drawSprite(context: context, frame: prevFrame, shadow: animator.previousShadowFrame,
                       rect: prevRect, walkW: prevWalkW, walkH: prevWalkH,
                       alpha: 1.0 - animator.transitionProgress)
        }

        // 현재 프레임 렌더링
        let currentAlpha = animator.isTransitioning ? animator.transitionProgress : 1.0
        drawSprite(context: context, frame: animator.currentFrame, shadow: animator.currentShadowFrame,
                   rect: petRect, walkW: walkW, walkH: walkH, alpha: currentAlpha)
    }

    /// 스프라이트 + 그림자 렌더링 (알파 적용)
    private func drawSprite(
        context: CGContext, frame: CGImage?, shadow: CGImage?,
        rect: CGRect, walkW: CGFloat, walkH: CGFloat, alpha: CGFloat
    ) {
        // Shadow
        if let shadow = shadow,
           let alphaOnly = shadow.copy(colorSpace: CGColorSpaceCreateDeviceGray()) {
            let shadowWidth = walkW * 0.8
            let shadowRect = CGRect(
                x: rect.midX - shadowWidth / 2,
                y: rect.minY - walkH * 0.05,
                width: shadowWidth,
                height: walkH * 0.15
            )
            context.saveGState()
            context.clip(to: shadowRect, mask: alphaOnly)
            context.setFillColor(CGColor(gray: 0, alpha: 0.25 * alpha))
            context.fill(shadowRect)
            context.restoreGState()
        }

        // Anim
        guard let frame = frame else { return }
        if alpha < 1.0 {
            context.saveGState()
            context.setAlpha(alpha)
            context.draw(frame, in: rect)
            context.restoreGState()
        } else {
            context.draw(frame, in: rect)
        }
    }

    // MARK: - 마우스 이벤트

    /// 비활성 윈도우에서도 첫 클릭이 바로 이벤트로 전달되도록
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let globalLocation = NSEvent.mouseLocation
        mouseDownLocation = globalLocation

        // 드래그 오프셋 계산 — 포켓몬 중심과 클릭 위치의 차이를 기억
        let petPos = PetManager.shared.stateMachine.position
        dragOffset = CGPoint(
            x: petPos.x - globalLocation.x,
            y: petPos.y - globalLocation.y
        )
    }

    override func mouseDragged(with event: NSEvent) {
        let globalLocation = NSEvent.mouseLocation

        if !isDragging {
            // 드래그 임계값 확인 — 미세한 움직임은 무시
            let dx = globalLocation.x - mouseDownLocation.x
            let dy = globalLocation.y - mouseDownLocation.y
            guard sqrt(dx * dx + dy * dy) >= dragThreshold else { return }

            // 드래그 시작
            isDragging = true
            PetManager.shared.startDrag()
        }

        // 글로벌 좌표로 포켓몬 위치 계산
        let newPos = CGPoint(
            x: globalLocation.x + dragOffset.x,
            y: globalLocation.y + dragOffset.y
        )

        // 스프라이트가 화면 밖으로 나가지 않도록 clamp
        let pet = PetManager.shared
        let scale = pet.spriteScale
        let animator = pet.spriteAnimator
        let halfW = animator.currentFrameSize.width * scale / 2
        let h = animator.currentFrameSize.height * scale
        let walkHalfH = animator.walkFrameSize.height * scale / 2

        let (clamped, _) = ScreenGeometry.shared.clampSpritePosition(
            newPos, halfWidth: halfW, height: h, walkHalfHeight: walkHalfH, ignoreRestriction: true)

        pet.stateMachine.position = clamped
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            // 드래그 종료 → Idle
            isDragging = false
            PetManager.shared.endDrag()
            return
        }

        // 클릭 (드래그가 아닌 경우) — 즉시 Reaction 실행
        PetManager.shared.react()
    }

    override func rightMouseDown(with event: NSEvent) {
        let pet = PetManager.shared
        let data = pet.pokemonDataManager.pokemon(id: pet.currentPokemonID)
        let isSleeping = pet.stateMachine.currentState == .sleep

        let menu = NSMenu()

        // 헤더 (비활성)
        let header = NSMenuItem(
            title: "\(data?.name ?? "???") \(data?.displayNumber ?? "")",
            action: nil, keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        // 포켓몬 변경
        let changeItem = NSMenuItem(title: "포켓몬 변경...",
                                    action: #selector(menuChangePokemon), keyEquivalent: "")
        changeItem.target = self
        menu.addItem(changeItem)

        // 설정
        let settingsItem = NSMenuItem(title: "설정...",
                                      action: #selector(menuOpenSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // 재우기 / 깨우기
        let sleepItem = NSMenuItem(title: isSleeping ? "깨우기" : "재우기",
                                   action: #selector(menuToggleSleep), keyEquivalent: "")
        sleepItem.target = self
        menu.addItem(sleepItem)

        // 뛰게 하기 / 걷게 하기
        let isRunning = pet.stateMachine.currentState == .run
        let runItem = NSMenuItem(title: isRunning ? "걷게 하기" : "뛰게 하기",
                                 action: #selector(menuToggleRun), keyEquivalent: "")
        runItem.target = self
        menu.addItem(runItem)

        menu.addItem(.separator())

        // 종료
        let quitItem = NSMenuItem(title: "종료",
                                  action: #selector(menuQuit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - 컨텍스트 메뉴 액션

    @objc private func menuChangePokemon() {
        PokemonSelectorWindowController.shared.open()
    }

    @objc private func menuOpenSettings() {
        SettingsWindowController.shared.open()
    }

    @objc private func menuToggleSleep() {
        let pet = PetManager.shared
        if pet.stateMachine.currentState == .sleep {
            pet.wake()
        } else {
            pet.sleep()
        }
    }

    @objc private func menuToggleRun() {
        let pet = PetManager.shared
        if pet.stateMachine.currentState == .run {
            pet.walk()
        } else {
            pet.run()
        }
    }

    @objc private func menuQuit() {
        NSApplication.shared.terminate(nil)
    }
}
