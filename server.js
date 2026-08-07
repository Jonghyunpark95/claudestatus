#!/usr/bin/env node
'use strict';

/**
 * Claude Mascot - 로컬 상태 서버
 *
 * Claude Code hook 이벤트를 받아서 세션별 상태를 들고 있다가
 * 브라우저(마스코트 화면)로 SSE 방송한다.
 * 의존성 없음. 127.0.0.1 에만 바인딩하므로 외부에서 접근 불가.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.env.MASCOT_PORT || 4573);
const HOST = '127.0.0.1';
const PUBLIC_DIR = path.join(__dirname, 'public');
const FORGET_AFTER_MS = 60 * 60 * 1000; // 1시간 조용하면 카드 제거
const MAX_BODY = 2 * 1024 * 1024;

/** @type {Map<string, object>} sessionId -> session state */
const sessions = new Map();
/** @type {Set<import('http').ServerResponse>} */
const clients = new Set();

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.json': 'application/json; charset=utf-8',
};

// ---------------------------------------------------------------- 상태 갱신

function blankSession(id) {
  return {
    id,
    state: 'idle',
    project: '',
    cwd: '',
    tool: '',
    detail: '',
    message: '',
    lastPrompt: '',
    model: '',
    toolCount: 0,
    since: Date.now(),   // 현재 상태로 바뀐 시각
    updated: Date.now(), // 마지막 이벤트 시각
    startedAt: Date.now(),
  };
}

function truncate(s, n) {
  if (typeof s !== 'string') return '';
  const one = s.replace(/\s+/g, ' ').trim();
  return one.length > n ? one.slice(0, n - 1) + '…' : one;
}

/** tool_input 에서 사람이 읽을 한 줄을 뽑는다 */
function describeTool(name, input) {
  if (!input || typeof input !== 'object') return '';
  const base = (p) => (typeof p === 'string' ? p.split('/').filter(Boolean).pop() || p : '');
  switch (name) {
    case 'Bash':      return truncate(input.description || input.command, 48);
    case 'Read':      return base(input.file_path);
    case 'Edit':
    case 'Write':
    case 'NotebookEdit': return base(input.file_path || input.notebook_path);
    case 'Glob':      return truncate(input.pattern, 40);
    case 'Grep':      return truncate(input.pattern, 40);
    case 'Task':
    case 'Agent':     return truncate(input.description, 40);
    case 'WebFetch':  { try { return new URL(input.url).hostname; } catch { return ''; } }
    case 'WebSearch': return truncate(input.query, 40);
    case 'Skill':     return truncate(input.skill, 40);
    default:          return '';
  }
}

/** hook 이벤트 하나를 세션 상태에 반영. 변화 없으면 false */
function applyEvent(body, queryEvent) {
  const event = body.hook_event_name || queryEvent || '';
  const id = body.session_id || 'unknown';
  if (event === 'SessionEnd') {
    return sessions.delete(id);
  }

  const s = sessions.get(id) || blankSession(id);
  const prevState = s.state;
  const now = Date.now();
  s.updated = now;

  if (body.cwd) {
    s.cwd = body.cwd;
    s.project = body.cwd.split('/').filter(Boolean).pop() || body.cwd;
  }
  if (body.model && typeof body.model === 'string') s.model = body.model;

  switch (event) {
    case 'SessionStart':
      s.state = 'idle';
      s.startedAt = now;
      s.toolCount = 0;
      s.tool = ''; s.detail = ''; s.message = '';
      break;

    case 'UserPromptSubmit':
      s.state = 'thinking';
      s.lastPrompt = truncate(body.prompt, 80);
      s.tool = ''; s.detail = ''; s.message = '';
      break;

    case 'PreToolUse':
      s.state = 'working';
      s.tool = body.tool_name || '';
      s.detail = describeTool(body.tool_name, body.tool_input);
      s.message = '';
      break;

    case 'PostToolUse':
      s.state = 'working';
      s.toolCount += 1;
      s.message = '';
      break;

    case 'Notification':
      s.state = 'waiting';
      s.message = truncate(body.message, 90);
      break;

    case 'PreCompact':
      s.state = 'working';
      s.tool = 'Compact';
      s.detail = '대화 압축 중';
      break;

    case 'SubagentStop':
      s.state = 'working';
      s.tool = 'Agent';
      s.detail = '서브에이전트 완료';
      break;

    case 'Stop':
      s.state = 'done';
      s.tool = ''; s.detail = ''; s.message = '';
      break;

    default:
      break;
  }

  if (s.state !== prevState) s.since = now;
  sessions.set(id, s);
  return true;
}

// ---------------------------------------------------------------- 방송

function snapshot() {
  const cutoff = Date.now() - FORGET_AFTER_MS;
  for (const [id, s] of sessions) if (s.updated < cutoff) sessions.delete(id);
  return {
    now: Date.now(),
    sessions: [...sessions.values()].sort((a, b) => a.startedAt - b.startedAt),
  };
}

function broadcast() {
  const payload = `data: ${JSON.stringify(snapshot())}\n\n`;
  for (const res of clients) {
    try { res.write(payload); } catch { clients.delete(res); }
  }
}

// ---------------------------------------------------------------- HTTP

function serveStatic(req, res, urlPath) {
  const rel = urlPath === '/' ? 'index.html' : decodeURIComponent(urlPath).replace(/^\/+/, '');
  const file = path.join(PUBLIC_DIR, rel);
  if (!file.startsWith(PUBLIC_DIR)) { res.writeHead(403).end('forbidden'); return; }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain' }).end('not found'); return; }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
      'Cache-Control': 'no-cache',
    });
    res.end(data);
  });
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${HOST}:${PORT}`);

  // hook 수신
  if (req.method === 'POST' && url.pathname === '/hook') {
    let raw = '';
    let tooBig = false;
    req.on('data', (chunk) => {
      raw += chunk;
      if (raw.length > MAX_BODY) { tooBig = true; req.destroy(); }
    });
    req.on('end', () => {
      if (tooBig) return;
      let body = {};
      try { body = JSON.parse(raw || '{}'); } catch { body = {}; }
      try {
        if (applyEvent(body, url.searchParams.get('event'))) broadcast();
      } catch (e) {
        console.error('[mascot] hook 처리 실패:', e.message);
      }
      res.writeHead(204).end();
    });
    req.on('error', () => {});
    return;
  }

  // SSE 구독
  if (url.pathname === '/events') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
    });
    res.write('retry: 2000\n\n');
    res.write(`data: ${JSON.stringify(snapshot())}\n\n`);
    clients.add(res);
    req.on('close', () => clients.delete(res));
    return;
  }

  // 폴백 폴링 / 상태 확인
  if (url.pathname === '/api/state') {
    res.writeHead(200, { 'Content-Type': MIME['.json'], 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(snapshot()));
    return;
  }

  if (url.pathname === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'text/plain' }).end('ok');
    return;
  }

  // 테스트용: 가짜 세션 하나 만들기 (?state=working)
  if (url.pathname === '/api/demo') {
    const state = url.searchParams.get('state') || 'working';
    applyEvent({
      session_id: 'demo-session',
      hook_event_name: { working: 'PreToolUse', waiting: 'Notification', done: 'Stop',
                         thinking: 'UserPromptSubmit', idle: 'SessionStart' }[state] || 'PreToolUse',
      cwd: process.cwd(),
      tool_name: 'Bash',
      tool_input: { description: '데모 명령 실행' },
      message: 'Claude가 Bash 실행 권한을 요청했어요',
      prompt: '데모 프롬프트입니다',
    });
    broadcast();
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' }).end(`demo: ${state}`);
    return;
  }

  if (req.method === 'GET') { serveStatic(req, res, url.pathname); return; }
  res.writeHead(405).end();
});

// SSE 연결 유지용 하트비트 + 주기적 재방송(경과시간 갱신)
setInterval(() => {
  for (const res of clients) {
    try { res.write(': ping\n\n'); } catch { clients.delete(res); }
  }
}, 15000).unref();

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`[mascot] 포트 ${PORT} 가 이미 사용 중입니다. 이미 켜져 있는지 확인하세요.`);
    process.exit(1);
  }
  throw err;
});

server.listen(PORT, HOST, () => {
  console.log(`[mascot] http://${HOST}:${PORT} 에서 대기 중`);
});
