#!/bin/bash
# 더블클릭하면 마스코트 서버를 켜고 별도 창으로 화면을 띄운다.
cd "$(dirname "$0")" || exit 1

PORT="${MASCOT_PORT:-4573}"
URL="http://127.0.0.1:${PORT}"

# 이미 떠 있으면 재사용
if curl -s -m 1 -o /dev/null "${URL}/healthz"; then
  echo "서버가 이미 실행 중입니다 (${URL})"
else
  echo "서버를 시작합니다…"
  nohup node server.js >> server.log 2>&1 &
  for _ in $(seq 1 20); do
    curl -s -m 1 -o /dev/null "${URL}/healthz" && break
    sleep 0.2
  done
fi

# 크롬/엣지가 있으면 주소창 없는 앱 창으로, 없으면 기본 브라우저로
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
EDGE="/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"

if [ -x "$CHROME" ]; then
  "$CHROME" --app="$URL" --window-size=420,720 \
    --user-data-dir="$HOME/.claude-mascot-window" >/dev/null 2>&1 &
elif [ -x "$EDGE" ]; then
  "$EDGE" --app="$URL" --window-size=420,720 \
    --user-data-dir="$HOME/.claude-mascot-window" >/dev/null 2>&1 &
else
  open "$URL"
fi

echo "열었습니다: $URL"
