# PokePet - macOS 데스크톱 펫

Gen 1-9 포켓몬(1025종) + 메가 진화 26종 스프라이트를 활용한 macOS 데스크톱 펫 앱.
스프라이트가 없는 종은 선택기에서 N/A로 표시 (기본 967종 + 메가 26종 = 993종 사용 가능).
PMDCollab SpriteCollab의 8방향 스프라이트 시트 사용.

## 빌드
- Xcode 프로젝트: `poketmon.xcodeproj`
- 타겟: macOS 14.0+
- 언어: Swift

## 아키텍처
- SwiftUI + AppKit 하이브리드 (투명 윈도우는 AppKit, 설정/선택기 UI는 SwiftUI)
- 메뉴바: MenuBarExtra + .window 스타일 (커스텀 SwiftUI 드롭다운)
- Dock 숨김 (LSUIElement = true), 메뉴바 전용 앱
- 게임 루프: DispatchSourceTimer (메인 큐)
- @Observable (Observation 프레임워크) 사용 — ObservableObject 사용하지 않음
- 스프라이트는 앱 번들에 포함 (~90MB)
- portrait 이미지: 포켓몬 선택기에서 초상화 표시용 (PMDCollab portrait/{ID}/Normal.png)

### PetManager (중앙 관리자 싱글턴)
```
PetManager.shared (@Observable)
  ├─ spriteAnimator    (@Observable) — 프레임 제공, 애니메이션 전환
  ├─ stateMachine      (@Observable) — 6개 상태 전환, 위치/방향
  ├─ gameLoop          — DispatchSourceTimer, 위치 업데이트
  ├─ settingsManager   (@Observable) — UserDefaults 저장/로드
  └─ pokemonDataManager — 1025종 포켓몬 목록
```
SwiftUI/AppKit 어디서든 PetManager.shared로 모든 컴포넌트 접근.

## 프로젝트 구조
```
Sprites/          — 스프라이트 폴더 (프로젝트 루트, 폴더 레퍼런스로 번들에 포함)
  {ID}/           — 포켓몬별 스프라이트 (AnimData.xml + Anim/Shadow PNG)
poketmon/
  App/            — 앱 진입점 (AppDelegate)
  Models/         — AnimDataParser, SpriteSheet, SpriteAnimator, PokemonDataManager
  Views/          — SwiftUI 뷰 (선택기, 설정 패널, 메뉴바 드롭다운)
  Services/       — SettingsManager
  Core/           — PetManager, PetStateMachine, GameLoop, ScreenGeometry
  Resources/      — pokemon_data.json, Portraits/
```

## 스프라이트 시스템
- 소스: PMDCollab/SpriteCollab (GitHub)
- 포켓몬당 파일: AnimData.xml + {Walk,Idle,Sleep,Eat,Hop,Hurt}-{Anim,Shadow}.png
- AnimData.xml로 프레임 크기/수/Duration 파싱 → CGImage.cropping으로 프레임 추출
- 8방향 (Row 0~7: Down, DownRight, Right, UpRight, Up, UpLeft, Left, DownLeft)

## 결정 사항
- 화면 가장자리 반사 옵션 토글 제거 (항상 반사 — 포켓몬은 가장자리에 닿으면 목표점을 완전 랜덤으로 재설정)
- 목표점 도달 제한 시간: 거리/속도 기반 동적 계산 (`min((거리 / 속도) × 여유배수 + 5초, 상한)`)
  - 여유배수: 활동 빈도의 걷는 시간 비율에서 산출 (빈도 1: 약 3.4배 ~ 빈도 5: 약 1.4배). Walk 중간에 Idle로 쉬는 시간이 있어 실제 이동 비율이 38~92%로 차이남
  - 상한: `min(수면 타임아웃 × 0.5, 120초)`. 절반 규칙은 목표점 만료 전에 잠들어 기능이 무의미해지는 것을 막고(잠들기 전 최소 2회 재시도 보장), 절대 상한 120초는 수면 타임아웃이 길거나(30분/1시간) "안 잠듦"(무한)일 때 상한이 사라지는 것을 막음
  - 고정 상수는 화면 크기/속도 설정에 따라 적정값이 크게 달라져 부적합. 설정 UI 미노출(교착 방지용 내부 안전장치)
- 메가 진화는 전설/환상과 같은 레벨의 태그가 아니라 **별도 탭**으로 분리. 전설·환상은 종(species)의 희귀도이고 메가는 형태(form) 축이라 축이 다름 — 같은 OR 필터에 섞으면 "전설+메가"가 합집합인지 교집합인지 모호해짐
  - 합성 ID `20000 + 도감번호`로 기존 Int ID 파이프라인(설정 저장/스프라이트 경로/초상화)을 그대로 사용. `baseID` 필드로 원본 도감번호 보존(표시는 `#006`), `gen = 100`으로 세대 탭(1~9)과 분리
  - 공식 메가 26종만 수록. SpriteCollab에는 게임에 없는 팬메이드 "Mega"도 있음(무장조/몰드류/플라엣테/드래캄/지가르데/할비롱/제라오라) — tracker의 `canon` 플래그도 부정확해 수동 선별함
  - 메가 폼에는 Eat 애니메이션이 없음 (선택적 리액션이라 미동작 없음)
- 수면까지(Sleep after) 8단계: 2/3/5/10/15/30분, 1시간, 안 잠듦(Never). 뒤로 갈수록 간격을 넓힌 로그 스케일 — 3분과 4분 차이는 체감되지 않지만 10분과 30분 차이는 체감되므로 균일 간격(구버전 1~10분)이 부적절했음. 데스크톱 펫은 종일 켜두는 앱이고 수면 타이머가 사용자 상호작용 기준이라 상한 10분으로는 대부분의 시간을 자면서 보냄
  - 저장은 분 값 그대로(0 = 안 잠듦), UI 슬라이더는 `sleepTimeoutOptions` 인덱스로 조작 — 구버전 저장값(1, 4분 등)은 가장 가까운 단계로 자동 보정
  - "안 잠듦"은 별도 토글이 아니라 슬라이더 마지막 칸. 토글로 만들면 슬라이더가 무의미해지는 죽은 상태가 생김
- 수면 진입 시 목표점 폐기 (`transition(to: .sleep)`에서 처리 — 모든 진입 경로 커버). 수면은 무기한 상태이므로 깨어나면 주변을 새로 살피는 것이 자연스럽고, 수면 중 모니터 구성이 바뀌어 목표점이 사라진 좌표가 되는 문제도 함께 해결. 드래그는 사용자가 위치를 지정한 것이므로 목표점을 유지하고 제한 시간만 재계산
- 다른 윈도우 위에서만 이동 기능 제거 (Accessibility API 권한 부담)
- Run 상태는 별도 모션 없이 Walk 애니메이션 속도 증가로 처리
- 멀티 모니터: 모니터별 독립 윈도우 (per-screen windows) 방식. macOS가 단일 윈도우의 음수 origin을 강제 보정하므로 union 윈도우 불가
- ScreenGeometry 싱글턴이 모든 모니터 좌표 관리 (unionFrame, dead zone 보정, randomTarget)

## 개발 계획
8단계 순차 개발. 상세 내용은 plan.md 참고.
현재: Phase 6 완료, 멀티 모니터 지원 구현 완료 (Phase 8 Step 8-3 선행 구현)
- Sprites 폴더: 프로젝트 루트 `./Sprites/`로 이동 (fileSystemSynchronizedGroups 충돌 방지)

### 렌더링 스케일 방식
- 각 포켓몬을 **원본 프레임 크기 × spriteScale** 비율로 렌더링 (비율 유지)
- `spriteScale = 화면높이 / 450` (900pt 화면 → 2x 배율)
- 큰 포켓몬은 크게, 작은 포켓몬은 작게 — 원본 크기 차이를 자연스럽게 반영
- 모든 포켓몬을 동일 크기 정사각형에 맞추던 기존 방식에서 변경 (큰 포켓몬 이미지 뭉개짐 방지)
- Walk 프레임 높이를 발(하단) 앵커 기준으로 사용
- renderScale(Walk 대비 다른 애니메이션 비율)은 더 이상 사용하지 않음 — currentFrameSize를 직접 사용

## 참고 문서
- plan.md — 전체 개발 계획 (Phase 1~8)
- SCREEN_SPEC.md — 화면별 상세 스펙
- SPRITE_INTEGRATION_PLAN.md — 스프라이트 구조/파싱/다운로드 상세
- pokemon_data.json — 1025종 포켓몬 데이터 (id, name, nameKo, gen, types, isLegendary, isMythical)
- ui-mockup.html — UI 목업 (브라우저에서 열어 확인, portrait 이미지 포함)

## 코딩 규칙
- 주석/커밋 메시지: 한국어
- Swift 표준 네이밍 (camelCase 변수, PascalCase 타입)
- 픽셀아트 렌더링 시 nearest-neighbor 보간 사용
