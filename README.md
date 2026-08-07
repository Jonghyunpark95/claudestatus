# Claude 마스코트

Claude Code가 **일하는 중인지 / 쉬는 중인지 / 물어볼 게 있는지**를
바탕화면 위 캐릭터로 보여준다. 다른 모니터 구석에 놔두고 곁눈질로 확인하는 용도.

macOS · Windows 둘 다 된다.

---

# 설치

**1. 내려받기** — 아래 중 편한 쪽

```bash
git clone https://github.com/Jonghyunpark95/claudestatus.git
```

git이 없으면 [ZIP 다운로드](https://github.com/Jonghyunpark95/claudestatus/archive/refs/heads/main.zip) 받아서 압축을 풀면 된다.

**2. 폴더 안에서 자기 운영체제 파일을 더블클릭**

| | 더블클릭할 파일 |
|---|---|
| 🍎 **macOS** | `setup.command` |
| 🪟 **Windows** | `setup.cmd` |

끝. 알아서 설치되고 캐릭터가 화면 오른쪽 아래에 뜬다.

**3. 이미 켜놨던 Claude Code는 한 번 껐다 켠다** (그래야 상태가 잡힌다)

<br>

### 미리 필요한 것

- **Node.js** — 없으면 설치 스크립트가 알려준다. [nodejs.org](https://nodejs.org) 에서 LTS 설치
- **Claude Code**
- macOS만: **Xcode Command Line Tools** — 없으면 설치 스크립트가 설치 창을 띄워준다
- Windows만: **Windows 10 1803 이상** (내장 `curl.exe` 사용)

### 안 될 때

| 증상 | 해결 |
|---|---|
| macOS: "확인되지 않은 개발자" | `ClaudeMascot.app` 우클릭 → **열기** 를 한 번 |
| macOS: 빌드 중 `redefinition of module 'SwiftBridging'` | 아래 [빌드가 안 될 때](#빌드가-안-될-때) 참고 |
| Windows: 스크립트 실행이 차단됨 | `setup.cmd` 우클릭 → 속성 → **차단 해제** 체크 |
| 캐릭터가 계속 자고만 있음 | Claude Code를 껐다 켰는지 확인 |

### 끄기 / 지우기

- **끄기** — macOS는 메뉴바 아이콘, Windows는 트레이 아이콘 클릭 → **종료**
- **지우기** — 폴더에서 `node install.js --uninstall` 실행 후 폴더 삭제

---

# 어떻게 보이나

| 상태 | 캐릭터 | 언제 |
|---|---|---|
| 😴 쉬는 중 | 어두워지고 눈 감음 + `zzz` | 세션 시작 직후, 응답 끝나고 3분 뒤 |
| 💭 생각하는 중 | 눈이 좌우로 움직임 | 프롬프트를 막 보냈을 때 |
| ⚙️ 일하는 중 | 다리를 번갈아 디디며 걷기 + 반짝이 | 도구(Bash/Edit/Read…) 사용 중 |
| ❓ 물어볼 게 있어요 | 팔 번쩍 들고 폴짝폴짝 + 노란 `?` | 권한 요청 / 입력 대기 |
| ✅ 다 했어요 | `^ ^` 웃는 눈 + 초록 체크 | 응답 완료 |
| 😐 조용해요 | 회색 | 일하는 중인데 5분 넘게 아무 이벤트 없음 |

도트 캐릭터라 애니메이션도 한 칸씩 툭툭 끊어 움직인다.

보는 방법은 두 가지다.

| | 형태 | 언제 |
|---|---|---|
| **데스크톱 펫** | 바탕화면 위에 캐릭터만 떠 있는 투명 창 (창틀 없음, 항상 맨 위) | 평소 |
| **대시보드** | 브라우저 창. 세션 카드 여러 개 | 세션이 여러 개일 때 자세히 |

### 조작

- **드래그** — 캐릭터를 잡고 끌면 이동. 위치는 기억한다
- **더블클릭** — 대시보드 열기
- **우클릭 / 트레이(메뉴바) 아이콘** — 크기, 항상 맨 위, 클릭 통과 고정, 위치 초기화, 종료
- **클릭 통과** — 캐릭터 몸통 위에서만 마우스를 받고, 투명한 부분은 아래 창으로 클릭이
  그대로 통과한다. 작업에 안 걸리적거린다

크기는 4단계. 기본은 **아주 작게**다.

| | 크기 | 비고 |
|---|---|---|
| 아주 작게 | 88×101 | 기본. 말풍선은 접히고 캐릭터 + 상태만 |
| 작게 | 132×152 | |
| 보통 | 176×202 | 말풍선에 도구 이름까지 |
| 크게 | 232×264 | |

트레이/메뉴바 아이콘도 현재 상태에 따라 바뀌므로 펫을 안 봐도 상태를 알 수 있다.
로그인할 때 자동 실행하려면 `node install.js --autostart`.

---

# 동작 방식

```
Claude Code ──hook──> mascot-hook ──POST──> server.js(127.0.0.1:4573) ──> 펫 / 대시보드
```

- **외부 통신 없음.** 서버는 `127.0.0.1` 에만 바인딩되고 어디에도 데이터를 보내지 않는다.
- 대화 내용은 저장하지 않는다. 서버가 들고 있는 건 세션별 현재 상태(도구 이름, 프로젝트
  폴더명, 마지막 프롬프트 80자)뿐이고 전부 메모리에만 있다. 디스크에 안 쓴다.
- **외부 패키지 0개.** Electron 안 쓴다.
  - 서버: Node 표준 라이브러리만
  - macOS 펫: Cocoa + WebKit (Swift 한 파일)
  - Windows 펫: PowerShell + WPF (윈도우 기본 내장). WebView2도 안 쓴다
- hook은 타임아웃 1초에 항상 성공으로 끝나므로 **서버가 꺼져 있어도 Claude Code 작업을
  절대 막지 않는다.**
- 이 맥/PC에서 도는 Claude Code는 전부 잡힌다 — VS Code 확장, 터미널, JetBrains,
  데스크톱 앱, 어느 프로젝트 폴더든. (다른 머신에서 도는 건 안 잡힌다)

### 파일

```
setup.command / setup.cmd   딸깍 설치 (macOS / Windows)
server.js                   상태 서버 (SSE 방송, 정적 파일 서빙)
install.js                  hook 설치/제거, 자동 실행 등록
hooks/mascot-hook.sh|.cmd   Claude Code 가 호출하는 hook
public/sprite.js            ★ 캐릭터 도트·색·상태 정의 (맥/윈도우 공용 원본)
public/mascot.js|.css       sprite.js 를 SVG 로 그리기
public/pet.*                데스크톱 펫 화면 (macOS)
public/index.html|app.js|style.css   대시보드 화면
mac/ClaudeMascot.swift      macOS 펫 (투명 창 + 클릭 통과 + 메뉴바)
mac/build.sh                .app 번들 빌드
windows/pet.ps1             Windows 펫 (투명 창 + 클릭 통과 + 트레이)
windows/start.cmd|.vbs      Windows 실행
```

캐릭터를 고치고 싶으면 **`public/sprite.js` 하나만** 바꾸면 맥·윈도우에 동시에 반영된다.
`o` 몸통 / `k` 눈·입 / `y` 노랑 / `g` 초록 / `l` 밝은 회색 / `.` 투명.

### 개발용

- 포트 변경: `MASCOT_PORT=5000 node server.js` (hook·펫도 같은 env를 읽는다)
- 펫 미리보기: `http://127.0.0.1:4573/pet.html?demo=waiting` (`working`/`done`/`idle`/`thinking`)
- 대시보드 미리보기: `http://127.0.0.1:4573/?demo` — 모든 상태를 한 번에
- 가짜 이벤트 주입: `curl "http://127.0.0.1:4573/api/demo?state=waiting"`

---

# 알아둘 것

- Claude Code가 응답을 마치면 `Stop` hook이 오지만, **사용자가 그 뒤로 뭘 하는지는 알 수 없다.**
  그래서 "다 했어요"는 3분 뒤 자동으로 "쉬는 중"으로 넘어간다.
- 세션이 비정상 종료되면 `SessionEnd` 가 안 올 수 있다. 1시간 조용한 세션은 자동으로 사라진다.
- 펫은 세션이 여러 개면 **가장 중요한 상태 하나**만 보여주고(물어보는 중 > 일하는 중 > …),
  오른쪽 위 배지에 전체 세션 수를 띄운다. 자세히 보려면 더블클릭해서 대시보드로.
- Clawd 는 Anthropic 의 캐릭터다. 여기 있는 도트는 다시 찍은 오마주다.

## 빌드가 안 될 때

macOS에서 `setup.command` 실행 중 아래 에러가 나는 경우가 있다.

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
