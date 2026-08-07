@echo off
chcp 65001 >nul 2>&1
rem 마스코트 서버를 켜고 데스크톱 펫을 띄운다.
rem 콘솔 창 없이 시작하려면 같은 폴더의 start.vbs 를 더블클릭하면 된다.

setlocal
set "HERE=%~dp0"
set "ROOT=%HERE%.."

where node >nul 2>&1
if errorlevel 1 (
  echo Node.js 를 찾을 수 없습니다. https://nodejs.org 에서 설치한 뒤 다시 실행하세요.
  pause
  exit /b 1
)

rem 펫이 서버가 안 떠 있으면 알아서 띄우므로 여기서는 펫만 실행한다
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%HERE%pet.ps1"

exit /b 0
