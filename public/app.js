'use strict';

/* Claude 마스코트 대시보드 — 상태 서버(SSE)를 구독해서 세션마다 캐릭터를 그린다.
   LABEL / RANK / effectiveState / fmtElapsed / bubbleFor / MASCOT_SVG 는 mascot.js 에 있다. */

const stage = document.getElementById('stage');
const emptyEl = document.getElementById('empty');
const connEl = document.getElementById('conn');
const btnSound = document.getElementById('btn-sound');
const btnCompact = document.getElementById('btn-compact');
const tpl = document.getElementById('card-tpl');

let latest = { now: Date.now(), sessions: [] };
const cards = new Map();      // sessionId -> element
const prevState = new Map();  // sessionId -> 직전 렌더 상태 (알림 트리거용)
let alertsOn = localStorage.getItem('mascot.alerts') === '1';
let audioCtx = null;

// 카드 템플릿에 공용 마스코트 SVG 를 심어둔다
tpl.content.querySelector('.mascot-wrap').innerHTML = MASCOT_SVG;

/* ------------------------------------------------------------- 렌더 */

function render() {
  const now = Date.now();
  const list = latest.sessions || [];
  const seen = new Set();
  let top = 'idle';

  for (const s of list) {
    seen.add(s.id);
    const state = effectiveState(s, now);
    if (RANK[state] > RANK[top]) top = state;

    let el = cards.get(s.id);
    if (!el) {
      el = tpl.content.firstElementChild.cloneNode(true);
      cards.set(s.id, el);
      stage.appendChild(el);
    }

    if (el.dataset.state !== state) el.dataset.state = state;

    const bubble = el.querySelector('.bubble-text');
    const text = bubbleFor(s, state);
    bubble.textContent = text;
    bubble.title = text;
    bubble.classList.toggle('show', !!text);

    el.querySelector('.status-text').textContent = LABEL[state];
    el.querySelector('.elapsed').textContent = fmtElapsed(now - s.since);

    const proj = el.querySelector('.project');
    proj.textContent = s.project ? `📁 ${s.project}` : '';
    proj.title = s.cwd || '';

    el.querySelector('.detail').textContent =
      state === 'working' && s.detail ? s.detail : '';

    el.querySelector('.toolcount').textContent =
      s.toolCount ? `도구 ${s.toolCount}회` : '';
    el.querySelector('.model').textContent = s.model || '';

    // 상태 전이 알림
    const before = prevState.get(s.id);
    if (before && before !== state) onTransition(s, before, state);
    prevState.set(s.id, state);
  }

  // 사라진 세션 정리
  for (const [id, el] of cards) {
    if (!seen.has(id)) { el.remove(); cards.delete(id); prevState.delete(id); }
  }

  emptyEl.classList.toggle('show', list.length === 0);
  document.body.dataset.mood = list.length ? top : 'idle';
  updateTitle(top, list.length);
  updateFavicon(top);
}

const TITLE_ICON = { waiting: '❓', working: '⚙️', thinking: '💭', done: '✅', stale: '😴', idle: '😴' };

function updateTitle(top, count) {
  document.title = count
    ? `${TITLE_ICON[top]} ${LABEL[top]} — Claude`
    : 'Claude 마스코트';
}

const FAV_COLOR = {
  waiting: '#f2c14e', working: '#d97757', thinking: '#d97757',
  done: '#63c98d', stale: '#6d6862', idle: '#6d6862',
};
let favLink = null;
let favLast = '';
function updateFavicon(top) {
  if (favLast === top) return;
  favLast = top;
  const c = document.createElement('canvas');
  c.width = c.height = 32;
  const g = c.getContext('2d');
  g.fillStyle = FAV_COLOR[top];
  g.beginPath();
  g.arc(16, 16, 13, 0, Math.PI * 2);
  g.fill();
  if (!favLink) {
    favLink = document.querySelector('link[rel="icon"]') || document.createElement('link');
    favLink.rel = 'icon';
    document.head.appendChild(favLink);
  }
  favLink.href = c.toDataURL();
}

/* ------------------------------------------------------------- 알림 */

function onTransition(s, before, after) {
  if (!alertsOn) return;
  if (after === 'waiting') {
    beep([880, 1175], 0.16);
    notify('❓ 물어볼 게 있어요', `${s.project || 'Claude'} · ${s.message || '입력을 기다리는 중'}`);
  } else if (after === 'done' && before !== 'idle') {
    beep([660, 880], 0.12);
    notify('✅ 작업 완료', `${s.project || 'Claude'} · 확인해 주세요`);
  }
}

function beep(freqs, dur) {
  try {
    audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
    freqs.forEach((f, i) => {
      const t = audioCtx.currentTime + i * dur;
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();
      osc.type = 'sine';
      osc.frequency.value = f;
      gain.gain.setValueAtTime(0.0001, t);
      gain.gain.exponentialRampToValueAtTime(0.14, t + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      osc.connect(gain).connect(audioCtx.destination);
      osc.start(t);
      osc.stop(t + dur + 0.02);
    });
  } catch { /* 소리 못 내도 무시 */ }
}

function notify(title, body) {
  if (!('Notification' in window) || Notification.permission !== 'granted') return;
  try { new Notification(title, { body, tag: 'claude-mascot', renotify: true }); } catch {}
}

function setAlerts(on) {
  alertsOn = on;
  localStorage.setItem('mascot.alerts', on ? '1' : '0');
  btnSound.classList.toggle('on', on);
  btnSound.textContent = on ? '🔔 알림 켬' : '🔕 알림 끔';
  if (on) {
    beep([880], 0.1);
    if ('Notification' in window && Notification.permission === 'default') {
      Notification.requestPermission();
    }
  }
}

btnSound.addEventListener('click', () => setAlerts(!alertsOn));

btnCompact.addEventListener('click', () => {
  const on = !document.body.classList.contains('compact');
  document.body.classList.toggle('compact', on);
  btnCompact.classList.toggle('on', on);
  localStorage.setItem('mascot.compact', on ? '1' : '0');
});

/* ------------------------------------------------------------- 연결 */

let es = null;
let retry = 0;

function connect() {
  es = new EventSource('/events');

  es.onopen = () => {
    retry = 0;
    connEl.textContent = '연결됨';
    connEl.className = 'conn ok';
  };

  es.onmessage = (ev) => {
    try {
      latest = JSON.parse(ev.data);
      render();
    } catch { /* 깨진 프레임 무시 */ }
  };

  es.onerror = () => {
    connEl.textContent = '서버 끊김';
    connEl.className = 'conn bad';
    es.close();
    retry = Math.min(retry + 1, 10);
    setTimeout(connect, 500 * retry);
  };
}

// 세션이 없을 때 보여줄 자는 마스코트 한 마리
(function seedEmptyArt() {
  const host = document.getElementById('empty-art');
  const sample = tpl.content.firstElementChild.cloneNode(true);
  host.appendChild(sample.querySelector('.mascot-wrap'));
})();

/* ?demo 를 붙이면 서버 없이 모든 상태를 한 번에 미리 본다 */
function demoSnapshot() {
  const now = Date.now();
  const mk = (id, over) => ({
    id, state: 'idle', project: '', cwd: '', tool: '', detail: '', message: '',
    lastPrompt: '', model: 'opus-5', toolCount: 0,
    since: now, updated: now, startedAt: now, ...over,
  });
  return {
    now,
    sessions: [
      mk('d1', { state: 'working', project: 'api-server', tool: 'Edit',
                 detail: 'main.go', toolCount: 27, since: now - 96000 }),
      mk('d2', { state: 'waiting', project: 'web-frontend',
                 message: 'Claude가 Bash 실행 권한을 요청했습니다', since: now - 14000 }),
      mk('d3', { state: 'thinking', project: 'docs-site',
                 lastPrompt: '빌드가 왜 실패하는지 찾아줘', since: now - 5000 }),
      mk('d4', { state: 'done', project: 'data-pipeline', toolCount: 51, since: now - 40000 }),
      mk('d5', { state: 'idle', project: 'mobile-app', since: now - 900000 }),
      mk('d6', { state: 'working', project: 'infra-scripts', tool: 'Bash',
                 detail: 'npm run build', toolCount: 8,
                 since: now - 400000, updated: now - 380000 }), // → 조용해요
    ],
  };
}

// 경과 시간·stale 판정을 실시간으로 굴린다
setInterval(render, 1000);

setAlerts(alertsOn);
if (localStorage.getItem('mascot.compact') === '1') {
  document.body.classList.add('compact');
  btnCompact.classList.add('on');
}

if (new URLSearchParams(location.search).has('demo')) {
  latest = demoSnapshot();
  connEl.textContent = '미리보기';
  render();
} else {
  render();
  connect();
}
