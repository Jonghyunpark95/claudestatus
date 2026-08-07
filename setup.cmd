@echo off
chcp 65001 >nul 2>&1
rem Windows 딸깍 설치 — 이 파일을 더블클릭하면 끝.
rem   1) Claude Code hook 등록
rem   2) 데스크톱 펫 실행
setlocal
cd /d "%~dp0"

echo Claude 마스코트 설치를 시작합니다.
echo.

rem --- 사전 확인 -------------------------------------------------------------
where node >nul 2>&1
if errorlevel 1 (
  echo [X] Node.js 가 없습니다.
  echo     https://nodejs.org 에서 LTS 버전을 설치한 뒤 다시 실행하세요.
  echo.
  pause
  exit /b 1
)

where curl.exe >nul 2>&1
if errorlevel 1 (
  echo [X] curl.exe 를 찾을 수 없습니다. Windows 10 1803 이상이 필요합니다.
  echo.
  pause
  exit /b 1
)

rem --- 설치 ------------------------------------------------------------------
echo [1/2] Claude Code hook 등록
node install.js
if errorlevel 1 (
  echo.
  echo 설치에 실패했습니다.
  pause
  exit /b 1
)
echo.

echo [2/2] 데스크톱 펫 실행
start "" wscript.exe "%~dp0windows\start.vbs"
echo.

echo ───────────────────────────────────────────
echo  설치 끝. 화면 오른쪽 아래에 캐릭터가 떴습니다.
echo.
echo  ※ 이미 켜져 있는 Claude Code 는 한 번 껐다 켜야
echo     상태가 잡힙니다.
echo.
echo  끄기 : 작업표시줄 오른쪽 트레이 아이콘 클릭 - 종료
echo  설정 : 캐릭터 우클릭 (크기·항상 맨 위·클릭 통과)
echo ───────────────────────────────────────────
echo.
pause
