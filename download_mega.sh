#!/bin/bash
# PMDCollab SpriteCollab - 메가 진화 폼 다운로드 (공식 26종)
#
# 메가 폼은 sprite/{도감ID}/{폼ID} 하위 폴더에 있다.
# 앱은 포켓몬을 Int ID 하나로 다루므로 20000 + 도감ID를 합성 ID로 부여해
# Sprites/2xxxx/ 폴더에 평탄하게 저장한다. (예: 리자몽 메가X → 20006)
#
# SpriteCollab에는 게임에 없는 팬메이드 "Mega"도 있어(무장조, 몰드류,
# 플라엣테, 드래캄, 지가르데, 할비롱, 제라오라) 공식 메가만 골라 담았다.
# Eat 애니메이션은 메가 폼에 없다 (선택적 리액션이라 없어도 동작).

set -u

BASE_URL="https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/sprite"
PORTRAIT_URL="https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/portrait"
SPRITE_DIR="./Sprites"
PORTRAIT_DIR="./poketmon/Resources/Portraits"

ANIMATIONS=("Walk" "Idle" "Sleep" "Hop" "Hurt")

# "도감ID:폼ID:합성ID" — 공식 메가 진화 중 스프라이트가 완성된 26종
FORMS=(
  "0006:0001:20006"  # 리자몽 (메가X)
  "0065:0001:20065"  # 후딘
  "0094:0001:20094"  # 팬텀
  "0115:0001:20115"  # 캥카
  "0142:0001:20142"  # 프테라
  "0150:0002:20150"  # 뮤츠 (메가Y)
  "0208:0001:20208"  # 강철톤
  "0229:0001:20229"  # 헬가
  "0248:0001:20248"  # 마기라스
  "0282:0001:20282"  # 가디안
  "0302:0001:20302"  # 깜까미
  "0303:0001:20303"  # 입치트
  "0308:0001:20308"  # 요가램
  "0310:0001:20310"  # 썬더볼트
  "0323:0001:20323"  # 폭타
  "0334:0001:20334"  # 파비코리
  "0354:0001:20354"  # 다크펫
  "0359:0001:20359"  # 앱솔
  "0362:0001:20362"  # 얼음귀신
  "0380:0001:20380"  # 라티아스
  "0381:0001:20381"  # 라티오스
  "0384:0001:20384"  # 레쿠쟈
  "0428:0001:20428"  # 이어롭
  "0448:0001:20448"  # 루카리오
  "0475:0001:20475"  # 엘레이드
  "0719:0001:20719"  # 디안시
)

mkdir -p "$SPRITE_DIR" "$PORTRAIT_DIR"

total=${#FORMS[@]}
count=0
failed=()

for entry in "${FORMS[@]}"; do
  IFS=':' read -r dexID formID synthID <<< "$entry"
  count=$((count + 1))
  src="$BASE_URL/$dexID/$formID"
  dest="$SPRITE_DIR/$synthID"
  mkdir -p "$dest"

  echo "[$count/$total] $dexID/$formID → $synthID"

  ok=1
  curl -sfL "$src/AnimData.xml" -o "$dest/AnimData.xml" || ok=0
  for anim in "${ANIMATIONS[@]}"; do
    for kind in Anim Shadow; do
      curl -sfL "$src/$anim-$kind.png" -o "$dest/$anim-$kind.png" || ok=0
    done
  done

  # portrait (선택기 그리드용) — 폼 초상화가 없으면 기본형으로 폴백
  curl -sfL "$PORTRAIT_URL/$dexID/$formID/Normal.png" -o "$PORTRAIT_DIR/$synthID.png" \
    || curl -sfL "$PORTRAIT_URL/$dexID/Normal.png" -o "$PORTRAIT_DIR/$synthID.png" \
    || true

  [ $ok -eq 0 ] && failed+=("$dexID/$formID")
done

echo
if [ ${#failed[@]} -eq 0 ]; then
  echo "완료: ${total}종 모두 다운로드 성공"
else
  echo "실패 ${#failed[@]}종: ${failed[*]}"
  exit 1
fi
