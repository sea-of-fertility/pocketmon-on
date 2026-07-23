# 포켓몬 데스크톱 펫 - 개발 계획

> 각 단계는 이전 단계의 결과물에 의존한다. 순서대로 진행.
> 코드 구현 세부사항은 SCREEN_SPEC.md, SPRITE_INTEGRATION_PLAN.md 참고.

## 아키텍처: PetManager (중앙 관리자)

> **✅ 결정**: 싱글턴 PetManager가 모든 컴포넌트를 소유. SwiftUI/AppKit 어디서든 `PetManager.shared`로 접근.
> **✅ 결정**: 모든 @Observable 매크로 사용 (macOS 15.5+ Observation 프레임워크). 중첩 객체 변경 자동 추적.
> **✅ 결정**: 게임 루프는 메인 큐에서 실행 (30fps 위치 계산은 가벼우므로 스레드 안전성 문제 회피).

```
PetManager (@Observable, 싱글턴)
  ├─ spriteAnimator    (@Observable) — 프레임 제공, 애니메이션 전환
  ├─ stateMachine      (@Observable) — 6개 상태 전환, 위치/방향
  ├─ gameLoop          — DispatchSourceTimer, 위치 업데이트
  ├─ settingsManager   (@Observable) — UserDefaults 저장/로드
  └─ pokemonDataManager — 649종 포켓몬 목록
```

접근 예시:
- 메뉴바 "재우기" (SwiftUI) → `PetManager.shared.stateMachine.sleep()`
- 포켓몬 클릭 (AppKit NSView) → `PetManager.shared.stateMachine.react()`
- 설정 속도 변경 (SwiftUI) → `PetManager.shared.settingsManager.speed = newValue`
- NSView 렌더링 → `PetManager.shared.spriteAnimator.currentFrame`

PetManager는 Phase 2 (Step 2-1)에서 AppDelegate와 함께 생성. 이후 Phase에서 하위 컴포넌트를 점진적으로 추가.

---

## Phase 1. 프로젝트 기반 & 스프라이트 시스템
모든 시각적 작업의 토대. 스프라이트 다운로드 → 파싱 → 프레임 추출 → 애니메이션 재생까지.

### Step 1-0. 다운로드 스크립트 수정 (사전 작업)
- download_sprites.sh의 ANIMATIONS 배열에 "Eat", "Hop", "Hurt" 추가
- 수정 후 6종 애니메이션: Walk, Idle, Sleep, Eat, Hop, Hurt

### Step 1-1. 스프라이트 다운로드
- `download_sprites.sh` 실행 → `./poketmon/Resources/Sprites/{ID:04d}/`에 633종 저장
- 포켓몬당 13파일 (AnimData.xml + 6종 Anim.png + 6종 Shadow.png)
- 다운로드 후 Xcode 프로젝트에 리소스 등록 (Sprites 폴더 + pokemon_data.json)

> **✅ 결정**: 스프라이트를 앱 번들에 전부 포함 (20~30MB)

### Step 1-2. AnimData.xml 파서
- `poketmon/Models/AnimDataParser.swift`
- Foundation XMLParser로 ShadowSize + 각 애니메이션의 프레임 크기, 프레임 수, Duration 배열 추출
- XML 구조는 SPRITE_INTEGRATION_PLAN.md 섹션 3 참고

### Step 1-3. 스프라이트 프레임 추출기
- `poketmon/Models/SpriteSheet.swift`
- 스프라이트 시트 PNG에서 CGImage.cropping으로 개별 프레임 추출
- 8방향 × N프레임 = 2차원 배열로 반환
- 8방향 Direction enum도 이 파일 또는 별도 파일에 정의
- 추출 공식은 SPRITE_INTEGRATION_PLAN.md 섹션 3 참고

### Step 1-4. SpriteAnimator
- `poketmon/Models/SpriteAnimator.swift`
- AnimDataParser + SpriteSheet를 결합하여 애니메이션 재생
- 포켓몬 ID를 받아 로드 → 애니메이션 종류("Walk"/"Idle"/"Sleep"/"Eat"/"Hop"/"Hurt") 전환 → 방향 전환 → 현재 Anim 프레임 + Shadow 프레임 동시 제공
- Eat/Hop/Hurt는 일부 포켓몬에 파일이 없을 수 있음. 로드 시 존재 여부 확인하여 사용 가능한 Reaction 애니메이션 목록 제공. 없으면 Reaction 상태 진입하지 않고 Idle 유지
- Duration 기반 타이머로 프레임 자동 순환
- @Observable로 구현하여 SwiftUI 바인딩 대비 (PetManager.shared.spriteAnimator로 접근)

> **✅ 결정**: Shadow PNG 렌더링 사용. Anim 아래에 Shadow를 겹쳐 그린다.

### Step 1-5. PokemonDataManager
- `poketmon/Models/PokemonDataManager.swift`
- pokemon_data.json을 Codable로 디코딩하여 포켓몬 목록 제공
- 누락 16종은 스프라이트 폴더 존재 여부로 판별하여 사용 불가 표시

### Phase 1 생성 파일
- `poketmon/Models/AnimDataParser.swift`
- `poketmon/Models/SpriteSheet.swift` (Direction enum 포함)
- `poketmon/Models/SpriteAnimator.swift`
- `poketmon/Models/PokemonDataManager.swift`

---

## Phase 2. 투명 윈도우 & 포켓몬 렌더링
borderless 투명 NSWindow 생성, 포켓몬 스프라이트를 화면 위에 표시.
hitTest 오버라이드로 클릭 통과 구현. 앱 구조를 SwiftUI → AppKit 하이브리드로 전환.

> **✅ 결정**: SwiftUI + AppKit 하이브리드. 투명 윈도우/메뉴바 등 AppKit 필수 부분만 AppKit, 나머지는 SwiftUI.
> **✅ 결정**: Dock 아이콘 숨김 (Info.plist에 LSUIElement = true). 메뉴바 전용 앱.
> **✅ 결정**: 모든 Space에 포켓몬 표시 (collectionBehavior에 .canJoinAllSpaces).

### Step 2-1. 앱 구조 전환
- 기본 SwiftUI WindowGroup을 MenuBarExtra 플레이스홀더로 교체 (아이콘만 표시, 드롭다운 내용은 Phase 5에서 완성)
- @NSApplicationDelegateAdaptor로 AppDelegate를 SwiftUI 앱에 연결
- AppDelegate에서 투명 NSWindow 생성 및 관리
- Info.plist에 LSUIElement = true 추가 (Dock 아이콘 숨김)

### Step 2-2. 투명 NSWindow 생성
- styleMask: .borderless, backgroundColor = .clear, isOpaque = false
- level = .floating (초기값. Phase 7에서 "항상 위/일반/바탕화면만" 동적 변경 예정)
- frame = NSScreen.main 전체 크기
- collectionBehavior: .canJoinAllSpaces + .fullScreenAuxiliary (모든 Space에 표시)
- ignoresMouseEvents = false (hitTest로 선택적 통과)

### Step 2-3. hitTest 오버라이드
- NSView 서브클래스에서 hitTest 오버라이드
- 포켓몬 스프라이트의 현재 위치/크기 영역 → self 반환 (클릭 가능)
- 그 외 영역 → nil 반환 (클릭 통과)

### Step 2-4. 포켓몬 스프라이트 렌더링
- Phase 1의 SpriteAnimator가 제공하는 Anim 프레임 + Shadow 프레임을 화면에 표시
- 픽셀아트 보간 끄기 (nearest-neighbor)
- 기본 크기: 화면 높이의 5~8%
- Shadow 이미지는 Anim 바로 아래에 겹쳐 렌더링
- 포켓몬 위치는 x, y 좌표 기반 (이동 로직은 Phase 3)

### Step 2-5. 완료 기준
- 앱 실행 시 Dock에 안 보이고, 투명 윈도우 위에 피카츄 Idle 애니메이션 재생
- 포켓몬 외 영역 클릭 시 아래 윈도우로 클릭 통과
- 모든 Space에서 포켓몬 보임

---

## Phase 3. 상태 머신 & 이동 로직
6개 상태(Idle, Walk, Run, Sleep, Reaction, Dragged) 전환 구현.
8방향 랜덤 이동, 화면 경계 반사, 전환 타이밍 로직.
상태 전환 규칙은 SCREEN_SPEC.md "포켓몬 상태 (State Machine)" 섹션 참고.

> **✅ 결정**: Reaction 애니메이션(Eat/Hop/Hurt) 스프라이트도 다운로드. Step 1-0에서 스크립트 수정 완료.
> **✅ 결정**: 게임 루프는 DispatchSourceTimer 사용.

### Step 3-1. 상태 머신
- 6개 상태: Idle, Walk, Run, Sleep, Reaction, Dragged
- 상태 전환 규칙:
  - Idle: 2~5초 후 → Walk. 3분(180초) 이상 → Sleep. 클릭 → Reaction
  - Walk: 3~10초 후 → Idle. 화면 가장자리 → 방향 전환
  - Run: 속도 2배, 프레임 1.5배. 10초 후 → Walk
  - Sleep: 클릭 → Idle
  - Reaction: Eat/Hop/Hurt 중 랜덤 1회 재생 → Idle
  - Dragged: Idle 프레임 고정 표시. 마우스 놓으면 → Idle

### Step 3-2. 이동 로직
- 랜덤 목표점 생성 → dx, dy → 8방향 매핑 (SPRITE_INTEGRATION_PLAN.md 섹션 5)
- Walk 2px/frame, Run 4px/frame
- 화면 가장자리에서 반대 방향으로 반사 (항상 반사, 래핑 모드 없음)

### Step 3-3. 게임 루프
- Phase 7 SettingsManager 구현 전까지 이동 속도/전환 타이밍/수면 시간은 기본값 하드코딩. Phase 7에서 동적 교체 예정.
- DispatchSourceTimer로 위치 업데이트 + 상태 전환 체크 (SpriteAnimator의 프레임 전환 타이머와 별개로 동작)
- 프레임 레이트: 30fps (≈33ms 간격)

### Step 3-4. 완료 기준
- 피카츄가 Idle ↔ Walk 자연스럽게 반복하며 8방향 이동
- 화면 가장자리에서 방향 반사
- 3분(180초) Idle 시 Sleep 전환, Sleep 상태에서 수면 애니메이션 재생

### Phase 3 생성 파일
- `poketmon/Core/PetStateMachine.swift` (6개 상태 enum + 전환 로직)
- `poketmon/Core/GameLoop.swift` (DispatchSourceTimer + 이동 업데이트)
- `poketmon/Core/PetManager.swift` (중앙 관리자 싱글턴, 하위 컴포넌트 소유)

---

## Phase 4. 마우스 인터랙션
좌클릭(Reaction), 드래그(Dragged), 우클릭(컨텍스트 메뉴), 더블클릭(선택기) 처리.
입력별 동작은 SCREEN_SPEC.md "인터랙션" 테이블 참고.

> **⚠️ 멀티 모니터 참고**: 모니터별 PetView가 독립적으로 존재. 포켓몬이 있는 모니터의 PetView에서만 마우스 이벤트 수신 (updateMousePassthrough에서 처리). 드래그 시 mouseDown이 발생한 PetView가 계속 이벤트를 받으므로 (NSView 마우스 캡처), 모니터를 넘어 드래그해도 정상 동작. 드래그 중 위치만 업데이트하면 다른 모니터의 PetView가 렌더링 담당.

### Step 4-1. 마우스 이벤트 처리
- PetView의 updateMousePassthrough로 포켓몬 영역에서만 이벤트 수신 (hitTest 대신)
- NSView에서 mouseDown, mouseDragged, mouseUp, rightMouseDown 오버라이드

### Step 4-2. 입력별 동작 연결
- 좌클릭: Sleep 상태면 → Idle. 그 외 → Reaction (Eat/Hop/Hurt 랜덤). 단, DispatchWorkItem으로 ~250ms 지연 후 실행. 더블클릭 시 cancel()하여 Reaction 방지
- 드래그: Dragged 상태 전환, 마우스 좌표 따라 포켓몬 위치 이동. 놓으면 → Idle. 마우스 좌표는 글로벌 좌표(NSEvent.mouseLocation)를 사용하여 모니터 간 드래그에도 대응
- 우클릭: NSMenu 컨텍스트 메뉴 표시 (메뉴 내용은 Phase 5에서 구현)
- 더블클릭: clickCount==2 감지 시 지연된 좌클릭 cancel() 후 포켓몬 선택기 윈도우 열기 (윈도우는 Phase 6에서 구현)

### Step 4-3. 완료 기준
- 좌클릭 시 Reaction 애니메이션 1회 재생 후 Idle 복귀
- 드래그로 포켓몬 위치 자유 이동 가능
- 우클릭/더블클릭은 이벤트 수신만 확인 (실제 메뉴/윈도우는 이후 Phase)

---

## Phase 5. 메뉴바 & 컨텍스트 메뉴
메뉴바 드롭다운 + 우클릭 컨텍스트 메뉴 구현. 상태 제어(일시정지, 재우기, 뛰게 하기).
항목 구성은 SCREEN_SPEC.md 화면 2, 3 참고. UI 디자인은 ui-mockup.html 참고.

> **✅ 결정**: 메뉴바 드롭다운은 MenuBarExtra + .window 스타일로 구현. SwiftUI View로 커스텀 UI 자유롭게 구성. 우클릭 컨텍스트 메뉴는 NSMenu 사용.

### Step 5-1. 메뉴바 완성
- Phase 2에서 추가한 MenuBarExtra 플레이스홀더를 완성
- 몬스터볼 아이콘 (16×16 Template 이미지) 적용. Assets.xcassets에 직접 생성 (원형 상단 빨강/하단 흰색, 중앙 검정 띠+원 — 단순 벡터)
- .menuBarExtraStyle(.window) 적용

### Step 5-2. 메뉴바 드롭다운 (SwiftUI View)
- 현재 포켓몬 정보 헤더 (이름, 번호, 상태)
- 포켓몬 변경 → Phase 6 선택기 윈도우 열기
- 설정 → Phase 7 설정 패널 열기
- 일시정지 토글 (SpriteAnimator 프레임 타이머 + 게임 루프 타이머 모두 정지 ↔ 재개)
- 재우기 (강제 Sleep 전환)
- 뛰게 하기 (Run 상태 10초 → Walk 복귀)
- 종료 (NSApplication.shared.terminate)
- UI 디자인은 ui-mockup.html 화면 2 참고

### Step 5-3. 우클릭 컨텍스트 메뉴 (NSMenu)
- Phase 4에서 수신한 rightMouseDown 이벤트에 연결
- 항목: 헤더(비활성), 포켓몬 변경, 설정, 구분선, 재우기/깨우기(상태 따라 텍스트 변경), 뛰게 하기, 구분선, 종료
- SCREEN_SPEC.md 화면 3 참고

### Step 5-4. 완료 기준
- 메뉴바에 몬스터볼 아이콘 표시, 클릭 시 커스텀 드롭다운 열림
- 일시정지/재우기/뛰게하기 동작 확인
- 우클릭 시 컨텍스트 메뉴 표시, 항목 동작 확인
- 포켓몬 변경/설정 버튼은 이벤트만 연결 (실제 윈도우는 Phase 6, 7)

---

## Phase 6. 포켓몬 선택기
NSPanel 기반 선택 윈도우. 검색바, 세대 탭(Gen 1~5), 타입 필터 칩(18종).
포켓몬 그리드 표시, 선택 시 데스크톱 펫 교체.
필터 조합 로직과 레이아웃은 SCREEN_SPEC.md 화면 4 참고. UI 디자인은 ui-mockup.html 참고.

> **✅ 결정**: 선택기 UI는 SwiftUI로 구현 (LazyVGrid 등 활용).

### Step 6-1. 선택기 윈도우
- NSPanel (.floating, 유틸리티 윈도우)에 NSHostingView로 SwiftUI View 삽입
- 크기: 480 × 600 pt
- Phase 5의 "포켓몬 변경" 버튼 및 더블클릭 이벤트에서 열기
- 윈도우 위치: 포켓몬이 현재 위치한 모니터의 중앙에 열기 (ScreenGeometry.shared.screenFrames에서 포켓몬 위치로 해당 모니터 판별)

### Step 6-2. 검색바
- 실시간 필터링 (타이핑과 동시에 그리드 갱신)
- 검색 대상: 포켓몬 영문 이름, 번호 (#025)
- 검색어 입력 시 세대/타입 필터 무시하고 전체 검색. 검색어 삭제 시 필터 상태 복원

### Step 6-3. 세대 탭
- 5개 세그먼트: Gen 1 (151종) / Gen 2 (100종) / Gen 3 (135종) / Gen 4 (107종) / Gen 5 (156종)
- 기본값: Gen 1. 탭 전환 시 그리드 갱신
- 타입 필터와 AND 조건 결합

### Step 6-4. 타입 필터 칩
- 18개 타입 토글 버튼 (Normal, Fire, Water, ...)
- 복수 선택 가능 (OR 조건 — 선택된 타입 중 하나라도 가진 포켓몬 표시)
- 전체 비활성 = 필터 없음 (전체 표시)

### Step 6-5. 포켓몬 그리드
- SwiftUI LazyVGrid로 구현
- 셀: 번호 + Idle 스프라이트 첫 프레임 축소 + 이름
- 썸네일 로딩: 비동기 로딩 (Task) + 메모리 캐시 (Dictionary). LazyVGrid가 화면에 보이는 셀만 로드 요청하므로 한 번에 20~30개만 처리. 캐시로 탭 전환/재열기 시 재로딩 방지
- 선택 시 파란 테두리, 현재 사용 중인 포켓몬은 녹색 테두리
- 누락 16종은 회색 처리 + 선택 불가

### Step 6-6. 필터 조합 로직
- 검색어 있으면 → 전체에서 검색 (세대/타입 무시)
- 검색어 없으면 → 세대 AND 타입 필터 적용

### Step 6-7. 선택 완료 / 취소
- 선택 완료: PetManager에 새 포켓몬 ID 전달 → SpriteAnimator 교체 + 상태 머신 Idle로 리셋. 윈도우 닫기
- 취소: 변경 없이 윈도우 닫기

### Step 6-8. 완료 기준
- 선택기 윈도우에서 세대/타입/검색으로 포켓몬 필터링 동작
- 포켓몬 선택 후 데스크톱 펫이 새 포켓몬으로 교체되어 애니메이션 재생

---

## Phase 7. 설정 패널
NSPanel 기반 설정 윈도우. 크기/투명도/표시위치, 이동속도/활동빈도/수면시간, 시스템 설정.
UserDefaults 저장 & 실시간 반영.
설정 항목과 범위는 SCREEN_SPEC.md 화면 5 참고. UI 디자인은 ui-mockup.html 참고.

### Step 7-1. 설정 윈도우
- NSPanel (.floating)에 NSHostingView로 SwiftUI View 삽입
- 크기: 400 × 500 pt
- Phase 5의 "설정" 버튼에서 열기

### Step 7-2. 표시 섹션
- 크기: 슬라이더 50% ~ 200% (기본 100%). 포켓몬 스프라이트 렌더링 배율
- 투명도: 슬라이더 30% ~ 100% (기본 100%). 스프라이트 불투명도. 모든 overlayWindows에 alphaValue 적용
- 표시 위치: 드롭다운 — 항상 위 / 일반 / 바탕화면만 (ui-mockup.html에 추가된 항목). 변경 시 모든 overlayWindows를 순회하며 level 적용 (AppDelegate.overlayWindows.forEach { $0.level = newLevel })

### Step 7-3. 행동 섹션
- 이동 속도: 슬라이더 1~5단계 (기본 3). Walk/Run 시 px/frame 조절
- 활동 빈도: 슬라이더 1~5단계 (기본 3). Walk ↔ Idle 전환 주기
- 수면까지: 슬라이더 1분~10분 (기본 3분). Idle → Sleep 자동 전환 시간

### Step 7-4. 시스템 섹션
- 로그인 시 자동 실행: 체크박스 (기본 OFF). SMAppService 또는 LaunchAgent

> **✅ 결정**: "다른 윈도우 위에서만 이동" 체크박스 제거. "표시 위치" 드롭다운(Step 7-2)으로 대체.
> **✅ 결정**: "화면 가장자리에서 반사" 체크박스 제거. 항상 반사 동작 (래핑 모드 없음).

### Step 7-5. SettingsManager
- UserDefaults 기반 저장 (키 프리픽스: com.poketmon.settings.)
- 슬라이더/체크박스 값 변경 즉시 저장 & 실시간 반영 (별도 저장 버튼 없음)
- 앱 실행 시 자동 로드, 값 없으면 기본값
- @Observable로 구현하여 SwiftUI 바인딩 + Phase 3 이동 로직에 반영 (PetManager.shared.settingsManager로 접근)

### Step 7-6. 액션 버튼
- 기본값 복원: 모든 설정을 기본값으로 리셋
- 닫기: 설정 패널 닫기

### Step 7-7. 완료 기준
- 설정 패널에서 크기/투명도 변경 시 데스크톱 포켓몬에 실시간 반영
- 이동 속도/활동 빈도 변경 시 포켓몬 행동에 즉시 반영
- 앱 재실행 시 설정값 유지

---

## Phase 8. 마무리 & 폴리시
최종 다듬기 단계. 안정성, 성능, 사용자 경험 개선.

### Step 8-1. 데이터 영속성
- 마지막 선택 포켓몬 ID 저장 (앱 재실행 시 같은 포켓몬으로 시작)
- 마지막 위치 저장 (앱 재실행 시 같은 위치에서 시작)

### Step 8-2. 성능 최적화
- 스프라이트 캐싱: 현재 포켓몬의 6종(Walk/Idle/Sleep/Eat/Hop/Hurt) 전체 프레임 메모리 로드, 교체 시 해제
- 불필요 시 타이머 정지 (Sleep 상태에서 이동 타이머 불필요)
- 메모리 프로파일링으로 누수 확인

### Step 8-3. 멀티 모니터 지원 & 엣지 케이스 처리

> **✅ Phase 3 테스트 중 선행 구현 완료.**
> **방식**: 모니터별 독립 윈도우 (per-screen windows). macOS가 단일 윈도우의 음수 origin을 (0,0)으로 강제 보정하는 문제 때문에 단일 union 윈도우 방식 불가.

- **✅ ScreenGeometry 싱글턴**: unionFrame, screenFrames, isOnScreen, clampToNearestScreen, randomTarget. didChangeScreenParametersNotification 자동 재계산
- **✅ 모니터별 윈도우 생성**: AppDelegate.overlayWindows 배열. 각 모니터의 frame으로 독립 OverlayWindow + PetView 생성
- **✅ 이동 범위 확장**: PetManager.tick()에서 ScreenGeometry.shared.unionFrame을 screenBounds로 사용
- **✅ Dead zone 보정**: PetStateMachine.moveTowardTarget에서 모니터 사이 빈 영역 진입 시 가장 가까운 모니터로 보정
- **✅ 모니터 변경 감지**: onScreenChange 콜백 → 전체 윈도우 재생성 + relocateIfOffScreen
- **✅ 목표점 유지**: Walk → Idle 전환 시 targetPoint 유지하여 여러 사이클에 걸쳐 다른 모니터까지 도달 가능
- 스프라이트 파일 누락 시 graceful fallback (미구현)

### Step 8-4. 포켓몬 교체 전환 효과
- 포켓몬 변경 시 현재 위치에서 페이드 전환 (SCREEN_SPEC.md 시나리오 2)

### Step 8-5. 최종 테스트
- 전체 상태 전환 흐름 확인 (Idle → Walk → Run → Sleep → Reaction → Dragged)
- 메뉴바/컨텍스트 메뉴 전체 항목 동작 확인
- 포켓몬 선택기 필터/검색/교체 동작 확인
- 설정 패널 전 항목 실시간 반영 확인
- 앱 재실행 시 설정·포켓몬·위치 복원 확인
