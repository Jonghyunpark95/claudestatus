#!/bin/bash
# macOS 딸깍 설치 — 이 파일을 더블클릭하거나 ./setup.command 로 실행하면 끝.
#   1) Claude Code hook 등록
#   2) 데스크톱 펫 앱 빌드
#   3) 실행
cd "$(dirname "$0")" || exit 1

echo "Claude 마스코트 설치를 시작합니다."
echo ""

# --- 사전 확인 -------------------------------------------------------------
if ! command -v node >/dev/null 2>&1; then
  echo "✗ Node.js 가 없습니다."
  echo "  https://nodejs.org 에서 LTS 버전을 설치한 뒤 다시 실행하세요."
  echo ""
  read -n 1 -s -r -p "아무 키나 누르면 닫힙니다."
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode Command Line Tools 가 필요합니다. 설치 창을 띄웁니다…"
  xcode-select --install
  echo "  설치가 끝나면 이 파일을 다시 실행하세요."
  echo ""
  read -n 1 -s -r -p "아무 키나 누르면 닫힙니다."
  exit 1
fi

# --- 설치 ------------------------------------------------------------------
echo "[1/3] Claude Code hook 등록"
node install.js || exit 1
echo ""

echo "[2/3] 데스크톱 펫 앱 빌드"
chmod +x mac/build.sh start.command 2>/dev/null
./mac/build.sh || exit 1
echo ""

echo "[3/3] 실행"
open ClaudeMascot.app
echo ""

echo "───────────────────────────────────────────"
echo " 설치 끝. 화면 오른쪽 아래에 캐릭터가 떴습니다."
echo ""
echo " ※ 이미 켜져 있는 Claude Code 는 한 번 껐다 켜야"
echo "    상태가 잡힙니다."
echo ""
echo " 끄기   : 메뉴바 아이콘 클릭 → 종료"
echo " 설정   : 캐릭터 우클릭 (크기·항상 맨 위·클릭 통과)"
echo "───────────────────────────────────────────"
echo ""
read -n 1 -s -r -p "아무 키나 누르면 닫힙니다."
