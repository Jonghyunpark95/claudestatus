#!/usr/bin/env node
'use strict';

/**
 * Claude Code hook 설치/제거
 *
 *   node install.js              hook 설치 (~/.claude/settings.json)
 *   node install.js --uninstall  hook 제거
 *   node install.js --autostart  hook 설치 + 로그인 시 서버 자동 실행(LaunchAgent)
 *   node install.js --uninstall --autostart  둘 다 제거
 *
 * 기존 설정은 건드리지 않고 mascot 항목만 넣고 뺀다. 쓰기 전에 항상 백업.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const HERE = __dirname;
const HOOK = path.join(HERE, 'hooks', 'mascot-hook.sh');
const SETTINGS = path.join(os.homedir(), '.claude', 'settings.json');
const PLIST_LABEL = 'com.claudemascot.server';
const PLIST = path.join(os.homedir(), 'Library', 'LaunchAgents', `${PLIST_LABEL}.plist`);

const argv = process.argv.slice(2);
const REMOVE = argv.includes('--uninstall');
const AUTOSTART = argv.includes('--autostart');

// PreToolUse/PostToolUse 는 matcher 를 받고, 나머지는 안 받는다
const MATCHED = ['PreToolUse', 'PostToolUse'];
const EVENTS = [
  'SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse',
  'Notification', 'Stop', 'SubagentStop', 'PreCompact', 'SessionEnd',
];

const isMascotHook = (h) =>
  h && typeof h.command === 'string' && h.command.includes('mascot-hook.sh');

function readSettings() {
  if (!fs.existsSync(SETTINGS)) return {};
  const raw = fs.readFileSync(SETTINGS, 'utf8').trim();
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch (e) {
    console.error(`✗ ${SETTINGS} 파싱 실패: ${e.message}`);
    console.error('  JSON이 깨져 있어 안전하게 중단합니다. 파일을 고친 뒤 다시 실행하세요.');
    process.exit(1);
  }
}

/** 기존 mascot hook 항목을 전부 걷어낸다 (재설치 시 중복 방지) */
function stripMascot(hooks) {
  for (const event of Object.keys(hooks)) {
    if (!Array.isArray(hooks[event])) continue;
    hooks[event] = hooks[event]
      .map((entry) => {
        if (!entry || !Array.isArray(entry.hooks)) return entry;
        return { ...entry, hooks: entry.hooks.filter((h) => !isMascotHook(h)) };
      })
      .filter((entry) => !entry || !Array.isArray(entry.hooks) || entry.hooks.length > 0);
    if (hooks[event].length === 0) delete hooks[event];
  }
  return hooks;
}

function installHooks() {
  const settings = readSettings();
  const hooks = stripMascot(settings.hooks && typeof settings.hooks === 'object' ? settings.hooks : {});

  if (!REMOVE) {
    for (const event of EVENTS) {
      const entry = {
        hooks: [{ type: 'command', command: `"${HOOK}" ${event}`, timeout: 5 }],
      };
      if (MATCHED.includes(event)) entry.matcher = '*';
      hooks[event] = [...(hooks[event] || []), entry];
    }
  }

  if (Object.keys(hooks).length > 0) settings.hooks = hooks;
  else delete settings.hooks;

  fs.mkdirSync(path.dirname(SETTINGS), { recursive: true });
  if (fs.existsSync(SETTINGS)) {
    const bak = `${SETTINGS}.mascot-backup`;
    fs.copyFileSync(SETTINGS, bak);
    console.log(`  백업: ${bak}`);
  }
  fs.writeFileSync(SETTINGS, JSON.stringify(settings, null, 2) + '\n');
  console.log(`${REMOVE ? '✓ hook 제거 완료' : '✓ hook 설치 완료'} → ${SETTINGS}`);
}

function plistXml() {
  const node = process.execPath;
  const server = path.join(HERE, 'server.js');
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${node}</string>
    <string>${server}</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${path.join(HERE, 'server.log')}</string>
  <key>StandardErrorPath</key><string>${path.join(HERE, 'server.log')}</string>
</dict>
</plist>
`;
}

function autostart() {
  const quiet = { stdio: 'ignore' };
  if (REMOVE) {
    try { execFileSync('launchctl', ['unload', PLIST], quiet); } catch {}
    if (fs.existsSync(PLIST)) fs.unlinkSync(PLIST);
    console.log('✓ 자동 실행 해제');
    return;
  }
  fs.mkdirSync(path.dirname(PLIST), { recursive: true });
  fs.writeFileSync(PLIST, plistXml());
  try { execFileSync('launchctl', ['unload', PLIST], quiet); } catch {}
  execFileSync('launchctl', ['load', PLIST]);
  console.log(`✓ 자동 실행 등록 (로그인 시 서버 시작) → ${PLIST}`);
}

// ------------------------------------------------------------------ 실행

if (!fs.existsSync(HOOK)) {
  console.error(`✗ hook 스크립트를 찾을 수 없습니다: ${HOOK}`);
  process.exit(1);
}
fs.chmodSync(HOOK, 0o755);

installHooks();
if (AUTOSTART) autostart();

if (!REMOVE) {
  console.log('');
  console.log('다음 단계:');
  console.log('  1) 서버 실행:  node server.js      (또는 ./start.command 더블클릭)');
  console.log('  2) 브라우저:   http://127.0.0.1:4573');
  console.log('  3) 실행 중인 Claude Code 세션은 재시작해야 hook이 적용됩니다.');
}
