(() => {
  const state = {
    plugins: [],
    actions: [],
    playbooks: [],
    currentPlugin: null,
    currentView: 'home',
    paletteIndex: 0,
    paletteItems: [],
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
    camera: '◉', id: '신분증',
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

  function setOutput(obj, meta = '') {
    const stamp = new Date().toLocaleTimeString();
    const header = meta ? `// ${meta} · ${stamp}\n` : `// ${stamp}\n`;
    const body = typeof obj === 'string' ? obj : JSON.stringify(obj, null, 2);
    output.innerHTML = `<span class="key">${escapeHtml(header)}</span>${syntaxHint(body)}`;
    output.scrollTop = 0;
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function syntaxHint(json) {
    return escapeHtml(json)
      .replace(/("(?:\\.|[^"\\])*")\s*:/g, '<span class="key">$1</span>:')
      .replace(/\b(true|false|null)\b/g, '<span class="ok">$1</span>');
  }

  function target() {
    return (targetInput.value || 'localhost').trim();
  }

  async function invoke(plugin, action, parameters = {}) {
    setOutput({ status: 'running', plugin, action, target: target() }, 'invoke');
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
      setOutput({ error: err.message }, 'error');
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
        document.getElementById('hero')?.classList.add('hidden');
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
        setOutput({ status: 'running playbook', path: btn.dataset.playbook }, 'playbook');
        try {
          const result = await api('/api/playbooks', {
            method: 'POST',
            body: JSON.stringify({ path: btn.dataset.playbook, computerName: target() }),
          });
          setOutput(result, result.Name || 'playbook');
          toast('Playbook finished');
        } catch (err) {
          setOutput({ error: err.message }, 'error');
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
        // normalize casing from PowerShell
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
      setOutput({
        message: 'LumenOps online',
        platform: health.platform,
        plugins: health.plugins,
        psVersion: health.psVersion,
      }, 'health');
    } catch (err) {
      healthPill.textContent = 'offline';
      healthPill.classList.add('warn');
      setOutput({ error: err.message, hint: 'Is Start-LumenOps running?' }, 'boot');
    }
  }

  // Events
  $('#btnPalette').addEventListener('click', openPalette);
  $('#btnClearOut').addEventListener('click', () => {
    output.innerHTML = '<code>Cleared.</code>';
  });
  $('#btnPlaybooks').addEventListener('click', renderPlaybooks);
  $('#btnActivity').addEventListener('click', renderActivity);
  $('#btnQuickHealth').addEventListener('click', async () => {
    const pb = state.playbooks.find((p) => /health/i.test(p.Name));
    if (pb) {
      const result = await api('/api/playbooks', {
        method: 'POST',
        body: JSON.stringify({ path: pb.Path, computerName: target() }),
      });
      setOutput(result, 'Health Check');
      toast('Health check complete');
    } else {
      await invoke('connectivity', 'probe', { host: target() });
    }
  });
  $('#btnQuickInventory').addEventListener('click', () => invoke('inventory', 'snapshot'));
  $('#btnPulse').addEventListener('click', async () => {
    const hosts = target().split(/[,;\s]+/).filter(Boolean);
    const data = await api('/api/fleet/pulse', {
      method: 'POST',
      body: JSON.stringify({ hosts }),
    });
    setOutput(data, 'fleet pulse');
    toast('Pulse complete');
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
