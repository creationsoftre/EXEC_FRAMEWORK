const root = document.getElementById('scoreboard');
const modeEl = document.getElementById('modeLabel');
const locationEl = document.getElementById('locationLabel');
const statusBadge = document.getElementById('statusBadge');
const bracketEl = document.getElementById('bracketLabel');
const playersEl = document.getElementById('playersValue');
const countdownEl = document.getElementById('countdownValue');
const countdownMetric = document.getElementById('countdownMetric');
const firstToEl = document.getElementById('firstToValue');
const killsEl = document.getElementById('killsValue');
const rowsEl = document.getElementById('leaderboardRows');
const emptyEl = document.getElementById('leaderboardEmpty');
const winnerEl = document.getElementById('winnerBanner');
const footerEl = document.getElementById('scoreboardFooter');
const goToastEl = document.getElementById('goToast');
const deathPrompt = document.getElementById('deathPrompt');
const deathTitle = document.getElementById('deathTitle');
const deathSubPrefix = document.getElementById('deathSubPrefix');
const deathSubSuffix = document.getElementById('deathSubSuffix');
const deathKey = document.getElementById('deathKey');
const hubHelp = document.getElementById('hubHelp');
const hubHelpTitle = document.getElementById('hubHelpTitle');
const hubHelpRows = document.getElementById('hubHelpRows');
const passiveIndicator = document.getElementById('passiveIndicator');
const passiveTitle = passiveIndicator ? passiveIndicator.querySelector('.passive-title') : null;
const passiveSubtext = document.getElementById('passiveSubtext');
const metaSection = document.getElementById('metaSection');
const leaderboardSection = document.getElementById('leaderboardSection');
const leaderboardHeader = document.getElementById('leaderboardHeader');
const hardcoreMetric = document.getElementById('hardcoreMetric');
const hardcoreValue = document.getElementById('hardcoreValue');

const SCALE_CONFIG = {
  baseWidth: 2560,
  baseHeight: 1440,
  min: 0.42,
  max: 1.0,
};

const STATUS_META = {
  waiting:   { text: 'Waiting for players', className: 'badge-waiting' },
  countdown: { text: 'Match countdown',     className: 'badge-countdown' },
  live:      { text: 'Match live',           className: 'badge-live' },
  ending:    { text: 'Match ending',         className: 'badge-ending' },
  playground:{ text: 'Playground',           className: 'badge-playground' },
  idle:      { text: 'Idle',                 className: 'badge-playground' },
};

let goTimeout = null;
const passiveDefaults = {
  title: passiveTitle ? passiveTitle.textContent : 'Passive Mode',
  subtext: passiveSubtext ? passiveSubtext.textContent : 'Combat disabled',
};
const deathDefaults = {
  title: deathTitle ? deathTitle.textContent : 'You are down',
  prefix: deathSubPrefix ? deathSubPrefix.textContent : 'Press',
  suffix: deathSubSuffix ? deathSubSuffix.textContent : 'to revive',
  keyLabel: deathKey ? deathKey.textContent : 'E',
};
const hubHelpDefaults = {
  title: hubHelpTitle ? hubHelpTitle.textContent : 'Hub Controls',
};

function applyUiColors(payload = {}) {
  const map = {
    scoreboard: {
      text: '--text',
      muted: '--muted',
      accent: '--accent',
      accentSoft: '--accent-soft',
      accentStrong: '--accent-strong',
      live: '--live',
      ending: '--ending',
      waiting: '--waiting',
      rowBg: '--row-bg',
      rowBgSelf: '--row-bg-self',
      bgDark: '--bg-dark',
      bgDarker: '--bg-darker',
      stroke: '--stroke',
      strokeStrong: '--stroke-strong',
    },
    leaderboard: {
      bg: '--lb-bg',
      card: '--lb-card',
      border: '--lb-border',
      text: '--lb-text',
      muted: '--lb-muted',
      accent: '--lb-accent',
      accentSoft: '--lb-accent-soft',
      gold: '--lb-gold',
      strokeStrong: '--lb-stroke-strong',
    },
  };

  Object.entries(map).forEach(([section, vars]) => {
    const source = payload[section];
    if (!source || typeof source !== 'object') return;
    Object.entries(vars).forEach(([key, cssVar]) => {
      if (source[key]) {
        document.documentElement.style.setProperty(cssVar, source[key]);
      }
    });
  });
}

function clampNumber(value, fallback) {
  const num = Number(value);
  return Number.isFinite(num) ? num : fallback;
}

function applyScoreboardScale() {
  const width = window.innerWidth || SCALE_CONFIG.baseWidth;
  const height = window.innerHeight || SCALE_CONFIG.baseHeight;
  const widthRatio = width / SCALE_CONFIG.baseWidth;
  const heightRatio = height / SCALE_CONFIG.baseHeight;

  let scale = Math.min(widthRatio, heightRatio);
  if (!Number.isFinite(scale) || scale <= 0) {
    scale = 1;
  } else {
    scale = Math.min(Math.max(scale, SCALE_CONFIG.min), SCALE_CONFIG.max);
  }

  document.documentElement.style.setProperty('--scoreboard-scale', scale.toFixed(3));
  document.documentElement.style.setProperty('--leaderboard-scale', Math.max(0.72, scale).toFixed(3));
  document.documentElement.style.setProperty('--framework-ui-scale', Math.max(0.58, scale).toFixed(3));
  document.body.classList.toggle('layout-short', height <= 860);
  document.body.classList.toggle('layout-tiny', height <= 760);
  document.body.classList.toggle('layout-narrow', width <= 1500);
  document.body.classList.toggle('layout-compact', height <= 860 || width <= 1500);
}

function clearElement(el) {
  if (!el) return;
  while (el.firstChild) {
    el.removeChild(el.firstChild);
  }
}

function renderTeams(teams, myId, myTeam) {
  teams.forEach((team) => {
    const card = document.createElement('div');
    card.className = 'team-card';
    if (team && team.key && team.key === myTeam) {
      card.classList.add('mine');
    }

    const header = document.createElement('div');
    header.className = 'team-card-header';

    const nameWrap = document.createElement('div');
    const nameSpan = document.createElement('span');
    nameSpan.className = 'team-name';
    nameSpan.textContent = (team && team.label) ? team.label : (team && team.key) ? team.key.toUpperCase() : 'TEAM';
    nameWrap.appendChild(nameSpan);

    const countValue = Number.isFinite(Number(team && team.count)) ? Number(team.count) : 0;
    const maxValueRaw = Number.isFinite(Number(team && team.max)) ? Number(team.max) : 0;
    const maxValue = maxValueRaw > 0 ? maxValueRaw : null;
    const countSpan = document.createElement('span');
    countSpan.className = 'team-count';
    countSpan.textContent = maxValue ? `${countValue}/${maxValue}` : String(countValue);
    nameWrap.appendChild(countSpan);

    header.appendChild(nameWrap);

    const killsSpan = document.createElement('span');
    killsSpan.className = 'team-kills';
    killsSpan.textContent = String(clampNumber(team && team.kills, 0));
    header.appendChild(killsSpan);

    card.appendChild(header);

    const membersWrap = document.createElement('div');
    membersWrap.className = 'team-members';

    if (team && Array.isArray(team.members) && team.members.length > 0) {
      team.members.forEach((member) => {
        const row = document.createElement('div');
        row.className = 'team-member';
        if (member && member.id === myId) {
          row.classList.add('me');
        }

        const info = document.createElement('div');
        info.className = 'member-info';

        const name = document.createElement('span');
        name.className = 'member-name';
        name.textContent = member && member.name ? member.name : 'Unnamed';
        info.appendChild(name);

        const meta = document.createElement('div');
        meta.className = 'member-meta';

        if (member && member.leader) {
          const tag = document.createElement('span');
          tag.className = 'tag leader';
          tag.textContent = 'Leader';
          meta.appendChild(tag);
        }

        if (member && member.host) {
          const tag = document.createElement('span');
          tag.className = 'tag host';
          tag.textContent = 'Host';
          meta.appendChild(tag);
        }

        if (meta.childElementCount > 0) {
          info.appendChild(meta);
        }

        row.appendChild(info);

        const kills = document.createElement('span');
        kills.className = 'member-kills';
        kills.textContent = String(clampNumber(member && member.kills, 0));
        row.appendChild(kills);

        membersWrap.appendChild(row);
      });
    } else {
      const empty = document.createElement('div');
      empty.className = 'team-card-empty';
      empty.textContent = 'Waiting for players...';
      membersWrap.appendChild(empty);
    }

    card.appendChild(membersWrap);
    rowsEl.appendChild(card);
  });
}

function renderLeaderboard(entries, teams, myId, myTeam) {
  clearElement(rowsEl);
  rowsEl.classList.remove('team-grid');
  leaderboardSection.classList.remove('team-mode');
  if (leaderboardHeader) leaderboardHeader.classList.remove('hidden');

  if (Array.isArray(teams) && teams.length > 0) {
    leaderboardSection.classList.add('team-mode');
    rowsEl.classList.add('team-grid');
    if (leaderboardHeader) leaderboardHeader.classList.add('hidden');
    emptyEl.classList.add('hidden');
    renderTeams(teams, myId, myTeam);
    return;
  }

  if (!Array.isArray(entries) || entries.length === 0) {
    emptyEl.classList.remove('hidden');
    return;
  }

  emptyEl.classList.add('hidden');
  const maxRows = Math.min(entries.length, 8);
  for (let i = 0; i < maxRows; i++) {
    const entry = entries[i];
    if (!entry) continue;

    const row = document.createElement('div');
    row.className = 'row';
    if (entry.id === myId) row.classList.add('me');

    const rank = document.createElement('span');
    rank.className = 'col col-rank';
    rank.textContent = String(i + 1);

    const name = document.createElement('span');
    name.className = 'col col-name';
    name.textContent = entry.name || '';

    const kills = document.createElement('span');
    kills.className = 'col col-kills';
    kills.textContent = String(entry.kills ?? 0);

    row.appendChild(rank);
    row.appendChild(name);
    row.appendChild(kills);
    rowsEl.appendChild(row);
  }
}
function updateStatus(statusKey) {
  const info = STATUS_META[statusKey] || STATUS_META.idle;
  statusBadge.className = 'badge ' + (info.className || '');
  statusBadge.textContent = info.text;
}

function formatPlayers(statusKey, players, minPlayers, maxPlayers) {
  const playersInt = clampNumber(players, 0);
  const maxInt = clampNumber(maxPlayers, 0);
  const minInt = clampNumber(minPlayers, 0);
  let text = maxInt > 0 ? `${playersInt}/${maxInt}` : String(playersInt);
  if (statusKey === 'waiting' && minInt > 0) {
    const need = Math.max(0, minInt - playersInt);
    if (need > 0) text += ` (need ${need})`;
  }
  return text;
}

function updateCountdown(statusKey, countdown, endingTimer) {
  const cd = clampNumber(countdown, -1);
  const ending = clampNumber(endingTimer, -1);
  if (statusKey === 'countdown' && cd >= 0) {
    countdownMetric.classList.remove('hidden');
    countdownEl.textContent = `${Math.max(0, Math.floor(cd))}s`;
  } else if (statusKey === 'ending' && ending >= 0) {
    countdownMetric.classList.remove('hidden');
    countdownEl.textContent = `${Math.max(0, Math.floor(ending))}s`;
  } else {
    countdownMetric.classList.add('hidden');
    countdownEl.textContent = '--';
  }
}

function handleWinner(statusKey, winner) {
  if (statusKey === 'ending' && winner) {
    winnerEl.classList.remove('hidden');
    winnerEl.textContent = `Winner: ${winner}`;
  } else {
    winnerEl.classList.add('hidden');
    winnerEl.textContent = '';
  }
}

function updateScoreboard(payload = {}) {
  const visible = !!payload.visible;
  root.classList.toggle('hidden', !visible);
  footerEl.classList.toggle('hidden', !visible);
  if (!visible) {
    document.body.classList.remove('session');
    return;
  }

  const isSession = !!payload.isSession;
  document.body.classList.toggle('session', isSession);

  modeEl.textContent = payload.modeLabel || '-';
  locationEl.textContent = payload.locationLabel || '';
  bracketEl.textContent = payload.bracketLabel || '-';

  const statusKey = payload.status || (isSession ? 'waiting' : 'playground');
  updateStatus(statusKey);

  if (isSession) {
    metaSection.classList.remove('hidden');
    leaderboardSection.classList.remove('hidden');
    if (hardcoreMetric) {
      hardcoreMetric.classList.remove('hidden');
      hardcoreValue.textContent = payload.hardcore ? 'On' : 'Off';
    }

    playersEl.textContent = formatPlayers(statusKey, payload.players, payload.minPlayers, payload.maxPlayers);
    updateCountdown(statusKey, payload.countdown, payload.endingTimer);

    firstToEl.textContent = String(clampNumber(payload.firstTo, 0));
    killsEl.textContent = String(clampNumber(payload.myKills, 0));

    renderLeaderboard(payload.leaderboard, payload.teams, payload.myServerId, payload.myTeam);
    handleWinner(statusKey, payload.winner);
  } else {
    metaSection.classList.add('hidden');
    leaderboardSection.classList.add('hidden');
    handleWinner('idle');
    if (hardcoreMetric) {
      hardcoreMetric.classList.add('hidden');
      hardcoreValue.textContent = 'Off';
    }
    leaderboardSection.classList.remove('team-mode');
    rowsEl.classList.remove('team-grid');
    clearElement(rowsEl);
    emptyEl.classList.add('hidden');
  }
}

function showCenterToast(text, duration) {
  if (goTimeout) {
    clearTimeout(goTimeout);
    goTimeout = null;
  }
  goToastEl.textContent = text || 'GO!';
  goToastEl.classList.remove('hidden');
  const ms = Number(duration) || 1800;
  goTimeout = setTimeout(() => {
    goToastEl.classList.add('hidden');
    goTimeout = null;
  }, ms);
}

function updatePassiveIndicator(payload = {}) {
  if (!passiveIndicator) return;
  const visible = !!payload.visible;
  passiveIndicator.classList.toggle('hidden', !visible);
  if (passiveTitle) {
    passiveTitle.textContent = payload.title || passiveDefaults.title;
  }
  if (passiveSubtext) {
    passiveSubtext.textContent = payload.subtext || passiveDefaults.subtext;
  }
}

function showGoToast(duration) {
  showCenterToast('GO!', duration);
}

function updateDeathPrompt(payload = {}) {
  if (!deathPrompt) return;
  const visible = !!payload.visible;
  deathPrompt.classList.toggle('hidden', !visible);
  if (deathTitle) {
    deathTitle.textContent = payload.title || deathDefaults.title;
  }
  if (deathSubPrefix) {
    deathSubPrefix.textContent = payload.prefix || deathDefaults.prefix;
  }
  if (deathSubSuffix) {
    deathSubSuffix.textContent = payload.suffix || deathDefaults.suffix;
  }
  if (deathKey) {
    deathKey.textContent = payload.keyLabel || deathDefaults.keyLabel;
  }
}

function updateHubHelp(payload = {}) {
  if (!hubHelp) return;
  const visible = !!payload.visible;
  hubHelp.classList.toggle('hidden', !visible);

  if (hubHelpTitle) {
    hubHelpTitle.textContent = payload.title || hubHelpDefaults.title;
  }

  if (!hubHelpRows) return;
  clearElement(hubHelpRows);
  const items = Array.isArray(payload.items) ? payload.items : [];
  items.forEach((item) => {
    if (!item || !item.key || !item.label) return;
    const row = document.createElement('div');
    row.className = 'hub-help-row';

    const key = document.createElement('span');
    key.className = 'hub-help-key';
    key.textContent = String(item.key).toUpperCase();

    const dash = document.createElement('span');
    dash.className = 'hub-help-dash';
    dash.textContent = '-';

    const label = document.createElement('span');
    label.className = 'hub-help-label';
    label.textContent = item.label;

    row.appendChild(key);
    row.appendChild(dash);
    row.appendChild(label);
    hubHelpRows.appendChild(row);
  });
}

window.addEventListener('message', (event) => {
  const data = event.data;
  if (!data) return;

  if (data.action === 'scoreboard:update') {
    updateScoreboard(data.payload);
  } else if (data.action === 'scoreboard:go') {
    showGoToast(data.payload && data.payload.duration);
  } else if (data.action === 'scoreboard:preMatchCountdown') {
    const remaining = data.payload && data.payload.remaining;
    showCenterToast(String(Math.max(1, Math.floor(Number(remaining) || 1))), 900);
  } else if (data.action === 'passive:update') {
    updatePassiveIndicator(data.payload);
  } else if (data.action === 'deathPrompt:update') {
    updateDeathPrompt(data.payload);
  } else if (data.action === 'hubHelp:update') {
    updateHubHelp(data.payload);
  } else if (data.action === 'exec:uiColors') {
    applyUiColors(data.payload);
  }
});

updateScoreboard({ visible: false });
updatePassiveIndicator({ visible: false });
updateDeathPrompt({ visible: false });
updateHubHelp({ visible: false });
applyScoreboardScale();
window.addEventListener('resize', applyScoreboardScale);
if (window.visualViewport) {
  window.visualViewport.addEventListener('resize', applyScoreboardScale);
}

