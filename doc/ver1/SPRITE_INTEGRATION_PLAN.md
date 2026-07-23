# PMDCollab SpriteCollab - 스프라이트 통합 계획서

## 1. 소스 정보

**Repository**: [PMDCollab/SpriteCollab](https://github.com/PMDCollab/SpriteCollab)
**라이선스**: 팬메이드 커뮤니티 프로젝트 (Pokemon Mystery Dungeon 스타일)
**특징**: 8방향 애니메이션, 포켓몬별 개별 폴더, XML 메타데이터 포함

---

## 2. 파일 구조

### 디렉토리 레이아웃
```
sprite/
  0001/                    ← 이상해씨 (Bulbasaur)
    AnimData.xml           ← 프레임 크기, 프레임 수, 방향 등 메타데이터
    Walk-Anim.png          ← Walk 애니메이션 스프라이트 시트
    Walk-Shadow.png        ← Walk 그림자
    Walk-Offsets.png       ← Walk 오프셋 데이터
    Idle-Anim.png          ← Idle 애니메이션
    Sleep-Anim.png         ← Sleep 애니메이션
    Attack-Anim.png        ← 전투 애니메이션
    ... (35+ 종류의 애니메이션)
    0000/                  ← 폼 변형 (Shiny 등)
    0006/                  ← 추가 폼
  0025/                    ← 피카츄 (Pikachu)
    ...
  0150/                    ← 뮤츠 (Mewtwo)
    ...
```

### 파일 명명 규칙
각 애니메이션은 3개 파일로 구성:
- `{Animation}-Anim.png` : 실제 스프라이트 이미지
- `{Animation}-Shadow.png` : 그림자 이미지
- `{Animation}-Offsets.png` : 프레임 오프셋 정보

### 데스크톱 펫 앱에 필요한 애니메이션
| 애니메이션 | 파일명 | 앱 내 용도 |
|---|---|---|
| **Walk** | Walk-Anim.png | 이동 (핵심) |
| **Idle** | Idle-Anim.png | 대기 상태 |
| **Sleep** | Sleep-Anim.png | 수면 상태 |
| Eat | Eat-Anim.png | 반응 (선택) |
| Hop | Hop-Anim.png | 반응 (선택) |
| Hurt | Hurt-Anim.png | 반응 (선택) |

---

## 3. Walk-Anim.png 스프라이트 시트 레이아웃

### 구조: 열(Columns) = 프레임, 행(Rows) = 8방향

```
        Frame 0   Frame 1   Frame 2   Frame 3
Row 0:  Down      Down      Down      Down       ← 아래
Row 1:  DownRight DownRight DownRight DownRight   ← 오른쪽 아래
Row 2:  Right     Right     Right     Right       ← 오른쪽
Row 3:  UpRight   UpRight   UpRight   UpRight     ← 오른쪽 위
Row 4:  Up        Up        Up        Up           ← 위
Row 5:  UpLeft    UpLeft    UpLeft    UpLeft       ← 왼쪽 위
Row 6:  Left      Left      Left      Left         ← 왼쪽
Row 7:  DownLeft  DownLeft  DownLeft  DownLeft     ← 왼쪽 아래
```

### 포켓몬별 프레임 크기 차이 (AnimData.xml로 결정)

| 포켓몬 | Walk-Anim.png 크기 | 프레임 크기 | 프레임 수 |
|---|---|---|---|
| 피카츄 #025 | 128 × 320 px | 32 × 40 px | 4 |
| 이상해씨 #001 | 240 × 320 px | (AnimData 참조) | (AnimData 참조) |
| 뮤츠 #150 | 288 × 448 px | (AnimData 참조) | (AnimData 참조) |

**핵심**: 프레임 크기가 포켓몬마다 다르므로 반드시 AnimData.xml 파싱 필요!

### AnimData.xml 파싱 예시 (피카츄)
```xml
<AnimData>
  <ShadowSize>1</ShadowSize>
  <Anims>
    <Anim>
      <Name>Walk</Name>
      <Index>0</Index>
      <FrameWidth>32</FrameWidth>
      <FrameHeight>40</FrameHeight>
      <Durations>
        <Duration>8</Duration>   <!-- 1/60초 단위 = ~133ms -->
        <Duration>10</Duration>  <!-- ~167ms -->
        <Duration>8</Duration>
        <Duration>10</Duration>
      </Durations>
    </Anim>
  </Anims>
</AnimData>
```

**프레임 추출 공식**:
```
frame_x = frame_index * frame_width
frame_y = direction_index * frame_height
```

---

## 4. 커버리지 통계

### 전체 요약
- **Gen 1-5 전체**: 649종
- **PMDCollab 보유**: 633종 (**97.5%**)
- **누락**: 16종 (Gen 5만 해당)

### 세대별 커버리지
| 세대 | 지역 | 보유/전체 | 커버리지 |
|---|---|---|---|
| Gen 1 | Kanto | 151/151 | **100%** |
| Gen 2 | Johto | 100/100 | **100%** |
| Gen 3 | Hoenn | 135/135 | **100%** |
| Gen 4 | Sinnoh | 107/107 | **100%** |
| Gen 5 | Unova | 140/156 | **89.7%** |

### 누락 포켓몬 16종 (Gen 5)
| # | 이름 | 타입 |
|---|---|---|
| 514 | Simisear | Fire |
| 516 | Simipour | Water |
| 520 | Tranquill | Normal/Flying |
| 522 | Roggenrola | Rock |
| 523 | Boldore | Rock |
| 538 | Sewaddle | Bug/Grass |
| 539 | Swadloon | Bug/Grass |
| 558 | Scrafty | Dark/Fighting |
| 564 | Archen | Rock/Flying |
| 565 | Archeops | Rock/Flying |
| 580 | Klang | Steel |
| 591 | Fraxure | Dragon |
| 592 | Haxorus | Dragon |
| 616 | Larvesta | Bug/Fire |
| 617 | Volcarona | Bug/Fire |
| 626 | Kyurem | Dragon/Ice |

**대안**: 누락 포켓몬은 Pokemon Selector에서 비활성화(N/A) 표시

---

## 5. 방향 매핑 (8방향 → 앱 이동 로직)

### PMDCollab 8방향 인덱스
```
Index 0: Down       (↓)
Index 1: DownRight  (↘)
Index 2: Right      (→)
Index 3: UpRight    (↗)
Index 4: Up         (↑)
Index 5: UpLeft     (↖)
Index 6: Left       (←)
Index 7: DownLeft   (↙)
```

### 앱 이동 방향 결정 로직
```swift
func directionIndex(dx: CGFloat, dy: CGFloat) -> Int {
    let absDx = abs(dx)
    let absDy = abs(dy)

    // 대각선: |dx| ≈ |dy| 인 경우
    let isDiagonal = min(absDx, absDy) > max(absDx, absDy) * 0.4

    if isDiagonal {
        if dx > 0 && dy > 0 { return 1 }  // ↘ DownRight
        if dx > 0 && dy < 0 { return 3 }  // ↗ UpRight
        if dx < 0 && dy < 0 { return 5 }  // ↖ UpLeft
        if dx < 0 && dy > 0 { return 7 }  // ↙ DownLeft
    }

    // 주축 방향 (|dx| > |dy| → 좌/우, |dy| > |dx| → 상/하)
    if absDx > absDy {
        return dx > 0 ? 2 : 6  // → Right : ← Left
    } else {
        return dy > 0 ? 0 : 4  // ↓ Down : ↑ Up
    }
}
```

---

## 6. 배치 다운로드 전략

### 다운로드 스크립트
파일: `download_sprites.sh`

다운로드 대상 (포켓몬당 13파일):
1. `AnimData.xml` - 메타데이터 (필수)
2. `Walk-Anim.png` - 걷기 스프라이트 (필수)
3. `Walk-Shadow.png` - 걷기 그림자 (선택)
4. `Idle-Anim.png` - 대기 스프라이트 (필수)
5. `Idle-Shadow.png` - 대기 그림자 (선택)
6. `Sleep-Anim.png` - 수면 스프라이트 (필수)
7. `Sleep-Shadow.png` - 수면 그림자 (선택)
8. `Eat-Anim.png` - 먹기 반응 (선택, 일부 포켓몬 미보유)
9. `Eat-Shadow.png` - 먹기 그림자 (선택)
10. `Hop-Anim.png` - 점프 반응 (선택, 일부 포켓몬 미보유)
11. `Hop-Shadow.png` - 점프 그림자 (선택)
12. `Hurt-Anim.png` - 피격 반응 (선택, 일부 포켓몬 미보유)
13. `Hurt-Shadow.png` - 피격 그림자 (선택)

### 다운로드 URL 패턴
```
https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/sprite/{ID:04d}/{FileName}
```

### 예상 용량
- 포켓몬당 약 20-50KB (Walk + Idle + Sleep + Eat + Hop + Hurt + Shadow + AnimData)
- 633종 × ~35KB = 약 **20-30MB** 총 용량

---

## 7. macOS 앱 통합 계획

### 리소스 구조 (Xcode 프로젝트)
```
Resources/
  sprites/
    0001/
      AnimData.xml
      Walk-Anim.png, Walk-Shadow.png
      Idle-Anim.png, Idle-Shadow.png
      Sleep-Anim.png, Sleep-Shadow.png
      Eat-Anim.png, Eat-Shadow.png     ← 선택 (일부 포켓몬 미보유)
      Hop-Anim.png, Hop-Shadow.png     ← 선택
      Hurt-Anim.png, Hurt-Shadow.png   ← 선택
    0025/
      ...
  pokemon_data.json
```

### Swift 스프라이트 파싱 흐름
```
1. pokemon_data.json 로드 → 포켓몬 목록
2. 사용자가 포켓몬 선택 (Pokemon Selector UI)
3. sprites/{ID}/AnimData.xml 파싱 → 프레임 크기, 프레임 수, 듀레이션
4. Walk-Anim.png 로드
5. CGImage로 프레임별 crop:
   - frame_rect = CGRect(x: frame_idx * frameW, y: dir_idx * frameH, w: frameW, h: frameH)
6. NSTimer/CADisplayLink로 프레임 순환 애니메이션
7. 화면 크기 기반 스케일링 적용
```

### 핵심 Swift 클래스
- `SpriteAnimator` : AnimData.xml 파싱 + 프레임 추출 + 타이머 애니메이션
- `PokemonPet` : 이동 로직 + 상태 머신 + 방향 계산
- `PokemonSelector` : Gen/Type 필터 UI + 검색
- `SettingsManager` : 크기 조절 + 속도 + UserDefaults 저장

---

## 8. 다음 단계

1. ✅ PMDCollab 구조 분석 완료
2. ✅ 커버리지 확인 (633/649 = 97.5%)
3. ✅ 배치 다운로드 스크립트 생성
4. ⬜ 사용자 Mac에서 download_sprites.sh 실행하여 스프라이트 다운로드
5. ⬜ Xcode 프로젝트 구성 및 Swift 코드 작성
6. ⬜ AnimData.xml 파서 구현
7. ⬜ SpriteAnimator 구현
8. ⬜ 투명 NSWindow + 이동 로직 구현
9. ⬜ Pokemon Selector UI 구현
10. ⬜ 설정 패널 구현
