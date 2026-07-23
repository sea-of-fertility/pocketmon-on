# Ver2 개발 계획

> Ver1 완료 상태 기반. 새로운 기능 추가 및 개선.

---

## Feature 1. 특정 모니터 이동 제한

펫의 이동 범위를 특정 모니터 하나로 제한하는 설정 추가.
기본값은 "모든 모니터" (현재 동작 유지).

### 핵심 아이디어
`ScreenGeometry`에 "활성 범위(activeBounds)" 개념 도입.
모니터 제한 시 해당 모니터 `frame`만 반환, "모든 모니터" 시 기존 `unionFrame` 반환.

### Step 1. ScreenGeometry 확장
**파일**: `poketmon/Core/ScreenGeometry.swift`

- `screenNames: [String]` 추가 — `recalculate()`에서 `NSScreen.localizedName`으로 채움
- `restrictedScreenName: String?` 추가 — nil이면 전체 모니터 (기본값)
- `activeBounds: CGRect` 계산 프로퍼티 — 제한 모니터 frame 또는 unionFrame
- `activeScreenFrames: [CGRect]` 계산 프로퍼티 — 제한 모니터만 또는 전체
- `isOnActiveScreen(_:margin:)` — activeScreenFrames 기준 판정
- `clampToNearestActiveScreen(_:margin:)` — activeScreenFrames 기준 보정
- `randomTarget(margin:)` 수정 — `screenFrames` → `activeScreenFrames` 사용

### Step 2. SettingsManager에 모니터 제한 설정 추가
**파일**: `poketmon/Services/SettingsManager.swift`

- `Key.restrictedMonitor` 키 추가
- `restrictedMonitorName: String?` 프로퍼티 + `didSet`에서 저장 및 `ScreenGeometry` 동기화
- `applyMonitorRestriction()` — `ScreenGeometry.shared.restrictedScreenName` 반영
- `availableMonitors: [(name: String, frame: CGRect)]` 계산 프로퍼티 (UI용)
- `loadFromDefaults()` — 저장값 로드 + `applyMonitorRestriction()` 호출
- `resetToDefaults()` — `restrictedMonitorName = nil` 추가

### Step 3. PetManager 이동 범위 변경
**파일**: `poketmon/Core/PetManager.swift`

- `tick()` 98행: `geo.unionFrame` → `geo.activeBounds` (1줄 변경)
- `relocateIfOffScreen()`: `isOnScreen` → `isOnActiveScreen`, `clampToNearestScreen` → `clampToNearestActiveScreen`
- `relocateIfOffScreen()`에 `stateMachine.clearTarget()` 추가

### Step 4. PetStateMachine dead zone 보정 변경
**파일**: `poketmon/Core/PetStateMachine.swift`

- `moveTowardTarget()` 259행: `geo.isOnScreen(position)` → `geo.isOnActiveScreen(position)`
- `moveTowardTarget()` 260행: `geo.clampToNearestScreen` → `geo.clampToNearestActiveScreen`
- `clearTarget()` public 메서드 추가 (모니터 변경 시 목표점 초기화용)

### Step 5. 설정 UI에 모니터 선택 Picker 추가
**파일**: `poketmon/Views/SettingsView.swift`

- `displaySection`에 "이동 범위" Picker 추가 ("표시 위치" 아래)
- 옵션: "모든 모니터" + 각 연결된 모니터 이름
- 모니터 레이블: `localizedName` + 위치 힌트 ("주 모니터", "왼쪽", "오른쪽" 등)

### 엣지 케이스
- **모니터 분리**: `activeBounds`가 `unionFrame`으로 자동 폴백 (이름 매칭 실패)
- **모니터 재연결**: `recalculate()` → `screenNames` 갱신 → `activeBounds` 자동 복원
- **드래그**: 제한 밖으로 드래그 허용, 놓은 후 다음 tick에서 자동 보정
- **동일 이름 모니터 2대**: 첫 번째 매칭 사용

### 완료 기준
- 설정 > 표시 > "이동 범위"에서 특정 모니터 선택 가능
- 펫이 선택한 모니터 안에서만 이동
- "모든 모니터" 전환 시 전체 이동 복원
- 모니터 분리 시 graceful fallback 동작
