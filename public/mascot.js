'use strict';

/* 대시보드(index.html)와 데스크톱 펫(pet.html)이 함께 쓰는 마스코트.
   캐릭터 도트·색·상태 정의는 전부 sprite.js 에 있고(윈도우 버전과 공유),
   여기서는 그걸 SVG 로 그리는 일만 한다.
   sprite.js 가 먼저 로드돼 있어야 한다. */

const GRID = SPRITE.grid;
const PX = SPRITE.px;

// 문자 → CSS 클래스. 실제 색은 sprite.js 의 palette 를 CSS 변수로 넣어서 쓴다.
const PALETTE = { o: 'cl-o', k: 'cl-k', l: 'cl-l', g: 'cl-g', y: 'cl-y' };

(function injectColors() {
  const root = document.documentElement.style;
  for (const [ch, hex] of Object.entries(SPRITE.palette)) root.setProperty(`--cl-${ch}`, hex);
  for (const [state, def] of Object.entries(SPRITE.states)) {
    if (def.body) root.setProperty(`--cl-body-${state}`, def.body);
  }
})();

/** {top, rows} 그리드를 <rect> 묶음으로 바꾼다 */
function paint(block) {
  if (!block) return '';
  const { top = 0, rows = [] } = block;
  let out = '';
  rows.forEach((row, i) => {
    const y = (top + i) * PX;
    for (let x = 0; x < row.length; x++) {
      const cls = PALETTE[row[x]];
      if (!cls) continue;
      // 가로로 이어지는 같은 색은 하나의 rect 로 합친다
      let run = 1;
      while (x + run < row.length && row[x + run] === row[x]) run++;
      out += `<rect class="${cls}" x="${x * PX}" y="${y}" width="${run * PX}" height="${PX}"/>`;
      x += run - 1;
    }
  });
  return out;
}

const group = (cls, block) => `<g class="${cls}">${paint(block)}</g>`;

const MASCOT_SVG = `
<svg class="mascot" viewBox="0 0 ${GRID * PX} ${GRID * PX}" aria-hidden="true">
  <g class="cl-hop">
    ${group('cl-arms', SPRITE.armsUp)}
    <g class="cl-legs">
      ${group('cl-leg-frame cl-leg-a', SPRITE.legsA)}
      ${group('cl-leg-frame cl-leg-b', SPRITE.legsB)}
    </g>
    ${group('cl-body', SPRITE.body)}
    ${Object.keys(SPRITE.faces).map((k) => group(`cl-face cl-face-${k}`, SPRITE.faces[k])).join('')}
  </g>
  ${Object.keys(SPRITE.props).map((k) => group(`cl-prop cl-prop-${k}`, SPRITE.props[k])).join('')}
</svg>`;

/* ---------------------------------------------------------------- 상태 공통 */

const LABEL = {};
const EMOJI = {};
const RANK = {};
for (const [state, def] of Object.entries(SPRITE.states)) {
  LABEL[state] = def.label;
  EMOJI[state] = def.emoji;
  RANK[state] = def.rank;
}

const STALE_MS = 5 * 60 * 1000; // 일하는 중인데 이만큼 조용하면 '조용해요'
const DONE_MS = 3 * 60 * 1000;  // 끝난 지 이만큼 지나면 자러 감

/** 서버가 준 원시 상태를 화면에 그릴 상태로 보정 */
function effectiveState(s, now) {
  if ((s.state === 'working' || s.state === 'thinking') && now - s.updated > STALE_MS) return 'stale';
  if (s.state === 'done' && now - s.since > DONE_MS) return 'idle';
  return s.state;
}

function fmtElapsed(ms) {
  const sec = Math.max(0, Math.floor(ms / 1000));
  if (sec < 60) return `${sec}초`;
  const m = Math.floor(sec / 60);
  if (m < 60) return `${m}분 ${sec % 60}초`;
  return `${Math.floor(m / 60)}시간 ${m % 60}분`;
}

function bubbleFor(s, state) {
  switch (state) {
    case 'waiting':  return s.message || '확인해 주세요!';
    case 'working':  return s.tool ? (s.detail ? `${s.tool} · ${s.detail}` : s.tool) : '작업 중…';
    case 'thinking': return s.lastPrompt || '음… 생각 중';
    case 'done':     return '끝났어요, 봐주세요';
    case 'stale':    return '한참 조용하네요';
    default:         return '';
  }
}
