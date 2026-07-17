(() => {
  const state = {
    plugins: [],
    actions: [],
    playbooks: [],
    currentPlugin: null,
    currentView: 'home',
    paletteIndex: 0,
    paletteItems: [],
    lastPlainText: '',
  };

  const $ = (sel) => document.querySelector(sel);
  const output = $('#output');
  const view = $('#view');
  const pluginNav = $('#pluginNav');
  const healthPill = $('#healthPill');
  const targetInput = $('#targetInput');
  const palette = $('#palette');
  const paletteInput = $('#paletteInput');
  const paletteList = $('#paletteList');

  const iconMap = {
    cpu: '◈', gears: '⚙', activity: '⌃', harddrive: '▤', network: '⌁',
    radar: '◎', box: '▣', users: '♟', scroll: '☰', shield: '⬡',
    camera: '◉', id: '◇',
  };

  const labelMap = {
    Hostname: 'Hostname',
    FQDN: 'FQDN',
    User: 'User',
    OS: 'Operating system',
    OSVersion: 'OS version',
    Architecture: 'Architecture',
    PowerShell: 'PowerShell',
    Edition: 'Edition',
    LastBoot: 'Last boot',
    ProcessCount: 'Processes',
    CollectedAt: 'Collected',
    TimeZone: 'Time zone',
    Culture: 'Culture',
    UtcNow: 'UTC now',
    LocalNow: 'Local time',
    TotalGB: 'Total RAM',
    FreeGB: 'Free RAM',
    Manufacturer: 'Manufacturer',
    Model: 'Model',
    Processors: 'Processors',
    LogicalCPUs: 'Logical CPUs',
    Domain: 'Domain',
    BiosSerial: 'BIOS serial',
  };

  async function api(path, options = {}) {
    const res = await fetch(path, {
      headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
      ...options,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
    return data;
  }

  function toast(msg) {
    const el = $('#toast');
    el.textContent = msg;
    el.classList.remove('hidden');
    clearTimeout(toast._t);
    toast._t = setTimeout(() => el.classList.add('hidden'), 2800);
  }

  function escapeHtml(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function humanizeKey(key) {
    if (labelMap[key]) return labelMap[key];
    return String(key)
      .replace(/_/g, ' ')
      .replace(/([a-z])([A-Z])/g, '$1 $2')
      .replace(/\b\w/g, (c) => c.toUpperCase());
  }

  function formatValue(val) {
    if (val == null || val === '') return '—';
    if (typeof val === 'boolean') return val ? 'Yes' : 'No';
    if (typeof val === 'object') return null;
    return String(val);
  }

  function prettyTime(iso) {
    if (!iso) return '—';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return String(iso);
    return d.toLocaleString();
  }

  function pick(obj, ...keys) {
    for (const k of keys) {
      if (obj && obj[k] != null) return obj[k];
    }
    return undefined;
  }

  function unwrap(payload) {
    if (!payload || typeof payload !== 'object') return { meta: {}, data: payload };
    const plugin = pick(payload, 'Plugin', 'plugin');
    const action = pick(payload, 'Action', 'action');
    const target = pick(payload, 'Target', 'target');
    const timestamp = pick(payload, 'Timestamp', 'timestamp');
    const data = pick(payload, 'Data', 'data') ?? payload;
    return { meta: { plugin, action, target, timestamp }, data };
  }

  function badge(text, kind = '') {
    return `<span class="badge ${kind}">${escapeHtml(text)}</span>`;
  }

  function kvGrid(entries) {
    const rows = entries
      .filter(([, v]) => v != null && v !== '')
      .map(([k, v]) => `<div class="k">${escapeHtml(humanizeKey(k))}</div><div class="v">${escapeHtml(formatValue(v) ?? String(v))}</div>`)
      .join('');
    return rows ? `<div class="kv-grid">${rows}</div>` : '';
  }

  function section(title, html) {
    if (!html) return '';
    return `<div class="out-section"><h5>${escapeHtml(title)}</h5>${html}</div>`;
  }

  function tableFromRows(rows, columns) {
    if (!rows?.length) return '<div class="out-empty">No rows returned.</div>';
    const cols = columns || Object.keys(rows[0] || {}).filter((k) => typeof rows[0][k] !== 'object');
    if (!cols.length) return '<div class="out-empty">No displayable columns.</div>';
    const head = cols.map((c) => `<th>${escapeHtml(humanizeKey(c))}</th>`).join('');
    const body = rows.map((row) => {
      const cells = cols.map((c) => {
        let v = row[c];
        if (v && typeof v === 'object') v = JSON.stringify(v);
        return `<td>${escapeHtml(formatValue(v) ?? '—')}</td>`;
      }).join('');
      return `<tr>${cells}</tr>`;
    }).join('');
    return `<div class="out-table-wrap"><table class="out-table"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
  }

  function meterList(volumes) {
    return volumes.map((v) => {
      const pct = Number(v.UsedPct ?? 0);
      const cls = pct >= 90 ? 'hot' : pct >= 80 ? 'warn' : '';
      const free = v.FreeGB != null ? `${v.FreeGB} GB free` : '';
      const used = v.UsedGB != null ? `${v.UsedGB} / ${v.TotalGB ?? '?'} GB` : '';
      return `
        <div class="meter">
          <div class="meter-top">
            <strong>${escapeHtml(v.Name || v.Root || 'Volume')}</strong>
            <span>${escapeHtml(used)}${free ? ` · ${escapeHtml(free)}` : ''} · ${pct}%</span>
          </div>
          <div class="meter-track"><div class="meter-fill ${cls}" style="width:${Math.min(100, Math.max(0, pct))}%"></div></div>
        </div>`;
    }).join('');
  }

  function renderReport({ title, subtitle, badges = [], bodyHtml, plainText }) {
    state.lastPlainText = plainText || `${title}\n${subtitle || ''}`;
    output.innerHTML = `
      <div class="out-report">
        <div class="out-banner">
          <div>
            <h4>${escapeHtml(title)}</h4>
            ${subtitle ? `<p class="out-sub">${escapeHtml(subtitle)}</p>` : ''}
          </div>
          <div class="out-badges">${badges.join('')}</div>
        </div>
        ${bodyHtml}
      </div>`;
    output.scrollTop = 0;
  }

  function setLoading(label) {
    state.lastPlainText = label;
    output.innerHTML = `
      <div class="out-loading">
        <div class="out-spinner" aria-hidden="true"></div>
        <div>${escapeHtml(label)}</div>
      </div>`;
  }

  function setError(message) {
    renderReport({
      title: 'Something went wrong',
      subtitle: prettyTime(new Date().toISOString()),
      badges: [badge('Error', 'bad')],
      bodyHtml: `<div class="msg-callout bad">${escapeHtml(message)}</div>`,
      plainText: message,
    });
  }

  function formatGenericObject(obj, depth = 0) {
    if (obj == null) return '<div class="out-empty">No data.</div>';
    if (Array.isArray(obj)) {
      if (!obj.length) return '<div class="out-empty">Empty list.</div>';
      if (typeof obj[0] === 'object') return tableFromRows(obj);
      return `<ul>${obj.map((i) => `<li>${escapeHtml(String(i))}</li>`).join('')}</ul>`;
    }
    if (typeof obj !== 'object') return `<div class="msg-callout">${escapeHtml(String(obj))}</div>`;

    const scalar = [];
    const nested = [];
    for (const [k, v] of Object.entries(obj)) {
      if (v == null) continue;
      if (typeof v !== 'object') scalar.push([k, v]);
      else nested.push([k, v]);
    }

    let html = scalar.length ? section('Details', kvGrid(scalar)) : '';
    for (const [k, v] of nested) {
      if (Array.isArray(v) && v.length && typeof v[0] === 'object') {
        html += section(humanizeKey(k), tableFromRows(v));
      } else if (Array.isArray(v)) {
        html += section(humanizeKey(k), `<div class="msg-callout">${escapeHtml(v.join(', '))}</div>`);
      } else if (depth < 2) {
        html += section(humanizeKey(k), formatGenericObject(v, depth + 1));
      }
    }
    return html || `<pre class="pretty-fallback">${escapeHtml(JSON.stringify(obj, null, 2))}</pre>`;
  }

  function formatByShape(meta, data) {
    const plugin = (meta.plugin || '').toLowerCase();
    const action = (meta.action || '').toLowerCase();
    const target = meta.target || 'localhost';
    const when = prettyTime(meta.timestamp);

    // Health / boot
    if (data?.status === 'ok' && data.version) {
      return {
        title: 'LumenOps is online',
        subtitle: `${data.hostname || ''} · PowerShell ${data.psVersion || ''}`.trim(),
        badges: [badge(`v${data.version}`, 'ok'), badge(`${data.plugins} plugins`, 'info'), badge(data.platform || 'host', 'info')],
        bodyHtml: section('Session', kvGrid([
          ['Hostname', data.hostname],
          ['Platform', data.platform],
          ['PowerShell', data.psVersion],
          ['Plugins loaded', data.plugins],
          ['Started', prettyTime(data.startedAt)],
        ])),
        plainText: `LumenOps online on ${data.hostname}`,
      };
    }

    if (data?.error && !data.Data) {
      return {
        title: 'Error',
        subtitle: when,
        badges: [badge('Failed', 'bad')],
        bodyHtml: `<div class="msg-callout bad">${escapeHtml(data.error)}</div>`,
        plainText: data.error,
      };
    }

    // Connectivity probe
    if (data?.checks && Array.isArray(data.checks)) {
      const passed = data.passed ?? data.checks.filter((c) => c.ok).length;
      const total = data.total ?? data.checks.length;
      const rows = data.checks.map((c) => `
        <div class="check-row">
          <span class="status-dot ${c.ok ? 'good' : 'bad'}"></span>
          <div><div class="name">${escapeHtml(c.name)}</div></div>
          <div class="detail">${escapeHtml(c.detail || (c.ok ? 'OK' : 'Fail'))}</div>
        </div>`).join('');
      return {
        title: `Connectivity probe · ${data.host || target}`,
        subtitle: when,
        badges: [
          badge(data.score || `${passed}/${total}`, passed === total ? 'ok' : 'warn'),
          badge(`${passed} passed`, 'ok'),
          badge(`${total - passed} failed`, total - passed ? 'bad' : 'info'),
        ],
        bodyHtml: section('Checks', `<div class="check-list">${rows}</div>`),
        plainText: `Probe ${data.host}: ${data.score}`,
      };
    }

    // Ping
    if (typeof data?.online === 'boolean' && data.host && data.latencyMs != null && !data.checks) {
      return {
        title: `Ping · ${data.host}`,
        subtitle: when,
        badges: [badge(data.online ? 'Online' : 'Offline', data.online ? 'ok' : 'bad'), badge(`${data.latencyMs} ms`, 'info')],
        bodyHtml: section('Result', kvGrid([
          ['Host', data.host],
          ['Reachable', data.online ? 'Yes' : 'No'],
          ['Latency', `${data.latencyMs} ms`],
        ])),
        plainText: `Ping ${data.host}: ${data.online ? 'online' : 'offline'} (${data.latencyMs} ms)`,
      };
    }

    // Disk usage / pressure
    if (Array.isArray(data?.volumes)) {
      const isPressure = data.alertCount != null || data.thresholdPct != null;
      return {
        title: isPressure ? 'Storage pressure' : 'Disk usage',
        subtitle: data.message || when,
        badges: isPressure
          ? [badge(data.message || `${data.alertCount} alerts`, data.alertCount ? 'warn' : 'ok')]
          : [badge(`${data.volumes.length} volumes`, 'info')],
        bodyHtml: data.volumes.length
          ? section('Volumes', meterList(data.volumes))
          : `<div class="msg-callout">${escapeHtml(data.message || 'No volumes to show.')}</div>`,
        plainText: data.message || `Disk: ${data.volumes.length} volumes`,
      };
    }

    // Software
    if (Array.isArray(data?.items) && (plugin === 'software' || data.title === 'Installed software' || data.count != null && data.items[0]?.Publisher != null)) {
      const cols = ['Name', 'Version', 'Publisher', 'Source'].filter((c) => data.items.some((i) => i[c] != null));
      return {
        title: data.title || 'Installed software',
        subtitle: `${data.count ?? data.items.length} applications · ${data.platform || target}`,
        badges: [badge(`${data.count ?? data.items.length} apps`, 'info')],
        bodyHtml: section('Applications', tableFromRows(data.items, cols.length ? cols : undefined)),
        plainText: `Software: ${data.count ?? data.items.length} applications`,
      };
    }

    // Services list / auto health
    if (Array.isArray(data?.items) && (plugin === 'services' || data.items[0]?.StartType != null || data.unhealthy != null)) {
      if (data.unhealthy != null || data.message) {
        return {
          title: 'Automatic service health',
          subtitle: data.message || when,
          badges: [badge(data.unhealthy ? `${data.unhealthy} unhealthy` : 'Healthy', data.unhealthy ? 'warn' : 'ok')],
          bodyHtml: data.items?.length
            ? section('Not running (Automatic)', tableFromRows(data.items, ['Name', 'DisplayName', 'Status', 'StartType']))
            : `<div class="msg-callout">${escapeHtml(data.message || 'All Automatic services are running.')}</div>`,
          plainText: data.message || 'Service health',
        };
      }
      return {
        title: 'Services',
        subtitle: `${data.count ?? data.items.length} services on ${target}`,
        badges: [badge(`${data.count ?? data.items.length} listed`, 'info')],
        bodyHtml: section('Service list', tableFromRows(data.items, ['Name', 'DisplayName', 'Status', 'StartType'])),
        plainText: `Services: ${data.count ?? data.items.length}`,
      };
    }

    // Processes
    if (Array.isArray(data?.items) && (plugin === 'processes' || data.items[0]?.WS_MB != null || data.items[0]?.Id != null)) {
      return {
        title: action === 'top' ? 'Top processes' : 'Processes',
        subtitle: `${data.items.length} shown · ${target}`,
        badges: [badge(`${data.items.length} processes`, 'info')],
        bodyHtml: section('Process list', tableFromRows(data.items)),
        plainText: `Processes: ${data.items.length}`,
      };
    }

    // Network adapters
    if (Array.isArray(data?.adapters)) {
      return {
        title: 'Network adapters',
        subtitle: `${data.adapters.length} interfaces · ${target}`,
        badges: [badge(`${data.adapters.length} adapters`, 'info')],
        bodyHtml: section('Interfaces', tableFromRows(data.adapters)),
        plainText: `Network: ${data.adapters.length} adapters`,
      };
    }

    if (Array.isArray(data?.listeners)) {
      return {
        title: 'Listening ports',
        subtitle: `${data.listeners.length} listeners · ${target}`,
        badges: [badge(`${data.listeners.length} ports`, 'info')],
        bodyHtml: section('TCP listeners', tableFromRows(data.listeners)),
        plainText: `Listeners: ${data.listeners.length}`,
      };
    }

    // Security pulse
    if (Array.isArray(data?.signals)) {
      const rows = data.signals.map((s) => `
        <div class="check-row">
          <span class="status-dot ${s.status === 'good' ? 'good' : s.status === 'warn' ? 'warn' : 'info'}"></span>
          <div><div class="name">${escapeHtml(s.name)}</div></div>
          <div class="detail">${escapeHtml(s.detail || s.status)}</div>
        </div>`).join('');
      return {
        title: 'Security pulse',
        subtitle: prettyTime(data.checkedAt) || when,
        badges: [badge(`${data.signals.length} signals`, 'info')],
        bodyHtml: section('Signals', `<div class="check-list">${rows}</div>`),
        plainText: 'Security pulse complete',
      };
    }

    // Password
    if (data?.password) {
      return {
        title: 'Generated password',
        subtitle: data.note || 'Copy now — not stored in activity log.',
        badges: [badge(`${data.length || data.password.length} chars`, 'ok')],
        bodyHtml: `<div class="password-box">${escapeHtml(data.password)}</div>`,
        plainText: data.password,
      };
    }

    // Event log
    if (plugin === 'eventlog' || (Array.isArray(data?.items) && data.items[0]?.LevelDisplayName)) {
      return {
        title: 'Recent errors & warnings',
        subtitle: data.message || data.source || target,
        badges: [badge(`${data.items?.length || 0} events`, data.items?.length ? 'warn' : 'ok')],
        bodyHtml: data.items?.length
          ? section('Events', tableFromRows(data.items, ['TimeCreated', 'Id', 'LevelDisplayName', 'ProviderName', 'Message']))
          : `<div class="msg-callout">${escapeHtml(data.message || data.error || 'No events returned.')}</div>`,
        plainText: `Event log: ${data.items?.length || 0} events`,
      };
    }

    // Sessions
    if (Array.isArray(data?.sessions)) {
      return {
        title: 'Signed-in sessions',
        subtitle: `${data.sessions.length} entries · ${target}`,
        badges: [badge(`${data.sessions.length} sessions`, 'info')],
        bodyHtml: section('Sessions', tableFromRows(data.sessions)),
        plainText: `Sessions: ${data.sessions.length}`,
      };
    }

    // Inventory snapshot / identity
    if (plugin === 'inventory' || data?.Hostname || data?.hostname) {
      const host = data.Hostname || data.hostname || target;
      const drives = data.Drives || data.drives || [];
      const hw = data.Hardware || data.hardware;
      let body = section('Host', kvGrid(Object.entries(data).filter(([, v]) => typeof v !== 'object')));
      if (hw && typeof hw === 'object') body += section('Hardware', kvGrid(Object.entries(hw)));
      if (drives.length) {
        const withPct = drives.map((d) => {
          const total = (d.UsedGB || 0) + (d.FreeGB || 0);
          return { ...d, TotalGB: d.TotalGB ?? total, UsedPct: total ? Math.round((d.UsedGB / total) * 1000) / 10 : 0 };
        });
        body += section('Drives', meterList(withPct));
      }
      return {
        title: action === 'identity' ? 'Host identity' : 'Inventory snapshot',
        subtitle: `${host} · ${when}`,
        badges: [badge(host, 'info'), data.PowerShell ? badge(`PS ${data.PowerShell}`, 'ok') : ''].filter(Boolean),
        bodyHtml: body,
        plainText: `Inventory: ${host}`,
      };
    }

    // Service control result
    if (data?.Operation && data?.Name) {
      return {
        title: `Service ${data.Operation}`,
        subtitle: when,
        badges: [badge(data.Status || 'Done', 'ok')],
        bodyHtml: section('Result', kvGrid([
          ['Service', data.Name],
          ['Operation', data.Operation],
          ['Status', data.Status],
        ])),
        plainText: `${data.Operation} ${data.Name}: ${data.Status}`,
      };
    }

    // Fleet pulse
    if (Array.isArray(data?.pulse)) {
      return {
        title: 'Fleet pulse',
        subtitle: `${data.pulse.length} host(s) checked`,
        badges: [
          badge(`${data.pulse.filter((p) => p.online).length} online`, 'ok'),
          badge(`${data.pulse.filter((p) => !p.online).length} offline`, 'bad'),
        ],
        bodyHtml: section('Hosts', tableFromRows(data.pulse, ['host', 'online', 'latencyMs', 'os', 'uptime'])),
        plainText: `Fleet pulse: ${data.pulse.length} hosts`,
      };
    }

    // Playbook results
    if (Array.isArray(data?.Results) || Array.isArray(data?.results)) {
      const results = data.Results || data.results;
      const failed = results.filter((r) => (r.Status || r.status) === 'failed').length;
      const steps = results.map((r) => {
        const status = r.Status || r.status;
        const ok = status === 'ok';
        return `
          <div class="step-item">
            <div class="step-head">
              <strong>${escapeHtml(r.Step || r.step || 'Step')}</strong>
              ${badge(ok ? 'OK' : 'Failed', ok ? 'ok' : 'bad')}
            </div>
            <div class="step-meta">${escapeHtml(r.Target || r.target || target)}${r.Error || r.error ? ` · ${escapeHtml(r.Error || r.error)}` : ''}</div>
          </div>`;
      }).join('');
      return {
        title: data.Name || data.name || 'Playbook',
        subtitle: prettyTime(data.Timestamp || data.timestamp) || when,
        badges: [badge(`${results.length} steps`, 'info'), badge(failed ? `${failed} failed` : 'All passed', failed ? 'bad' : 'ok')],
        bodyHtml: section('Steps', `<div class="step-list">${steps}</div>`),
        plainText: `Playbook ${(data.Name || data.name)}: ${results.length} steps`,
      };
    }

    // Generic arrays of objects
    if (Array.isArray(data) && data.length && typeof data[0] === 'object') {
      return {
        title: humanizeKey(action || plugin || 'Results'),
        subtitle: `${data.length} rows · ${target}`,
        badges: [badge(`${data.length} rows`, 'info')],
        bodyHtml: section('Results', tableFromRows(data)),
        plainText: `${data.length} rows`,
      };
    }

    return {
      title: humanizeKey(action || plugin || 'Result'),
      subtitle: `${target} · ${when}`,
      badges: [badge('Complete', 'ok')],
      bodyHtml: formatGenericObject(data),
      plainText: typeof data === 'string' ? data : JSON.stringify(data, null, 2),
    };
  }

  function setOutput(payload, fallbackTitle = '') {
    if (typeof payload === 'string') {
      renderReport({
        title: fallbackTitle || 'Output',
        subtitle: new Date().toLocaleTimeString(),
        badges: [badge('Info', 'info')],
        bodyHtml: `<div class="msg-callout">${escapeHtml(payload)}</div>`,
        plainText: payload,
      });
      return;
    }
    const { meta, data } = unwrap(payload);
    if (fallbackTitle && !meta.action) meta.action = fallbackTitle;
    const report = formatByShape(meta, data);
    renderReport(report);
  }

  function target() {
    return (targetInput.value || 'localhost').trim();
  }

  async function invoke(plugin, action, parameters = {}) {
    setLoading(`Running ${plugin} → ${action} on ${target()}…`);
    try {
      const result = await api('/api/invoke', {
        method: 'POST',
        body: JSON.stringify({
          plugin,
          action,
          computerName: target(),
          parameters,
        }),
      });
      setOutput(result, `${plugin}.${action}`);
      toast(`${plugin}.${action} complete`);
      return result;
    } catch (err) {
      setError(err.message);
      toast(err.message);
      throw err;
    }
  }

  function renderNav() {
    pluginNav.innerHTML = state.plugins.map((p) => `
      <button class="nav-item ${state.currentPlugin === p.id ? 'active' : ''}" type="button" data-plugin="${p.id}">
        <span class="nav-icon">${iconMap[p.icon] || '•'}</span>
        <span>${escapeHtml(p.name)}</span>
      </button>
    `).join('');

    pluginNav.querySelectorAll('[data-plugin]').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.currentPlugin = btn.dataset.plugin;
        state.currentView = 'plugin';
        renderNav();
        renderView();
        const hero = document.getElementById('hero');
        if (hero) hero.style.display = 'none';
      });
    });
  }

  function renderView() {
    if (state.currentView === 'playbooks') return renderPlaybooks();
    if (state.currentView === 'activity') return renderActivity();
    if (state.currentView === 'home' || !state.currentPlugin) {
      view.innerHTML = `
        <h3>Command surface</h3>
        <p class="sub">Choose a plugin from the rail, or open the command palette to jump anywhere.</p>
        <div class="meta-row">
          <span class="chip">${state.plugins.length} plugins</span>
          <span class="chip">${state.actions.length} actions</span>
          <span class="chip">${state.playbooks.length} playbooks</span>
        </div>
        <div class="action-grid">
          ${state.actions.slice(0, 8).map((a) => `
            <button class="action-card" type="button" data-run="${a.PluginId}.${a.ActionId}">
              <strong>${escapeHtml(a.Name)}</strong>
              <span>${escapeHtml(a.Description || a.Category)}</span>
            </button>
          `).join('')}
        </div>
      `;
      bindActionCards();
      return;
    }

    const plugin = state.plugins.find((p) => p.id === state.currentPlugin);
    if (!plugin) return;

    view.innerHTML = `
      <h3>${escapeHtml(plugin.name)}</h3>
      <p class="sub">${escapeHtml(plugin.description)}</p>
      <div class="meta-row">
        <span class="chip">${escapeHtml(plugin.category)}</span>
        <span class="chip">v${escapeHtml(plugin.version)}</span>
      </div>
      <div class="action-grid">
        ${(plugin.actions || []).map((a) => `
          <button class="action-card" type="button" data-run="${plugin.id}.${a.id}">
            <strong>${escapeHtml(a.name)}</strong>
            <span>${escapeHtml(a.description || '')}</span>
          </button>
        `).join('')}
      </div>
    `;
    bindActionCards();
  }

  function bindActionCards() {
    view.querySelectorAll('[data-run]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const [plugin, action] = btn.dataset.run.split('.');
        const meta = state.actions.find((a) => a.PluginId === plugin && a.ActionId === action);
        if (meta?.Confirm || meta?.Destructive) {
          if (!confirm(`Run ${meta.Name} on ${target()}?`)) return;
        }
        let parameters = {};
        if (plugin === 'services' && action === 'control') {
          const name = prompt('Service name (e.g. Spooler):');
          if (!name) return;
          const operation = prompt('Operation: Start | Stop | Restart', 'Restart');
          if (!operation) return;
          parameters = { name, operation };
        }
        if (plugin === 'connectivity' && (action === 'probe' || action === 'ping')) {
          parameters = { host: target() };
        }
        if (plugin === 'security' && action === 'password') {
          parameters = { length: 24 };
        }
        await invoke(plugin, action, parameters);
      });
    });
  }

  async function renderPlaybooks() {
    state.currentView = 'playbooks';
    state.currentPlugin = null;
    renderNav();
    const hero = document.getElementById('hero');
    if (hero) hero.style.display = 'none';

    view.innerHTML = `
      <h3>Playbooks</h3>
      <p class="sub">Reusable multi-step admin recipes. Share them like scripts — version them like infrastructure.</p>
      <div class="action-grid">
        ${state.playbooks.map((p) => `
          <button class="action-card" type="button" data-playbook="${escapeHtml(p.Path)}">
            <strong>${escapeHtml(p.Name)}</strong>
            <span>${escapeHtml(p.Description || '')} · ${p.StepCount} steps</span>
          </button>
        `).join('') || '<div class="empty">No playbooks found.</div>'}
      </div>
    `;

    view.querySelectorAll('[data-playbook]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        setLoading('Running playbook…');
        try {
          const result = await api('/api/playbooks', {
            method: 'POST',
            body: JSON.stringify({ path: btn.dataset.playbook, computerName: target() }),
          });
          setOutput(result, result.Name || 'playbook');
          toast('Playbook finished');
        } catch (err) {
          setError(err.message);
        }
      });
    });
  }

  async function renderActivity() {
    state.currentView = 'activity';
    state.currentPlugin = null;
    renderNav();
    const hero = document.getElementById('hero');
    if (hero) hero.style.display = 'none';

    try {
      const data = await api('/api/logs');
      const rows = (data.logs || []).map((l) => `
        <tr>
          <td>${escapeHtml((l.Timestamp || '').slice(11, 19))}</td>
          <td><span class="status-dot ${l.Level === 'Error' ? 'bad' : l.Level === 'Success' ? 'good' : 'info'}"></span>${escapeHtml(l.Level)}</td>
          <td>${escapeHtml(l.Action || '—')}</td>
          <td>${escapeHtml(l.Message || '')}</td>
        </tr>
      `).join('');

      view.innerHTML = `
        <h3>Activity</h3>
        <p class="sub">Recent console actions for this session.</p>
        <table class="table">
          <thead><tr><th>Time</th><th>Level</th><th>Action</th><th>Message</th></tr></thead>
          <tbody>${rows || '<tr><td colspan="4" class="empty">No activity yet.</td></tr>'}</tbody>
        </table>
      `;
    } catch (err) {
      view.innerHTML = `<div class="empty">${escapeHtml(err.message)}</div>`;
    }
  }

  function openPalette() {
    palette.classList.remove('hidden');
    paletteInput.value = '';
    state.paletteIndex = 0;
    filterPalette('');
    paletteInput.focus();
  }

  function closePalette() {
    palette.classList.add('hidden');
  }

  function filterPalette(q) {
    const query = q.toLowerCase().trim();
    const items = state.actions.filter((a) => {
      const hay = [a.Name, a.Description, a.Category, a.Id, ...(a.Keywords || [])].join(' ').toLowerCase();
      return !query || hay.includes(query);
    }).slice(0, 12);

    state.paletteItems = items;
    state.paletteIndex = 0;
    paletteList.innerHTML = items.map((a, i) => `
      <li class="${i === 0 ? 'active' : ''}" data-idx="${i}">
        <span>${escapeHtml(a.Name)}<br><small style="color:var(--faint)">${escapeHtml(a.Description || '')}</small></span>
        <span class="cat">${escapeHtml(a.Category)}</span>
      </li>
    `).join('') || '<li class="empty">No matches</li>';

    paletteList.querySelectorAll('li[data-idx]').forEach((li) => {
      li.addEventListener('click', () => runPaletteItem(Number(li.dataset.idx)));
    });
  }

  async function runPaletteItem(idx) {
    const item = state.paletteItems[idx];
    if (!item) return;
    closePalette();
    state.currentPlugin = item.PluginId;
    state.currentView = 'plugin';
    const hero = document.getElementById('hero');
    if (hero) hero.style.display = 'none';
    renderNav();
    renderView();
    await invoke(item.PluginId, item.ActionId, item.PluginId === 'connectivity' ? { host: target() } : {});
  }

  async function boot() {
    try {
      const health = await api('/api/health');
      healthPill.textContent = `v${health.version} · ${health.hostname}`;
      healthPill.classList.add('ok');
      healthPill.classList.remove('pending');

      const [plugins, actions, playbooks] = await Promise.all([
        api('/api/plugins'),
        api('/api/actions'),
        api('/api/playbooks'),
      ]);

      state.plugins = plugins.plugins || [];
      state.actions = (actions.actions || []).map((a) => ({
        ...a,
        PluginId: a.PluginId || a.pluginId,
        ActionId: a.ActionId || a.actionId,
        Name: a.Name || a.name,
        Description: a.Description || a.description,
        Category: a.Category || a.category,
        Keywords: a.Keywords || a.keywords || [],
        Confirm: a.Confirm || a.confirm,
        Destructive: a.Destructive || a.destructive,
      }));
      state.playbooks = (playbooks.playbooks || []).map((p) => ({
        Name: p.Name || p.name,
        Description: p.Description || p.description,
        Path: p.Path || p.path,
        StepCount: p.StepCount || p.stepCount || 0,
      }));

      renderNav();
      renderView();
      setOutput(health, 'health');
    } catch (err) {
      healthPill.textContent = 'offline';
      healthPill.classList.add('warn');
      setError(`${err.message} — is Start-LumenOps running?`);
    }
  }

  $('#btnPalette').addEventListener('click', openPalette);
  $('#btnClearOut').addEventListener('click', () => {
    state.lastPlainText = '';
    output.innerHTML = '<div class="out-empty">Cleared. Pick an action or press ⌘K.</div>';
  });
  $('#btnCopyOut').addEventListener('click', async () => {
    const text = state.lastPlainText || output.innerText;
    try {
      await navigator.clipboard.writeText(text);
      toast('Copied to clipboard');
    } catch {
      toast('Copy failed');
    }
  });
  $('#btnPlaybooks').addEventListener('click', renderPlaybooks);
  $('#btnActivity').addEventListener('click', renderActivity);
  $('#btnQuickHealth').addEventListener('click', async () => {
    const pb = state.playbooks.find((p) => /health/i.test(p.Name));
    if (pb) {
      setLoading('Running health check playbook…');
      try {
        const result = await api('/api/playbooks', {
          method: 'POST',
          body: JSON.stringify({ path: pb.Path, computerName: target() }),
        });
        setOutput(result, 'Health Check');
        toast('Health check complete');
      } catch (err) {
        setError(err.message);
      }
    } else {
      await invoke('connectivity', 'probe', { host: target() });
    }
  });
  $('#btnQuickInventory').addEventListener('click', () => invoke('inventory', 'snapshot'));
  $('#btnPulse').addEventListener('click', async () => {
    setLoading('Pulsing fleet…');
    try {
      const hosts = target().split(/[,;\s]+/).filter(Boolean);
      const data = await api('/api/fleet/pulse', {
        method: 'POST',
        body: JSON.stringify({ hosts }),
      });
      setOutput(data, 'fleet pulse');
      toast('Pulse complete');
    } catch (err) {
      setError(err.message);
    }
  });

  paletteInput.addEventListener('input', (e) => filterPalette(e.target.value));

  document.addEventListener('keydown', (e) => {
    const isMac = navigator.platform.toUpperCase().includes('MAC');
    if ((isMac ? e.metaKey : e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      if (palette.classList.contains('hidden')) openPalette();
      else closePalette();
    }
    if (e.key === 'Escape') closePalette();

    if (!palette.classList.contains('hidden')) {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        state.paletteIndex = Math.min(state.paletteIndex + 1, state.paletteItems.length - 1);
        syncPaletteActive();
      }
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        state.paletteIndex = Math.max(state.paletteIndex - 1, 0);
        syncPaletteActive();
      }
      if (e.key === 'Enter') {
        e.preventDefault();
        runPaletteItem(state.paletteIndex);
      }
    }
  });

  function syncPaletteActive() {
    paletteList.querySelectorAll('li[data-idx]').forEach((li) => {
      li.classList.toggle('active', Number(li.dataset.idx) === state.paletteIndex);
    });
  }

  boot();
})();
