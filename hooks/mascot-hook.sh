#!/bin/sh
# Claude Code hook -> 마스코트 서버로 상태 전달.
#
# stdin 으로 들어온 hook JSON 을 그대로 로컬 서버에 넘긴다.
# 서버가 꺼져 있어도 Claude Code 작업을 절대 막지 않도록
# 타임아웃을 짧게 두고 항상 exit 0 으로 끝낸다.

PORT="${MASCOT_PORT:-4573}"
EVENT="${1:-}"

curl -s -m 1 --connect-timeout 1 \
  -X POST "http://127.0.0.1:${PORT}/hook?event=${EVENT}" \
  -H 'Content-Type: application/json' \
  --data-binary @- >/dev/null 2>&1

exit 0
