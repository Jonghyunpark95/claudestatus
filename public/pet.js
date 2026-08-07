'use strict';

/* 데스크톱 펫 — 여러 세션 중 '가장 중요한' 한 마리를 바탕화면에 띄운다.
   네이티브 껍데기(ClaudeMascot.app)와는 webkit.messageHandlers 로만 대화한다. */

const wrap = document.getElementById('wrap');
const bubbleEl = document.getElementById('bubble');
const bubbleText = document.getElementById('bubble-text');
const captionEl = document.getElementById('caption');
const badgeEl = document.getElementById('badge');

wrap.innerHTML = MASCOT_SVG;

const BUBBLE_HOLD_MS = 4500;   // working/thinking 말풍선은 잠깐만 띄우고 접는다
let latest = { now: Date.now(), sessions: [] };
let bubbleUntil = 0;
let lastBubble = '';
let lastState = '';

/* 네이티브 브리지 (브라우저에서 그냥 열어봐도 죽지 않게 방어) */
const bridge = (name, payload) => {
  try { window.webkit.messageHandlers[name].postMessage(payload); } catch { /* 껍데기 밖 */ }
};

/* ------------------------------------------------------------- 렌더 */

function pickTop(sessions, now) {
  let best = null, bestRank = -1;
  for (const s of sessions) {
    const state = effectiveState(s, now);
    if (RANK[state] > bestRank) { best = { s, state }; bestRank = RANK[state]; }
  }
  return best;
}

function render() {
  const now = Date.now();
  const sessions = latest.sessions || [];
  const top = pickTop(sessions, now) || { s: null, state: 'idle' };
  const { s, state } = top;

  if (document.body.dataset.state !== state) document.body.dataset.state = state;

  // 말풍선: waiting/done 은 계속, 나머지는 내용이 바뀔 때만 잠깐
  const text = s ? bubbleFor(s, state) : '';
  const sticky = state === 'waiting' || state === 'done';
  if (text !== lastBubble || state !== lastState) {
    lastBubble = text;
    bubbleUntil = now + BUBBLE_HOLD_MS;
    bubbleText.textContent = text;
  }
  const showBubble = !!text && (sticky || now < bubbleUntil);
  bubbleEl.classList.toggle('show', showBubble);

  // 캡션: 상태 + 프로젝트. 창이 아주 작으면 프로젝트명은 뺀다 (어차피 잘린다)
  const narrow = window.innerWidth < 115;
  const caption = s
    ? (state === 'waiting' || narrow
        ? LABEL[state]
        : `${LABEL[state]}${s.project ? ' · ' + s.project : ''}`)
    : '';
  captionEl.textContent = caption;
  captionEl.classList.toggle('show', !!caption);

  // 배지: 세션이 둘 이상이면 개수
  badgeEl.textContent = sessions.length > 1 ? String(sessions.length) : '';
  badgeEl.classList.toggle('show', sessions.length > 1);

  // 네이티브에 상태 알림 (메뉴바 아이콘 / 알림용)
  if (state !== lastState) {
    bridge('state', {
      state,
      label: LABEL[state],
      emoji: EMOJI[state],
      project: s ? s.project : '',
      message: s ? s.message : '',
      count: sessions.length,
    });
  }
  lastState = state;

  postHitAreas(showBubble);
}

/* ------------------------------------------------------------- 클릭 통과 영역
   캐릭터 몸통(과 말풍선) 위에서만 마우스를 받고, 나머지 투명한 부분은
   아래 창으로 클릭이 그대로 통과하도록 네이티브에 좌표를 알려준다. */

// 20x20 그리드에서 몸통(3~16열, 8~15행) + 다리(16~17행)가 차지하는 비율
const BODY_BOX = { x0: 0.15, y0: 0.40, x1: 0.85, y1: 0.90 };
let lastHit = '';

function postHitAreas(showBubble) {
  const svg = wrap.querySelector('.mascot');
  if (!svg) return;
  const r = svg.getBoundingClientRect();

  // viewBox 가 정사각(140x140)이라 실제로 그려지는 영역은 박스 안에 들어가는
  // 정사각형이다. 레터박스를 빼고 그 정사각형 기준으로 몸통 위치를 계산한다.
  const side = Math.min(r.width, r.height);
  const left = r.left + (r.width - side) / 2;
  const top = r.top + (r.height - side) / 2;

  const rects = [{
    shape: 'rect',   // 상자 캐릭터라 사각형 판정
    x: left + side * BODY_BOX.x0,
    y: top + side * BODY_BOX.y0,
    w: side * (BODY_BOX.x1 - BODY_BOX.x0),
    h: side * (BODY_BOX.y1 - BODY_BOX.y0),
  }];
  if (showBubble) {
    const b = bubbleEl.getBoundingClientRect();
    if (b.width > 0) rects.push({ shape: 'rect', x: b.left, y: b.top, w: b.width, h: b.height });
  }
  const key = JSON.stringify(rects);
  if (key === lastHit) return;
  lastHit = key;
  bridge('hit', { rects });
}

window.addEventListener('resize', () => { lastHit = ''; render(); });

/* ------------------------------------------------------------- 연결 */

let retry = 0;

function connect() {
  const es = new EventSource('/events');

  es.onopen = () => { retry = 0; document.body.dataset.conn = 'on'; };

  es.onmessage = (ev) => {
    try { latest = JSON.parse(ev.data); render(); } catch { /* 깨진 프레임 무시 */ }
  };

  es.onerror = () => {
    document.body.dataset.conn = 'off';
    es.close();
    retry = Math.min(retry + 1, 10);
    setTimeout(connect, 500 * retry);
  };
}

setInterval(render, 1000); // 경과시간·stale·말풍선 타이머를 굴린다

/* ?demo=waiting 처럼 붙이면 서버 없이 그 상태를 그려본다 (미리보기용) */
const demo = new URLSearchParams(location.search).get('demo');
if (demo !== null) {
  const now = Date.now();
  const state = demo || 'waiting';
  latest = {
    now,
    sessions: [{
      id: 'demo', state, project: 'web-frontend', cwd: '', tool: 'Bash',
      detail: 'npm run build', message: 'Bash 실행 권한을 요청했어요',
      lastPrompt: '빌드가 왜 실패하는지 찾아줘', model: 'opus-5', toolCount: 12,
      since: now - 15000, updated: now, startedAt: now - 60000,
    }],
  };
  document.body.dataset.conn = 'on';
  render();
} else {
  render();
  connect();
}
