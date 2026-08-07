@echo off
rem Claude Code hook -> 마스코트 서버로 상태 전달 (Windows)
rem
rem stdin 으로 들어온 hook JSON 을 그대로 로컬 서버에 넘긴다.
rem 서버가 꺼져 있어도 Claude Code 작업을 절대 막지 않도록
rem 타임아웃을 짧게 두고 항상 성공(exit 0)으로 끝낸다.
rem
rem curl.exe 는 Windows 10 1803 이상에 기본 포함되어 있다.

setlocal
if "%MASCOT_PORT%"=="" (set "PORT=4573") else (set "PORT=%MASCOT_PORT%")

curl.exe -s -m 1 --connect-timeout 1 -X POST ^
  "http://127.0.0.1:%PORT%/hook?event=%~1" ^
  -H "Content-Type: application/json" ^
  --data-binary @- >nul 2>&1

exit /b 0
