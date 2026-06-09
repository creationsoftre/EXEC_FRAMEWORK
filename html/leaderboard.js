const lbOverlay = document.getElementById('leaderboardOverlay');
const lbUpdated = document.getElementById('lbUpdated');
const lbNav = document.getElementById('lbNav');
const lbModeTitle = document.getElementById('lbModeTitle');
const lbModeMeta = document.getElementById('lbModeMeta');
const lbTable = document.getElementById('lbTable');
const lbAwards = document.getElementById('lbAwards');
const lbCloseBtn = document.getElementById('lbClose');
const lbResource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'exec_framework';

const lbState = {
  active: false,
  data: null,
  tab: null,
};

function lbEscapeHtml(value) {
  if (value === null || value === undefined) return '';
  return String(value).replace(/[&<>"']/g, (char) => {
    switch (char) {
      case '&': return '&amp;';
      case '<': return '&lt;';
      case '>': return '&gt;';
      case '"': return '&quot;';
      case '\'': return '&#39;';
      default: return char;
    }
  });
}

function lbFormatMetric(value, meta) {
  if (value === null || value === undefined) return '--';
  const fmt = (meta && meta.format) || 'raw';
  const decimals = (meta && typeof meta.decimals === 'number') ? meta.decimals : 2;
  const suffix = (meta && meta.suffix) || '';
  const num = Number(value);

  if (fmt === 'int') {
    if (!Number.isFinite(num)) return `${value}${suffix}`;
    return `${Math.round(num)}${suffix}`;
  }
  if (fmt === 'float') {
    if (!Number.isFinite(num)) return `${value}${suffix}`;
    return `${num.toFixed(decimals)}${suffix}`;
  }
  if (fmt === 'percent') {
    if (!Number.isFinite(num)) return `${value}${suffix}`;
    return `${(num * 100).toFixed(decimals)}%${suffix}`;
  }
  if (fmt === 'time') {
    if (!Number.isFinite(num)) return `${value}${suffix}`;
    const minutes = Math.floor(num / 60);
    const seconds = Math.floor(num % 60);
    return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}${suffix}`;
  }
  return `${value}${suffix}`;
}

function lbFormatAward(value, spec) {
  return lbFormatMetric(value, spec);
}

function lbRenderNav() {
  lbNav.innerHTML = '';
  const data = lbState.data;
  if (!data) return;

  const order = Array.isArray(data.modeOrder) ? data.modeOrder : [];
  order.forEach((key) => {
    const mode = data.perMode ? data.perMode[key] : null;
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'lb-nav-item' + (lbState.tab === key ? ' active' : '');
    const label = mode && mode.label ? mode.label : key.toUpperCase();
    const count = mode && Array.isArray(mode.entries) ? mode.entries.length : 0;
    const minMatches = mode && typeof mode.minMatches === 'number' ? mode.minMatches : 0;
    const pending = mode && mode.filteredCount ? mode.filteredCount : 0;
    let subtitle;
    if (count > 0) {
      subtitle = `${count} qualified`;
      if (pending > 0) {
        subtitle += ` (+${pending} pending)`;
      }
    } else if (pending > 0 && minMatches > 0) {
      subtitle = `${pending} pending | ${minMatches}+ matches`;
    } else if (pending > 0) {
      subtitle = `${pending} pending`;
    } else if (minMatches > 0) {
      subtitle = `Need ${minMatches}+ matches`;
    } else {
      subtitle = 'No data yet';
    }
    button.innerHTML = `<strong>${lbEscapeHtml(label)}</strong><span>${lbEscapeHtml(subtitle)}</span>`;
    button.addEventListener('click', () => lbSetTab(key));
    lbNav.appendChild(button);
  });

  const awardsBtn = document.createElement('button');
  awardsBtn.type = 'button';
  awardsBtn.className = 'lb-nav-item' + (lbState.tab === 'awards' ? ' active' : '');
  awardsBtn.innerHTML = '<strong>Awards</strong><span>Highlights</span>';
  awardsBtn.addEventListener('click', () => lbSetTab('awards'));
  lbNav.appendChild(awardsBtn);
}

function lbRenderMode(modeKey) {
  lbAwards.classList.add('hidden');
  lbTable.classList.remove('hidden');

  const data = lbState.data;
  const mode = data && data.perMode ? data.perMode[modeKey] : null;
  const minMatches = mode && typeof mode.minMatches === 'number' ? mode.minMatches : 0;
  const pending = mode && mode.filteredCount ? mode.filteredCount : 0;

  if (!mode || !Array.isArray(mode.entries) || mode.entries.length === 0) {
    let emptyMessage;
    if (minMatches > 0) {
      emptyMessage = `Need ${minMatches}+ matches to qualify.`;
      if (pending > 0) {
        emptyMessage += ` ${pending} player${pending === 1 ? '' : 's'} awaiting eligibility.`;
      }
    } else {
      emptyMessage = 'No data captured yet.';
    }
    lbTable.innerHTML = `<div class="lb-empty">${lbEscapeHtml(emptyMessage)}</div>`;
    lbModeTitle.textContent = mode ? (mode.label || modeKey) : 'No data';
    const details = [];
    if (minMatches > 0) details.push(`Min ${minMatches} matches`);
    if (pending > 0) details.push(`${pending} pending`);
    if (mode && mode.capturedAt) details.push(`Updated ${mode.capturedAt}`);
    lbModeMeta.textContent = details.join(' | ');
    return;
  }

  const metrics = Array.isArray(mode.metricOrder) ? mode.metricOrder : [];
  let headerRow = '<th>#</th><th>Player</th>';
  metrics.forEach((key) => {
    const meta = mode.metrics ? mode.metrics[key] : null;
    const label = meta && meta.label ? meta.label : key;
    headerRow += `<th>${lbEscapeHtml(label)}</th>`;
  });

  let bodyRows = '';
  mode.entries.forEach((entry, idx) => {
    const rank = entry.rank || (idx + 1);
    const name = entry.name || entry.entityId || 'Unknown';
    let row = `<tr><td>${rank}</td><td>${lbEscapeHtml(name)}</td>`;
    metrics.forEach((key) => {
      const meta = mode.metrics ? mode.metrics[key] : null;
      const value = entry.metrics ? entry.metrics[key] : null;
      row += `<td>${lbEscapeHtml(lbFormatMetric(value, meta))}</td>`;
    });
    row += '</tr>';
    bodyRows += row;
  });

  lbTable.innerHTML = `<table class="lb-grid"><thead><tr>${headerRow}</tr></thead><tbody>${bodyRows}</tbody></table>`;
  lbModeTitle.textContent = mode.label || modeKey;
  const details = [];
  if (mode.entries) details.push(`${mode.entries.length} qualified`);
  if (minMatches > 0) details.push(`Min ${minMatches} matches`);
  if (pending > 0) details.push(`${pending} pending`);
  if (mode.capturedAt) details.push(`Updated ${mode.capturedAt}`);
  lbModeMeta.textContent = details.join(' | ');
}

function lbRenderAwards() {
  const data = lbState.data;
  lbTable.classList.add('hidden');
  lbAwards.classList.remove('hidden');
  lbModeTitle.textContent = 'Awards';
  lbModeMeta.textContent = '';

  const awards = data ? data.awards : null;
  const order = data ? data.awardOrder : null;
  if (!awards || !order || order.length === 0) {
    lbAwards.innerHTML = '<div class="lb-empty">No awards captured yet.</div>';
    return;
  }

  lbAwards.innerHTML = '';
  let hasEntries = false;

  order.forEach((key) => {
    const award = awards[key];
    if (!award) return;

    const card = document.createElement('div');
    card.className = 'lb-award-card';

    const head = document.createElement('div');
    head.className = 'lb-award-head';
    const title = document.createElement('span');
    title.className = 'lb-award-title';
    title.textContent = award.label || key;
    const captured = document.createElement('span');
    captured.className = 'lb-award-captured';
    const minMatches = typeof award.minMatches === 'number' ? award.minMatches : 0;
    const pending = award.filteredCount ? award.filteredCount : 0;
    const metaParts = [];
    if (minMatches > 0) metaParts.push(`${minMatches}+ matches`);
    if (award.capturedAt) metaParts.push(`Updated ${award.capturedAt}`);
    captured.textContent = metaParts.join(' | ');
    head.appendChild(title);
    head.appendChild(captured);
    card.appendChild(head);

    if (award.description) {
      const desc = document.createElement('div');
      desc.className = 'lb-award-desc';
      desc.textContent = award.description;
      card.appendChild(desc);
    }

    const entries = Array.isArray(award.entries) ? award.entries : [];
    if (entries.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'lb-empty';
      if (minMatches > 0) {
        empty.textContent = `Need ${minMatches}+ matches to qualify.`;
        if (pending > 0) {
          empty.textContent += ` ${pending} player${pending === 1 ? '' : 's'} awaiting eligibility.`;
        }
      } else if (pending > 0) {
        empty.textContent = `${pending} player${pending === 1 ? '' : 's'} awaiting eligibility.`;
      } else {
        empty.textContent = 'No data yet.';
      }
      card.appendChild(empty);
    } else {
      hasEntries = true;
      const list = document.createElement('div');
      list.className = 'lb-award-entries';
      entries.forEach((entry) => {
        const item = document.createElement('div');
        item.className = 'lb-award-entry';
        const name = document.createElement('span');
        name.textContent = `#${entry.rank || '-'} ${entry.name || entry.entityId || 'Unknown'}`;
        const value = document.createElement('span');
        value.className = 'value';
        value.textContent = lbFormatAward(entry.value, award);
        if (entry.extra && entry.extra.games) {
          value.textContent += ` (${entry.extra.games} matches)`;
        }
        item.appendChild(name);
        item.appendChild(value);
        list.appendChild(item);
      });
      card.appendChild(list);
      if (pending > 0) {
        const note = document.createElement('div');
        note.className = 'lb-award-desc';
        note.textContent = `${pending} player${pending === 1 ? '' : 's'} awaiting eligibility.`;
        card.appendChild(note);
      }
    }

    lbAwards.appendChild(card);
  });

  if (!hasEntries) {
    lbAwards.innerHTML = '<div class="lb-empty">No awards captured yet.</div>';
  }
}

function lbRender() {
  lbRenderNav();
  if (lbState.tab === 'awards') {
    lbRenderAwards();
  } else if (lbState.tab) {
    lbRenderMode(lbState.tab);
  } else {
    lbTable.classList.remove('hidden');
    lbTable.innerHTML = '<div class="lb-empty">Select a category to view standings.</div>';
    lbModeTitle.textContent = 'EXEC Leaderboards';
    lbModeMeta.textContent = '';
    lbAwards.classList.add('hidden');
  }
}

function lbSetTab(tab) {
  if (lbState.tab === tab) return;
  lbState.tab = tab;
  lbRender();
}

function lbOpen(payload) {
  lbState.data = payload || {};
  lbState.active = true;
  lbOverlay.classList.remove('hidden');
  lbUpdated.textContent = payload && payload.generatedAt ? `Updated: ${payload.generatedAt}` : 'Updated: --';

  let defaultTab = null;
  const order = Array.isArray(payload.modeOrder) ? payload.modeOrder : [];
  for (const key of order) {
    const mode = payload.perMode ? payload.perMode[key] : null;
    if (!defaultTab) defaultTab = key;
    if (mode && Array.isArray(mode.entries) && mode.entries.length > 0) {
      defaultTab = key;
      break;
    }
  }
  if (!defaultTab && payload.awards) defaultTab = 'awards';
  lbState.tab = defaultTab || null;
  lbRender();
}

function lbClose() {
  if (!lbState.active) return;
  lbOverlay.classList.add('hidden');
  lbNav.innerHTML = '';
  lbTable.innerHTML = '';
  lbAwards.innerHTML = '';
  lbAwards.classList.add('hidden');
  lbTable.classList.remove('hidden');
  lbModeTitle.textContent = 'EXEC Leaderboards';
  lbModeMeta.textContent = '';
  lbUpdated.textContent = 'Updated: --';
  lbState.active = false;
  lbState.data = null;
  lbState.tab = null;
}

function lbRequestClose() {
  if (!lbState.active) return;
  fetch(`https://${lbResource}/leaderboardClose`, { method: 'POST' }).catch(() => {});
}

if (lbCloseBtn) {
  lbCloseBtn.addEventListener('click', lbRequestClose);
}

if (lbOverlay) {
  lbOverlay.addEventListener('click', (event) => {
    if (event.target === lbOverlay || event.target.classList.contains('lb-backdrop')) {
      lbRequestClose();
    }
  });
}

window.addEventListener('keydown', (event) => {
  if (!lbState.active) return;
  if (event.key === 'Escape') {
    lbRequestClose();
  }
});

window.addEventListener('message', (event) => {
  const data = event.data;
  if (!data) return;

  if (data.action === 'leaderboard:open') {
    lbOpen(data.payload || {});
  } else if (data.action === 'leaderboard:close') {
    lbClose();
  }
});
