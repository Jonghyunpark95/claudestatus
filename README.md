# Claude 마스코트

VS Code에서 Claude Code가 **일하는 중인지 / 쉬는 중인지 / 물어볼 게 있는지**를
다른 모니터에 띄워놓고 곁눈질로 확인하는 도구.

보는 방법이 두 가지다.

| | 형태 | 언제 |
|---|---|---|
| **데스크톱 펫** | 바탕화면 위에 캐릭터만 떠 있는 투명 창 (창틀 없음, 항상 맨 위) | 평소. 구석에 놔두고 곁눈질 |
| **대시보드** | 브라우저 창. 세션 카드 여러 개 | 세션이 여러 개일 때 자세히 |

캐릭터는 Claude Code 시작화면의 **Clawd** 를 참고한 8비트 도트다.

## 상태

| 상태 | 캐릭터 | 언제 |
|---|---|---|
| 😴 쉬는 중 | 어두워지고 눈 감음 + `zzz` | 세션 시작 직후, 응답 끝나고 3분 뒤 |
| 💭 생각하는 중 | 눈이 좌우로 움직임 | 내가 프롬프트를 막 보냈을 때 |
| ⚙️ 일하는 중 | 다리를 번갈아 디디며 걷기 + 반짝이 | 도구(Bash/Edit/Read…) 사용 중 |
| ❓ 물어볼 게 있어요 | 팔 번쩍 들고 폴짝폴짝 + 노란 `?` | 권한 요청 / 입력 대기 |
| ✅ 다 했어요 | `^ ^` 웃는 눈 + 초록 체크 | 응답 완료 |
| 😐 조용해요 | 회색 | 일하는 중인데 5분 넘게 아무 이벤트 없음 |

도트 캐릭터라 애니메이션도 `steps()` 로 한 칸씩 툭툭 끊어 움직인다.

## 동작 방식

```
Claude Code ──hook──> mascot-hook.sh ──POST──> server.js(127.0.0.1:4573) ──SSE──> 펫 / 대시보드
```

- **외부 통신 없음.** 서버는 `127.0.0.1` 에만 바인딩되고 어디에도 데이터를 보내지 않는다.
- 대화 내용은 저장하지 않는다. 서버가 들고 있는 건 세션별 현재 상태(도구 이름, 프로젝트
  폴더명, 마지막 프롬프트 80자)뿐이고 전부 메모리에만 있다. 디스크에 안 쓴다.
- **외부 패키지 0개.** 서버는 Node 표준 라이브러리만, 펫 앱은 Cocoa + WebKit 만 쓴다.
  Electron 안 쓴다.
- hook 스크립트는 `curl -m 1` 에 항상 `exit 0` 이라 **서버가 꺼져 있어도 Claude Code 작업을
  절대 막지 않는다.** (서버 꺼진 상태에서 42ms 만에 exit 0)

## 요구사항

- **macOS 12 이상** — 데스크톱 펫이 Cocoa + WebKit 네이티브 앱이라 현재 macOS 전용이다
- **Node.js 18 이상** — 상태 서버용. `node -v` 로 확인
- **Xcode Command Line Tools** — 펫 앱 빌드용. 없으면 `xcode-select --install`
  (전체 Xcode는 필요 없다)
- **Claude Code**

## 설치

```bash
git clone https://github.com/Jonghyunpark95/claudestatus.git
cd claudestatus

# 1) Claude Code hook 등록 (~/.claude/settings.json, 백업 자동 생성)
node install.js

# 2) 데스크톱 펫 앱 빌드
./mac/build.sh

# 3) 실행
open ClaudeMascot.app
```

설치 후 **실행 중인 Claude Code 세션은 한 번 재시작**해야 hook이 붙는다.
그다음 아무 프로젝트에서나 Claude Code에 말을 걸면 캐릭터가 움직인다.

첫 실행 때 "확인되지 않은 개발자" 경고가 뜨면 앱을 우클릭 → 열기 를 한 번 하거나
시스템 설정 → 개인정보 보호 및 보안 에서 허용하면 된다. (직접 빌드한 앱이라 서명이 없다)

## 실행

```bash
open ClaudeMascot.app     # 데스크톱 펫. 서버가 꺼져 있으면 알아서 띄운다
./start.command           # 대시보드 (브라우저 창)
```

펫 앱은 Dock에 안 뜨고 **메뉴바 아이콘**으로만 산다. 메뉴바 아이콘이 현재 상태 이모지로
바뀌므로 펫을 안 봐도 상태를 알 수 있다.

- **드래그**: 캐릭터를 잡고 끌면 이동. 위치는 기억한다
- **더블클릭**: 대시보드 열기
- **우클릭 / 메뉴바 아이콘**: 크기, 항상 맨 위, 클릭 통과 고정, 위치 초기화, 종료
- **클릭 통과**: 캐릭터 몸통 위에서만 마우스를 받고, 투명한 부분은 아래 창으로 클릭이 그대로
  통과한다. 작업에 안 걸리적거린다

크기는 4단계. 기본은 **아주 작게**다.

| | 크기 | 비고 |
|---|---|---|
| 아주 작게 | 88×101 | 기본. 말풍선은 접히고 캐릭터 + 상태만 |
| 작게 | 132×152 | |
| 보통 | 176×202 | 말풍선에 도구 이름까지 |
| 크게 | 232×264 | |

### 끄기

셋 중 아무거나:

- **메뉴바 아이콘**(😴/⚙️/❓/✅) 클릭 → **종료**
- 캐릭터 위에서 **우클릭** → **종료**
- 터미널에서 `pkill -f ClaudeMascot`

"클릭 통과 고정"을 켜뒀으면 캐릭터가 마우스를 안 받으므로 **메뉴바 아이콘**으로 끄면 된다.

서버까지 같이 내리려면 `pkill -f "node server.js"`. 서버를 내려도 Claude Code 작업에는
아무 영향이 없다(hook이 1초 타임아웃 후 그냥 넘어간다).

로그인할 때 자동 실행하려면 시스템 설정 → 일반 → 로그인 항목에 `ClaudeMascot.app` 추가.
(서버만 자동 실행하려면 `node install.js --autostart`)

## 제거

```bash
node install.js --uninstall              # hook 제거
node install.js --uninstall --autostart  # hook + 서버 자동 실행 둘 다 제거
rm -rf ClaudeMascot.app
```

## 옵션 / 디버깅

- 포트 변경: `MASCOT_PORT=5000 node server.js` (hook 과 빌드 스크립트도 같은 env를 읽는다)
- 펫 미리보기: `http://127.0.0.1:4573/pet.html?demo=waiting` (`working`/`done`/`idle`/`thinking`)
- 대시보드 미리보기: `http://127.0.0.1:4573/?demo` — 모든 상태를 한 번에
- 가짜 이벤트 주입: `curl "http://127.0.0.1:4573/api/demo?state=waiting"`

## 파일

```
server.js              상태 서버 (SSE 방송, 정적 파일 서빙)
install.js             hook 설치/제거, 서버 LaunchAgent 등록
start.command          서버 실행 + 대시보드 창 열기
hooks/mascot-hook.sh   Claude Code 가 호출하는 hook 스크립트
mac/ClaudeMascot.swift 데스크톱 펫 (투명 창 + 클릭 통과 + 메뉴바)
mac/build.sh           .app 번들 빌드
public/mascot.js       도트 캐릭터 정의 (그리드 문자열 → SVG) + 상태 공통 로직
public/mascot.css      캐릭터 색·애니메이션
public/pet.*           데스크톱 펫 화면
public/index.html,app.js,style.css   대시보드 화면
```

캐릭터를 고치고 싶으면 `public/mascot.js` 의 그리드 문자열만 바꾸면 된다.
`o` 몸통 / `k` 눈·입 / `y` 노랑 / `g` 초록 / `l` 밝은 회색 / `.` 투명.

## 알아둘 것

- Claude Code가 응답을 마치면 `Stop` hook이 오지만, **사용자가 그 뒤로 뭘 하는지는 알 수 없다.**
  그래서 "다 했어요"는 3분 뒤 자동으로 "쉬는 중"으로 넘어간다.
- 세션이 비정상 종료되면 `SessionEnd` 가 안 올 수 있다. 1시간 조용한 카드는 자동으로 사라진다.
- 펫은 세션이 여러 개면 **가장 중요한 상태 하나**만 보여주고(물어보는 중 > 일하는 중 > …),
  오른쪽 위 배지에 전체 세션 수를 띄운다. 자세히 보려면 더블클릭해서 대시보드로.
- Clawd 는 Anthropic 의 캐릭터다. 여기 있는 도트는 다시 찍은 오마주다.

## 빌드가 안 될 때

`./mac/build.sh` 에서 아래처럼 `SwiftBridging` 모듈이 중복 정의됐다는 에러가 나는 경우가 있다.

```
error: redefinition of module 'SwiftBridging'
error: could not build Objective-C module 'Cocoa'
```

Command Line Tools 를 여러 번 업데이트한 맥에서 옛날 `module.modulemap` 이 지워지지 않고
남아, 새로 설치된 `bridging.modulemap` 과 같은 모듈을 두 번 선언해서 생기는 문제다.
이 상태에서는 `import Cocoa` 만 해도 모든 Swift 빌드가 실패한다. 옛날 파일을 비활성화하면 된다.

```bash
D=/Library/Developer/CommandLineTools/usr/include/swift
diff "$D/module.modulemap" "$D/bridging.modulemap"          # 저작권 연도 빼고 같은지 확인
sudo mv "$D/module.modulemap" "$D/module.modulemap.disabled"
```

되돌리려면 원래 이름으로 다시 `sudo mv` 하면 된다.
