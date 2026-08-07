'use strict';

/* 대시보드(index.html)와 데스크톱 펫(pet.html)이 함께 쓰는 마스코트.
   Claude Code 시작화면의 Clawd 를 참고한 8비트 도트 캐릭터다.
   20x20 그리드에 한 칸 7단위 → viewBox 140x140. */

const GRID = 20;
const PX = 7;

// 문자 → CSS 클래스 (실제 색은 mascot.css 에서 정한다)
const PALETTE = { o: 'cl-o', k: 'cl-k', l: 'cl-l', g: 'cl-g', y: 'cl-y' };

/** 그리드 문자열 배열을 <rect> 묶음으로 바꾼다 */
function paint(rows) {
  let out = '';
  rows.forEach((row, y) => {
    for (let x = 0; x < row.length; x++) {
      const cls = PALETTE[row[x]];
      if (!cls) continue;
      // 가로로 이어지는 같은 색은 하나의 rect 로 합친다
      let run = 1;
      while (x + run < row.length && row[x + run] === row[x]) run++;
      out += `<rect class="${cls}" x="${x * PX}" y="${y * PX}" width="${run * PX}" height="${PX}"/>`;
      x += run - 1;
    }
  });
  return out;
}

// ---------------------------------------------------------------- 몸통

// 몸통 — 가로로 긴 상자 (14칸 x 8칸, 대략 1.75:1). 8~15행.
const BODY = [
  '', '', '', '', '', '', '', '',
  '...oooooooooooooo...',
  '...oooooooooooooo...',
  '...oooooooooooooo...',
  '...oooooooooooooo...',
  '...oooooooooooooo...',
  '...oooooooooooooo...',
  '...oooooooooooooo...',
  '...oooooooooooooo...',
];

// 다리 4개. 두 프레임을 겹쳐 두고 CSS 로 번갈아 보여줘서 걷는 느낌을 낸다. 16~17행.
const LEGS_A = [
  '.....o..o...o..o....',
  '.....o..o...o..o....',
];
const LEGS_B = [
  '.....o..o...o..o....',
  '........o......o....',
];

// ---------------------------------------------------------------- 표정
// 몸통 위에 덮어 그린다. 눈은 9~10행, 입은 11~12행.

// 눈은 10~11행, 입은 13~14행 (몸통 8~15행 안쪽)
const FACES = {
  // 기본 — 점 눈 + 작은 미소
  normal: at(10, [
    '.......k....k.......',
    '.......k....k.......',
    '....................',
    '........k..k........',
    '.........kk.........',
  ]),
  // 웃음 — ^ ^ 눈 + 활짝 벌린 입
  happy: at(10, [
    '.......k....k.......',
    '......k.k..k.k......',
    '....................',
    '........kkkk........',
    '.........kk.........',
  ]),
  // 잠 — 감은 눈
  sleep: at(11, [
    '......kk....kk......',
    '....................',
    '....................',
    '.........kk.........',
  ]),
  // 놀람/질문 — 크게 뜬 눈 + 벌린 입
  alert: at(10, [
    '......kk....kk......',
    '......kk....kk......',
    '....................',
    '.........kk.........',
    '.........kk.........',
  ]),
  // 생각 — 위를 보는 눈 + 다문 입
  think: at(10, [
    '.......k....k.......',
    '....................',
    '....................',
    '....................',
    '........kkk.........',
  ]),
};

// ---------------------------------------------------------------- 소품

// 자는 중 zzz — 오른쪽 위로 떠오른다
const PROP_ZZZ = at(1, [
  '...............lll..',
  '................l...',
  '...............lll..',
  '...........lll......',
  '............l.......',
  '...........lll......',
]);

// 물어볼 게 있을 때 ? — 머리 위
const PROP_Q = at(0, [
  '.........yyy........',
  '........y...y.......',
  '............y.......',
  '..........yy........',
  '..........y.........',
  '....................',
  '..........y.........',
]);

// 다 했을 때 체크 — 머리 위
const PROP_CHECK = at(3, [
  '...............g....',
  '..............g.....',
  '..........g..g......',
  '...........gg.......',
]);

// 일하는 중 반짝이 — 몸통 위 양 모서리에 붙여서 '작업 중' 느낌만 준다
const PROP_SPARK = at(7, [
  '..y..............y..',
]);

// 팔 — 번쩍 든 상태. 대각선으로 꺾고 맨 아랫줄을 몸통에 붙여서
// 뿔이 아니라 '만세한 팔'로 읽히게 한다.
const ARMS_UP = at(6, [
  '.o................o.',
  '..o..............o..',
  '..o..............o..',
]);

// ---------------------------------------------------------------- 조립

/** rows 를 topRow 행부터 시작하도록 빈 줄로 밀어준다 */
function at(topRow, rows) {
  return Array(topRow).fill('').concat(rows);
}

function group(cls, rows) {
  return `<g class="${cls}">${paint(rows)}</g>`;
}

const MASCOT_SVG = `
<svg class="mascot" viewBox="0 0 ${GRID * PX} ${GRID * PX}" aria-hidden="true">
  <g class="cl-hop">
    ${group('cl-arms', ARMS_UP)}
    <g class="cl-legs">
      ${group('cl-leg-frame cl-leg-a', at(16, LEGS_A))}
      ${group('cl-leg-frame cl-leg-b', at(16, LEGS_B))}
    </g>
    ${group('cl-body', BODY)}
    ${Object.keys(FACES).map((k) => group(`cl-face cl-face-${k}`, FACES[k])).join('')}
  </g>
  ${group('cl-prop cl-prop-zzz', PROP_ZZZ)}
  ${group('cl-prop cl-prop-q', PROP_Q)}
  ${group('cl-prop cl-prop-check', PROP_CHECK)}
  ${group('cl-prop cl-prop-spark', PROP_SPARK)}
</svg>`;

/* ---------------------------------------------------------------- 상태 공통 */

const LABEL = {
  idle:     '쉬는 중',
  thinking: '생각하는 중',
  working:  '일하는 중',
  waiting:  '물어볼 게 있어요!',
  done:     '다 했어요',
  stale:    '조용해요',
};

const EMOJI = {
  idle: '😴', thinking: '💭', working: '⚙️',
  waiting: '❓', done: '✅', stale: '😐',
};

// 화면 전체 분위기 / 대표 상태를 고를 때의 우선순위
const RANK = { waiting: 5, working: 4, thinking: 3, done: 2, stale: 1, idle: 0 };

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
