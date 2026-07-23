# PokePet — 플랫폼 독립 동작 명세서

> 이 문서는 macOS 구현에서 추출한 **플랫폼에 의존하지 않는 순수 동작 로직**을 정리한 것입니다.
> 다른 플랫폼(Windows, Linux, Web 등)에서 동일한 데스크톱 펫을 구현할 때 참고 문서로 사용합니다.

---

## 1. 전체 아키텍처

```
PetManager (중앙 싱글턴)
  ├─ SpriteAnimator   — 현재 프레임 제공, 애니메이션 전환/크로스페이드
  ├─ StateMachine      — 6개 상태 관리, 위치/방향 계산, 경계 처리
  ├─ GameLoop          — 30 FPS 타이머, 매 프레임 tick() 호출
  ├─ SettingsManager   — 설정 저장/로드
  └─ PokemonDataManager — 649종 포켓몬 목록 (pokemon_data.json)
```

### 메인 루프 흐름 (30 FPS)

```
매 프레임 (33.33ms 간격):
  1. StateMachine.update() → 상태 전이 확인, 위치 이동, 경계 반사
  2. 애니메이션 변경 필요 시 → SpriteAnimator.switchAnimation()
  3. 방향 동기화 → SpriteAnimator.setDirection(현재방향)
  4. 30초마다 → 현재 위치 저장
```

---

## 2. 상태 머신

### 2.1 상태 목록

| 상태 | 설명 | 애니메이션 |
|------|------|-----------|
| `idle` | 제자리 대기 | Idle |
| `walk` | 목표 지점으로 이동 | Walk |
| `run` | 빠르게 이동 (Walk 애니메이션 가속) | Walk (1.5배속) |
| `sleep` | 수면 (게임 루프 일시정지) | Sleep |
| `reaction` | 클릭 반응 (Eat/Hop/Hurt 중 랜덤) | 원샷 재생 |
| `dragged` | 사용자가 드래그 중 | Idle |

### 2.2 상태 전이 다이어그램

```
                    ┌──────────────────────────────┐
                    │         sleepTimeout          │
                    ▼         경과 시 자동           │
 ┌──────┐   시간경과   ┌──────┐   시간경과   ┌───────┐
 │ walk │ ◄──────── │ idle │ ────────► │ sleep │
 │      │ ────────► │      │           │       │
 └──┬───┘   시간경과   └──┬───┘           └───┬───┘
    │                    │                    │
    │ 랜덤              │ 클릭              │ 클릭/wake
    ▼                    ▼                    ▼
 ┌──────┐           ┌──────────┐         idle로 복귀
 │ run  │           │ reaction │
 │      │──10초후──►│          │──완료──► idle
 └──────┘   walk    └──────────┘

        어떤 상태에서든 드래그 시 → dragged
        드래그 종료 시 → 이전 상태 복귀
```

### 2.3 전이 조건 상세

#### idle → walk
- 조건: idle 상태에서 `transitionTime` 경과
- `transitionTime` = `idleToWalkRange`에서 랜덤 선택 (진입 시 결정)
- 전이 시: `randomTarget()` 생성 → 해당 지점으로 이동 시작

#### walk → idle
- 조건: walk 상태에서 `transitionTime` 경과
- `transitionTime` = `walkToIdleRange`에서 랜덤 선택

#### walk 중 목표 도달
- 조건: `distance(현재위치, 목표) < speed × 2`
- 동작: 새로운 `randomTarget()` 생성, 방향 재계산
- 상태는 유지 (walk 계속)

#### idle → sleep
- 조건: `마지막 인터랙션 시각`으로부터 `sleepTimeout`초 경과
- 동작: 게임 루프 일시정지 (CPU 절약)

#### sleep → idle
- 트리거: 사용자 클릭 또는 `wake()` 호출
- 동작: 게임 루프 재개

#### walk → run (랜덤 발생)
- 조건: walk 상태에서 확률적으로 발생
- 지속: **10.0초** 고정
- 완료 후: walk로 복귀

#### 어떤 상태 → reaction
- 트리거: 사용자 싱글 클릭
- 동작: Eat/Hop/Hurt 중 사용 가능한 애니메이션 랜덤 선택 → 원샷 재생
- 완료 후: idle로 복귀

#### 어떤 상태 → dragged
- 트리거: 사용자 드래그 (3px 이상 이동)
- 동작: 이전 상태 저장, 애니메이션을 Idle로 전환
- 종료 시: 이전 상태 복귀 (sleep이었으면 sleep으로, walk이었으면 walk으로)

---

## 3. 이동 & 방향

### 3.1 이동 속도 (px/frame, 30FPS 기준)

| 설정값 | walk 속도 | run 속도 |
|--------|----------|---------|
| 1 (매우 느림) | 1.0 | 2.0 |
| 2 (느림) | 1.5 | 3.0 |
| **3 (기본)** | **2.0** | **4.0** |
| 4 (빠름) | 3.0 | 6.0 |
| 5 (매우 빠름) | 4.0 | 8.0 |

> `run 속도 = walk 속도 × 2.0`

### 3.2 이동 로직

```
매 프레임:
  dx = targetPoint.x - position.x
  dy = targetPoint.y - position.y
  distance = sqrt(dx² + dy²)

  if distance < speed × 2:
    // 목표 도달 → 새 목표 생성
    targetPoint = randomTarget(margin: 40)
    updateDirection()
  else:
    // 목표를 향해 이동
    position.x += (dx / distance) × speed
    position.y += (dy / distance) × speed
    updateDirection()
```

### 3.3 8방향 계산

```
8방향 (스프라이트 시트 행 순서):
  Row 0 = Down (↓)
  Row 1 = DownRight (↘)
  Row 2 = Right (→)
  Row 3 = UpRight (↗)
  Row 4 = Up (↑)
  Row 5 = UpLeft (↖)
  Row 6 = Left (←)
  Row 7 = DownLeft (↙)

방향 결정 알고리즘:
  dx = target.x - current.x
  dy = target.y - current.y  (양수 = 위, 음수 = 아래 — 좌표계 주의)
  isDiagonal = min(|dx|, |dy|) > max(|dx|, |dy|) × 0.4

  if isDiagonal:
    dx > 0 && dy < 0 → DownRight
    dx > 0 && dy > 0 → UpRight
    dx < 0 && dy > 0 → UpLeft
    dx < 0 && dy < 0 → DownLeft
  else if |dx| > |dy|:
    dx > 0 → Right
    dx < 0 → Left
  else:
    dy > 0 → Up
    dy < 0 → Down
```

> **좌표계 주의:** macOS는 좌하단 원점 (y↑ = 위). Windows/웹은 좌상단 원점 (y↑ = 아래).
> 방향 계산 시 좌표계에 맞게 dy 부호를 반전해야 합니다.

---

## 4. 화면 경계 & 멀티 모니터

### 4.1 멀티 모니터 좌표계

```
각 모니터를 글로벌 좌표계에서 관리:
  screenFrames: [Rect]  — 모니터별 글로벌 좌표 직사각형
  unionFrame: Rect       — 모든 모니터를 포함하는 최소 직사각형

예시 (모니터 2개):
  모니터1: (0, 0, 1920, 1080)
  모니터2: (1920, 0, 2560, 1440)
  unionFrame: (0, 0, 4480, 1440)
```

### 4.2 모니터 제한 기능

```
restrictedMonitor: String?  (nil = 전체 모니터)

activeScreenFrames:
  if restrictedMonitor 설정됨 → 해당 모니터만 반환
  else → 전체 모니터 반환
```

### 4.3 경계 반사 (Bounce)

#### 벽 판정에 사용되는 크기값

`position`은 포켓몬의 **발(하단) 중앙 좌표**입니다. 벽 판정은 이 position을 기준으로
스프라이트가 화면 밖으로 삐져나가지 않도록 합니다.

```
spriteScale = primaryScreenHeight / 450.0 × userScaleMultiplier

halfWidth      = currentFrameSize.width × spriteScale / 2   ← 현재 애니메이션 프레임 기준
height         = currentFrameSize.height × spriteScale       ← 현재 애니메이션 프레임 기준
walkHalfHeight = walkFrameSize.height × spriteScale / 2      ← 항상 Walk 프레임 기준 (고정)
```

> **왜 Walk 기준인가?**
> 수직 경계는 항상 Walk 프레임 높이를 기준으로 판정합니다.
> 애니메이션이 Idle→Walk→Sleep으로 바뀔 때마다 프레임 크기가 달라지는데,
> 매번 다른 높이로 경계를 계산하면 포켓몬이 벽에 닿을 때 위치가 흔들립니다.
> Walk은 이동 중에 사용되는 기본 애니메이션이므로 이를 **고정 앵커**로 사용합니다.

#### 판정 로직

```
position 기준 도식 (macOS 좌하단 원점):

  screen.maxY ─────────────────────────── 천장
       │                                    │
       │     pos.y 최대 허용:               │
       │     screen.maxY - height           │
       │     + walkHalfHeight               │
       │         ┌─────────┐                │
       │         │ sprite  │ ← height       │
       │         │  전체   │                │
       │         │         │                │
       │         └────●────┘                │  ● = position (발 중앙)
       │              │                     │
       │     pos.y 최소 허용:               │
       │     screen.minY + walkHalfHeight   │
       │                                    │
  screen.minY ─────────────────────────── 바닥

  ◄─halfWidth─►●◄─halfWidth─►
  screen.minX                  screen.maxX
```

```
clampSpritePosition(position, halfWidth, height, walkHalfHeight):

  1. 현재 position이 속한 모니터의 frame 찾기
     (어떤 모니터에도 속하지 않으면 가장 가까운 모니터 선택)

  2. 수평 판정:
     왼쪽 벽: pos.x < frame.minX + halfWidth       → 벽에 부딪힘
     오른쪽 벽: pos.x > frame.maxX - halfWidth      → 벽에 부딪힘

  3. 수직 판정 (발 앵커 기준):
     바닥: pos.y < frame.minY + walkHalfHeight      → 벽에 부딪힘
     천장: pos.y > frame.maxY - height + walkHalfHeight → 벽에 부딪힘

  4. 부딪힌 경우:
     위치를 경계 안으로 클램핑 (벽에 붙임)
     bounced = true
     새로운 randomTarget 생성 → 반대 방향으로 자연스럽게 전환

  5. 드래그 중에는 모니터 제한 무시 (ignoreRestriction = true)
     → 전체 모니터 영역에서 자유롭게 이동 가능
```

#### 구체적 예시

```
예시: 1080p 모니터, 48×48 Walk 프레임, spriteScale = 2.4, 설정 100%

  halfWidth      = 48 × 2.4 / 2 = 57.6 px
  height         = 48 × 2.4     = 115.2 px  (현재 애니메이션이 Walk인 경우)
  walkHalfHeight = 48 × 2.4 / 2 = 57.6 px

  모니터 frame = (0, 0, 1920, 1080)

  수평 허용 범위: 57.6 ~ 1862.4  (양쪽 57.6px 여백)
  수직 허용 범위: 57.6 ~ 1022.4  (바닥 57.6px, 천장 57.6px 여백)

  → 포켓몬의 발 좌표가 이 범위를 벗어나면 bounced = true
```

### 4.4 데드존 처리

모니터 사이 빈 공간(데드존)에 포켓몬이 빠지는 것을 방지합니다.

```
isOnScreen(point, margin):
  어떤 모니터의 (margin만큼 inset된) 영역에 포함되면 true

clampToNearestScreen(point, margin):
  모든 activeScreenFrame에 대해:
    해당 프레임의 margin-inset 영역으로 클램핑한 점을 계산
    거리 = dx² + dy²
  가장 가까운 클램핑 결과를 반환

경계 반사 후 데드존 체크:
  if !isOnScreen(clampedPosition):
    clampedPosition = clampToNearestScreen(position)
    bounced = true
```

### 4.5 랜덤 목표 생성

```
randomTarget(margin: 40):
  1. activeScreenFrames에서 랜덤 모니터 선택
  2. 모니터 영역을 margin(40px)만큼 inset
  3. inset 영역 내 랜덤 좌표 반환
  4. inset 결과가 유효하지 않으면 → 모니터 중심점 반환
```

---

## 5. 스프라이트 시스템

### 5.1 파일 구조

```
Sprites/
  {ID}/                     — 4자리 제로패딩 (예: "0025" = 피카츄)
    AnimData.xml             — 애니메이션 메타데이터
    Walk-Anim.png            — Walk 스프라이트 시트
    Walk-Shadow.png          — Walk 그림자 시트
    Idle-Anim.png
    Idle-Shadow.png
    Sleep-Anim.png
    Sleep-Shadow.png
    Eat-Anim.png             — (없을 수 있음)
    Hop-Anim.png             — (없을 수 있음)
    Hurt-Anim.png            — (없을 수 있음)
    ...

ID 포맷: String.format("%04d", pokemonID)
  예: 1 → "0001", 25 → "0025", 649 → "0649"
```

### 5.2 AnimData.xml 형식

```xml
<AnimData>
  <ShadowSize>24</ShadowSize>
  <Anims>
    <Anim>
      <Name>Walk</Name>
      <Index>0</Index>
      <FrameWidth>48</FrameWidth>
      <FrameHeight>48</FrameHeight>
      <Durations>
        <Duration>8</Duration>     <!-- 8/60초 = 0.1333초 -->
        <Duration>8</Duration>
        <Duration>8</Duration>
        <Duration>8</Duration>
      </Durations>
    </Anim>
    <Anim>
      <Name>Idle</Name>
      ...
    </Anim>
    ...
  </Anims>
</AnimData>
```

**Duration 단위:** 1/60초 (60분의 1초)
- `Duration=8` → 8/60 = 0.1333초
- `Duration=4` → 4/60 = 0.0667초

### 5.3 스프라이트 시트 레이아웃

```
┌─────────────────────────────────────────┐
│ Frame0  Frame1  Frame2  Frame3  ...     │ Row 0 = Down
│ Frame0  Frame1  Frame2  Frame3  ...     │ Row 1 = DownRight
│ Frame0  Frame1  Frame2  Frame3  ...     │ Row 2 = Right
│ Frame0  Frame1  Frame2  Frame3  ...     │ Row 3 = UpRight
│ Frame0  Frame1  Frame2  Frame3  ...     │ Row 4 = Up
│ Frame0  Frame1  Frame2  Frame3  ...     │ Row 5 = UpLeft
│ Frame0  Frame1  Frame2  Frame3  ...     │ Row 6 = Left
│ Frame0  Frame1  Frame2  Frame3  ...     │ Row 7 = DownLeft
└─────────────────────────────────────────┘

프레임 추출:
  rect = (frameIndex × frameWidth, directionRow × frameHeight, frameWidth, frameHeight)
  cropped = image.crop(rect)

8방향 미만인 경우:
  실제 행 수 = min(imageHeight / frameHeight, 8)
  부족한 방향은 Row 0 (Down)을 복제하여 채움
```

### 5.4 애니메이션 타입

| 타입 | 용도 | 필수 여부 |
|------|------|----------|
| Walk | 이동 | 필수 |
| Idle | 대기 | 필수 |
| Sleep | 수면 | 필수 |
| Eat | 반응(먹기) | 선택 |
| Hop | 반응(점프) | 선택 |
| Hurt | 반응(아파) | 선택 |

> 반응 애니메이션은 해당 포켓몬에 존재하는 것 중에서만 랜덤 선택

---

## 6. 렌더링

### 6.1 스프라이트 스케일

```
baseScale = primaryScreenHeight / 450.0
spriteScale = baseScale × userScaleMultiplier

userScaleMultiplier = userScaleSetting / 100.0  (범위: 0.5 ~ 2.0)

예시:
  1080p 모니터, 사용자 설정 100%:
    baseScale = 1080 / 450 = 2.4
    spriteScale = 2.4 × 1.0 = 2.4
    48px 프레임 → 화면에서 115px로 렌더링
```

> **핵심 원칙:** 모든 포켓몬을 동일 크기로 강제하지 않고, 원본 프레임 크기 차이를 자연스럽게 반영.
> 큰 포켓몬(예: Steelix 80px)은 크게, 작은 포켓몬(예: Pichu 32px)은 작게 표시.

### 6.2 위치 앵커 (발 기준)

```
position = 포켓몬의 발(하단) 중앙 좌표

렌더링 영역 계산:
  width  = currentFrameSize.width × spriteScale
  height = currentFrameSize.height × spriteScale
  walkH  = walkFrameSize.height × spriteScale  (경계 기준 높이)

  renderRect:
    x = position.x - width / 2
    y = position.y - walkH / 2
    size = (width, height)

경계 계산에는 Walk 프레임 높이를 기준으로 사용 (애니메이션 변경 시 경계가 흔들리지 않도록)
```

### 6.3 그림자 렌더링

```
그림자 위치/크기 (Walk 프레임 기준):
  walkW = walkFrameSize.width × spriteScale
  walkH = walkFrameSize.height × spriteScale

  shadowWidth  = walkW × 0.8
  shadowHeight = walkH × 0.15
  shadowX      = petRect.midX - shadowWidth / 2
  shadowY      = petRect.minY - walkH × 0.05  (발 바로 아래)

그림자 렌더링 방법:
  1. Shadow 스프라이트를 그레이스케일로 변환
  2. 알파 마스크로 사용
  3. 마스크 영역에 검정색, 알파 0.25 × currentAlpha로 채우기
```

### 6.4 픽셀아트 렌더링

```
보간 방식: nearest-neighbor (최근접 이웃)
반드시 nearest-neighbor를 사용해야 픽셀아트가 선명하게 확대됩니다.

플랫폼별 설정:
  - macOS:  CGContext.interpolationQuality = .none
  - Web:    canvas context.imageSmoothingEnabled = false
  - WPF:    RenderOptions.BitmapScalingMode = NearestNeighbor
  - Direct2D: D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR
```

### 6.5 렌더링 최적화

```
화면 밖 포켓몬 렌더링 스킵:
  margin = max(walkW, walkH) × 1.5
  expandedFrame = screenFrame.inset(-margin)  (확장)

  if !expandedFrame.contains(position):
    렌더링 건너뜀
```

---

## 7. 포켓몬 전환 (크로스페이드)

### 7.1 전환 과정

```
changePokemon(newID):
  1. 이전 프레임 스냅샷 저장 (현재 프레임, 그림자, 위치, 크기)
  2. 새 포켓몬 스프라이트 로드
  3. 크로스페이드 시작: transitionProgress = 0.0
  4. 상태를 idle로 리셋
```

### 7.2 크로스페이드 렌더링

```
전환 지속시간: 0.3초

매 프레임:
  elapsed = 현재시각 - transitionStartTime
  transitionProgress = min(elapsed / 0.3, 1.0)

  if transitionProgress < 1.0:
    이전 포켓몬 그리기: alpha = 1.0 - transitionProgress  (페이드 아웃)
    새 포켓몬 그리기:   alpha = transitionProgress          (페이드 인)
  else:
    전환 완료: 이전 프레임 데이터 해제
    새 포켓몬만 그리기: alpha = 1.0
```

---

## 8. 애니메이션 타이밍

### 8.1 프레임 재생

```
currentFrameIndex = 0

scheduleNextFrame():
  durations = currentAnimation.durationsInSeconds  // AnimData에서 파싱
  delay = durations[currentFrameIndex % count] / max(speedMultiplier, 0.1)

  delay 후:
    nextIndex = (currentFrameIndex + 1) % frameCount
    currentFrameIndex = nextIndex
    scheduleNextFrame()
```

### 8.2 속도 배율

| 상태 | speedMultiplier | 효과 |
|------|----------------|------|
| run | 1.5 | 프레임 간격 66% (더 빠른 재생) |
| 기타 | 1.0 | 원본 속도 |

### 8.3 원샷 애니메이션 (reaction)

```
playOnce(animationType, onComplete):
  currentAnimation = animationType
  currentFrameIndex = 0
  isOneShot = true

  프레임 루프 중:
    if isOneShot && nextIndex == 0:
      // 한 바퀴 완료
      onComplete() 호출
      프레임 루프 중단
```

---

## 9. 사용자 인터랙션

### 9.1 클릭 처리

```
싱글 클릭:
  250ms 지연 후 reaction 실행 (더블클릭 대기)

더블 클릭:
  대기 중인 reaction 취소
  포켓몬 선택기 열기

싱글/더블 클릭 판별:
  mouseDown 시 250ms 타이머 시작
  250ms 내에 두 번째 클릭 → 더블클릭
  250ms 경과 → 싱글클릭 (reaction 실행)
```

### 9.2 드래그

```
드래그 시작 조건: 마우스 이동 거리 ≥ 3px

mouseDown:
  dragOffset = petPosition - mousePosition

mouseDragged:
  distance = sqrt(dx² + dy²)
  if distance ≥ 3.0:
    if !isDragging:
      startDrag()  // 상태 → dragged
    newPosition = currentMouse + dragOffset
    clamp to screen bounds (모니터 제한 무시 — 자유로운 드래그)
    petPosition = clampedPosition

mouseUp:
  if isDragging:
    endDrag()  // 이전 상태 복귀
```

### 9.3 마우스 패스스루 (투명 윈도우)

```
매 프레임 (30Hz):
  petRect = 현재 포켓몬 렌더링 영역

  if 마우스 커서가 petRect 안에 있음:
    윈도우 클릭 활성화 (마우스 이벤트 수신)
  else:
    윈도우 클릭 패스스루 (아래 윈도우로 이벤트 전달)

  드래그 중에는 항상 클릭 활성화
```

### 9.4 우클릭 컨텍스트 메뉴

```
항목:
  - 포켓몬 변경 (선택기 열기)
  - 설정 열기
  - 일시정지 / 재개
  - 종료
```

---

## 10. 설정

### 10.1 설정 항목 & 기본값

| 설정 | 범위 | 기본값 | 설명 |
|------|------|--------|------|
| spriteScale | 50 ~ 200 | 100 | 크기 배율 (%) |
| opacity | 30 ~ 100 | 100 | 불투명도 (%) |
| windowLevel | 0, 1, 2 | 0 | 윈도우 레이어 |
| movementSpeed | 1 ~ 5 | 3 | 이동 속도 |
| activityFrequency | 1 ~ 5 | 3 | 활동 빈도 |
| sleepTimeout | 1 ~ 10 | 3 | 수면 진입 (분) |
| autoLaunch | bool | false | 로그인 시 자동 시작 |
| currentPokemonID | int | — | 현재 포켓몬 |
| lastPositionX/Y | float | — | 마지막 위치 |
| restrictedMonitor | string? | nil | 특정 모니터 제한 |

### 10.2 윈도우 레이어

| 값 | 이름 | 동작 |
|----|------|------|
| 0 | 항상 위 | 모든 윈도우 위에 표시 |
| 1 | 일반 | 다른 윈도우와 같은 레이어 |
| 2 | 바탕화면 | 바탕화면 아이콘 아래 표시 |

### 10.3 활동 빈도 상세

**idle → walk 전이 시간 (초)**

| 설정 | 범위 | 설명 |
|------|------|------|
| 1 | 5.0 ~ 10.0 | 매우 조용 |
| 2 | 3.0 ~ 7.0 | 조용 |
| **3** | **2.0 ~ 5.0** | **보통** |
| 4 | 1.0 ~ 3.0 | 활발 |
| 5 | 0.5 ~ 2.0 | 매우 활발 |

**walk → idle 전이 시간 (초)**

| 설정 | 범위 | 설명 |
|------|------|------|
| 1 | 2.0 ~ 4.0 | 짧게 걸음 |
| 2 | 2.5 ~ 6.0 | |
| **3** | **3.0 ~ 10.0** | **보통** |
| 4 | 5.0 ~ 15.0 | |
| 5 | 8.0 ~ 20.0 | 오래 걸음 |

---

## 11. 앱 동작

### 11.1 시스템 트레이 (메뉴바)

```
앱은 Dock/태스크바에 표시되지 않음.
시스템 트레이(macOS 메뉴바) 아이콘으로만 접근.

트레이 메뉴 항목:
  - 현재 포켓몬 이름 & 번호
  - 포켓몬 변경
  - 설정
  - 일시정지 / 재개
  - 종료
```

### 11.2 투명 오버레이 윈도우

```
윈도우 속성:
  - 프레임 없음 (borderless)
  - 배경 투명
  - 그림자 없음
  - 포커스 가져가지 않음 (canBecomeKey = false)
  - 모든 가상 데스크톱에 표시
  - macOS 좌표 자동 보정 방지 (constrainFrameRect 무시)

멀티 모니터:
  모니터별로 독립 투명 윈도우 생성 (단일 대형 윈도우 불가 — OS가 좌표 강제 보정)
  포켓몬 위치에 따라 해당 모니터의 윈도우에서만 렌더링
```

### 11.3 위치 복원

```
앱 시작 시:
  if 저장된 위치가 존재 AND isOnScreen(저장위치, margin: 20):
    해당 위치에서 시작
  else:
    주 모니터 중앙, 상단 30% 높이에서 시작
    (x = centerX, y = minY + height × 0.3)
```

---

## 12. 포켓몬 데이터

### 12.1 pokemon_data.json 형식

```json
[
  { "id": 1, "name": "Bulbasaur", "gen": 1, "types": ["Grass", "Poison"] },
  { "id": 25, "name": "Pikachu", "gen": 1, "types": ["Electric"] },
  ...
  { "id": 649, "name": "Genesect", "gen": 5, "types": ["Bug", "Steel"] }
]
```

- 총 649종 (1세대 ~ 5세대)
- 포켓몬 선택 UI에서 세대별/타입별 필터링 지원
- 초상화 이미지: `Portraits/{ID}/Normal.png` (선택기에서 표시)

---

## 13. 상수 요약

```
=== 타이밍 ===
게임 루프 FPS:           30 (프레임 간격 33.33ms)
AnimData Duration 단위:  1/60초
포켓몬 전환 크로스페이드: 0.3초
클릭→반응 지연:          0.25초 (250ms, 더블클릭 대기)
Run 지속시간:            10.0초
위치 저장 간격:          30초
드래그 시작 임계값:      3.0 px

=== 이동 ===
Walk 속도 (설정 1~5):   1.0, 1.5, 2.0, 3.0, 4.0 px/frame
Run 속도:               walkSpeed × 2.0
Run 애니메이션 배율:     1.5×

=== 렌더링 ===
스프라이트 기본 스케일:  primaryScreenHeight / 450.0
그림자 너비:            walkWidth × 0.8
그림자 높이:            walkHeight × 0.15
그림자 Y 오프셋:        -walkHeight × 0.05
그림자 알파:            0.25 × currentAlpha
렌더링 마진:            max(walkW, walkH) × 1.5
보간 방식:              nearest-neighbor

=== 경계 ===
랜덤 목표 마진:         40 px
데드존 클램핑 마진:     max(halfWidth, walkHalfHeight)
화면 포함 검사 마진:    20 px

=== 설정 기본값 ===
크기 배율:              100% (범위 50~200)
불투명도:               100% (범위 30~100)
윈도우 레이어:          항상 위 (0)
이동 속도:              3 (범위 1~5)
활동 빈도:              3 (범위 1~5)
수면 진입:              3분 (범위 1~10)
```

---

## 14. 플랫폼별 구현 가이드

이 명세의 로직을 구현할 때, 플랫폼별로 대체해야 하는 핵심 API:

| 기능 | macOS (현재) | Windows | Web |
|------|-------------|---------|-----|
| 투명 오버레이 윈도우 | NSWindow (borderless, clear) | WS_EX_LAYERED + SetLayeredWindowAttributes | position:fixed + pointer-events:none |
| 클릭 패스스루 | ignoresMouseEvents 토글 | WS_EX_TRANSPARENT + WM_NCHITTEST | pointer-events 토글 |
| 시스템 트레이 | MenuBarExtra | Shell_NotifyIcon | Electron: Tray / Tauri: SystemTray |
| 윈도우 레이어 | NSWindow.Level | SetWindowPos (HWND_TOPMOST 등) | CSS z-index + alwaysOnTop |
| 모니터 목록 | NSScreen.screens | EnumDisplayMonitors | screen.getAllDisplays() |
| PNG 로딩/크로핑 | CGImage + CGDataProvider | WIC / GDI+ / stb_image | Image + Canvas |
| 설정 저장 | UserDefaults | Registry / AppData JSON | localStorage / electron-store |
| 자동 시작 | SMAppService | Registry Run key | auto-launch 패키지 |
| 30 FPS 타이머 | DispatchSourceTimer | SetTimer / timeSetEvent | requestAnimationFrame / setInterval |
| 픽셀아트 보간 | interpolationQuality = .none | NearestNeighbor | imageSmoothingEnabled = false |
