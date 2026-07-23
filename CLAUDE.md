# PokePet - macOS 데스크톱 펫

Gen 1-5 포켓몬(649종) 스프라이트를 활용한 macOS 데스크톱 펫 앱.
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
- 스프라이트는 앱 번들에 포함 (~20-30MB)
- portrait 이미지: 포켓몬 선택기에서 초상화 표시용 (PMDCollab portrait/{ID}/Normal.png)

### PetManager (중앙 관리자 싱글턴)
```
PetManager.shared (@Observable)
  ├─ spriteAnimator    (@Observable) — 프레임 제공, 애니메이션 전환
  ├─ stateMachine      (@Observable) — 6개 상태 전환, 위치/방향
  ├─ gameLoop          — DispatchSourceTimer, 위치 업데이트
  ├─ settingsManager   (@Observable) — UserDefaults 저장/로드
  └─ pokemonDataManager — 649종 포켓몬 목록
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
- 화면 가장자리 반사 옵션 토글 제거 (항상 반사 — 포켓몬은 가장자리에서 반대 방향으로 전환)
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
- pokemon_data.json — 649종 포켓몬 데이터 (id, name, gen, types)
- ui-mockup.html — UI 목업 (브라우저에서 열어 확인, portrait 이미지 포함)

## 코딩 규칙
- 주석/커밋 메시지: 한국어
- Swift 표준 네이밍 (camelCase 변수, PascalCase 타입)
- 픽셀아트 렌더링 시 nearest-neighbor 보간 사용
