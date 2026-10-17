'use strict';

const POLL_INTERVAL_MS = 3000;

const el = {
  connStatus: document.getElementById('connStatus'),
  connectionBanner: document.getElementById('connectionBanner'),
  connectionBannerTitle: document.getElementById('connectionBannerTitle'),
  connectionBannerDetail: document.getElementById('connectionBannerDetail'),
  retryBtn: document.getElementById('retryBtn'),
  themeToggle: document.getElementById('themeToggle'),
  routingGrid: document.getElementById('routingGrid'),
  inputList: document.getElementById('inputList'),
  advancedToggle: document.getElementById('advancedToggle'),
  advancedPanel: document.getElementById('advancedPanel'),
  infoIp: document.getElementById('infoIp'),
  infoAccount: document.getElementById('infoAccount'),
  infoFirmware: document.getElementById('infoFirmware'),
  renameInputsList: document.getElementById('renameInputsList'),
  renameOutputsList: document.getElementById('renameOutputsList'),
  networkForm: document.getElementById('networkForm'),
  netIp: document.getElementById('netIp'),
  netMask: document.getElementById('netMask'),
  netGw: document.getElementById('netGw'),
  passwordForm: document.getElementById('passwordForm'),
  rebootBtn: document.getElementById('rebootBtn'),
  factoryResetBtn: document.getElementById('factoryResetBtn'),
  renameModal: document.getElementById('renameModal'),
  renameForm: document.getElementById('renameForm'),
  renameInput: document.getElementById('renameInput'),
  toast: document.getElementById('toast'),
};

let state = null;
let busy = false;       // true while a user-initiated request is in flight
let pollTimer = null;
let renameTarget = null; // {kind: 'in'|'out', index: number}
let lastUpdatedAt = null;

// ---------- theme ----------

function initTheme() {
  const saved = localStorage.getItem('hdmi-matrix-theme');
  if (saved === 'light' || saved === 'dark') {
    document.documentElement.setAttribute('data-theme', saved);
  }
  updateThemeControl();
}

function effectiveTheme() {
  return document.documentElement.getAttribute('data-theme')
    || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
}

function updateThemeControl() {
  const current = effectiveTheme();
  const next = current === 'dark' ? 'light' : 'dark';
  const label = `Use ${next} theme`;
  el.themeToggle.setAttribute('aria-label', label);
  el.themeToggle.setAttribute('title', label);
  el.themeToggle.setAttribute('aria-pressed', String(current === 'dark'));
  const themeColor = document.getElementById('themeColor');
  if (themeColor) {
    const resolvedBackground = getComputedStyle(document.documentElement).getPropertyValue('--bg').trim();
    if (resolvedBackground) themeColor.setAttribute('content', resolvedBackground);
  }
}

function toggleTheme() {
  const current = effectiveTheme();
  const next = current === 'dark' ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', next);
  try { localStorage.setItem('hdmi-matrix-theme', next); } catch (e) { /* private mode, ignore */ }
  updateThemeControl();
}

el.themeToggle.addEventListener('click', toggleTheme);
initTheme();

// ---------- networking ----------

async function api(path, options) {
  try {
    const res = await fetch(path, options);
    let body = null;
    try { body = await res.json(); } catch (e) { /* no body */ }
    if (!res.ok) {
      const message = (body && body.error) || `Request failed (${res.status})`;
      throw new Error(message);
    }
    return body;
  } catch (err) {
    if (err instanceof TypeError) throw new Error('Control service is unreachable');
    throw err;
  }
}

async function fetchState() {
  return api('/api/state');
}

async function sendAction(path, payload) {
  busy = true;
  render();
  try {
    const next = await api(path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload || {}),
    });
    if (next && next.inputs) {
      state = next;
      render();
    }
    lastUpdatedAt = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date());
    setConnState('ok');
    return next;
  } catch (err) {
    setConnState('error');
    showToast(err.message, 'error');
    throw err;
  } finally {
    busy = false;
    render();
  }
}

function setConnState(mode) {
  el.connStatus.dataset.state = mode;
  const label = el.connStatus.querySelector('.status__label');
  label.textContent = mode === 'ok' ? 'Connected' : mode === 'error' ? 'Connection lost' : 'Connecting…';
  el.connectionBanner.dataset.state = mode;
  el.connectionBanner.hidden = mode === 'ok';
  el.retryBtn.hidden = mode !== 'error';
  if (mode === 'error') {
    el.connectionBannerTitle.textContent = 'Control service unavailable';
    el.connectionBannerDetail.textContent = lastUpdatedAt
      ? `Showing the last known state from ${lastUpdatedAt}.`
      : 'Check the host address and try again.';
  } else if (mode === 'connecting') {
    el.connectionBannerTitle.textContent = 'Connecting to control service';
    el.connectionBannerDetail.textContent = 'Loading the latest matrix state…';
  }
}

// ---------- toast ----------

let toastTimer = null;
function showToast(message, kind) {
  el.toast.textContent = message;
  el.toast.dataset.kind = kind || 'info';
  el.toast.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.toast.hidden = true; }, 3200);
}

// ---------- polling ----------

async function poll() {
  if (busy) return;
  try {
    state = await fetchState();
    setConnState('ok');
    lastUpdatedAt = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date());
    render();
  } catch (err) {
    setConnState('error');
  }
}

function startPolling() {
  poll();
  pollTimer = setInterval(poll, POLL_INTERVAL_MS);
}

// ---------- rendering ----------

function render() {
  if (!state) return;
  renderRouting();
  renderAudio();
  renderInputs();
  renderRenameList(el.renameInputsList, 'in', 'Input', state.inputs);
  renderRenameList(el.renameOutputsList, 'out', 'Output', state.outputs);
  renderDeviceInfo();
}

function renderRouting() {
  el.routingGrid.innerHTML = '';
  el.routingGrid.setAttribute('aria-busy', String(busy));
  for (const output of state.outputs) {
    const card = document.createElement('div');
    card.className = 'route-card';

    const header = document.createElement('div');
    header.className = 'route-card__header';

    const nameWrap = document.createElement('div');
    nameWrap.className = 'route-card__name';
    const nameBtn = document.createElement('button');
    nameBtn.type = 'button';
    nameBtn.textContent = output.name;
    nameBtn.title = 'Rename this output';
    nameBtn.addEventListener('click', () => openRename('out', output.index, output.name));
    const sub = document.createElement('span');
    sub.className = 'route-card__sub';
    sub.textContent = `Output ${output.index}`;
    nameWrap.append(nameBtn, sub);

    const power = document.createElement('button');
    power.type = 'button';
    power.className = 'power-switch';
    power.setAttribute('aria-pressed', String(output.power));
    power.setAttribute('aria-label', `${output.name} power ${output.power ? 'on' : 'off'}`);
    power.disabled = busy;
    power.innerHTML = '<span class="power-switch__knob"></span>';
    power.addEventListener('click', () => {
      sendAction('/api/output-power', { output: output.index, on: !output.power }).catch(() => {});
    });

    header.append(nameWrap, power);

    const chooser = document.createElement('div');
    chooser.className = 'input-chooser';
    for (const input of state.inputs) {
      const chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'input-chip';
      chip.textContent = input.name;
      const active = input.index === output.input_index;
      chip.setAttribute('aria-pressed', String(active));
      chip.disabled = !output.power || busy;
      chip.title = !output.power ? 'Turn the output on to switch sources' : `Route ${input.name} to ${output.name}`;
      chip.addEventListener('click', () => {
        if (active) return;
        sendAction('/api/route', { output: output.index, input: input.index }).catch(() => {});
      });
      chooser.appendChild(chip);
    }

    card.append(header, chooser);
    el.routingGrid.appendChild(card);
  }
}

function renderAudio() {
  for (const group of document.querySelectorAll('.segmented')) {
    const mode = group.dataset.mode;
    const current = state.audio[mode].value;
    for (const btn of group.querySelectorAll('button')) {
      const value = Number(btn.dataset.value);
      // Out-A / Out-B are Output 1 / Output 2, so label each with whatever
      // input is currently routed there -- that's the audio you'd actually get.
      const output = state.outputs.find((o) => o.index === value);
      if (output) {
        const input = state.inputs.find((i) => i.index === output.input_index);
        const wire = value === 1 ? 'Out-A' : 'Out-B';
        const main = document.createElement('span');
        main.className = 'segmented__main';
        main.textContent = input ? input.name : wire;
        const sub = document.createElement('span');
        sub.className = 'segmented__sub';
        sub.textContent = output.power ? `${output.name} · ${wire}` : `${output.name} off · ${wire}`;
        btn.replaceChildren(main, sub);
      }
      btn.setAttribute('aria-pressed', String(value === current));
      btn.disabled = busy;
      btn.onclick = () => {
        if (value === current) return;
        sendAction('/api/audio', { mode, value }).catch(() => {});
      };
    }
  }
}

function renderInputs() {
  el.inputList.innerHTML = '';
  for (const input of state.inputs) {
    const row = document.createElement('div');
    row.className = 'input-row';

    const nameWrap = document.createElement('div');
    nameWrap.className = 'input-row__name';
    const nameBtn = document.createElement('button');
    nameBtn.type = 'button';
    nameBtn.textContent = input.name;
    nameBtn.title = 'Rename this input';
    nameBtn.addEventListener('click', () => openRename('in', input.index, input.name));
    const idx = document.createElement('span');
    idx.className = 'input-row__index';
    idx.textContent = `Input ${input.index}`;
    nameWrap.append(nameBtn, idx);

    const select = document.createElement('select');
    select.setAttribute('aria-label', `EDID preset for ${input.name}`);
    select.disabled = busy;
    for (const preset of state.edid_presets) {
      const opt = document.createElement('option');
      opt.value = String(preset.index);
      opt.textContent = `${String(preset.index).padStart(2, '0')}: ${preset.name}`;
      if (preset.index === input.edid_preset) opt.selected = true;
      select.appendChild(opt);
    }
    select.addEventListener('change', () => {
      sendAction('/api/edid', { input: input.index, preset: Number(select.value) }).catch(() => {
        select.value = String(input.edid_preset); // revert on failure
      });
    });

    row.append(nameWrap, select);
    el.inputList.appendChild(row);
  }
}

function renderDeviceInfo() {
  el.infoIp.textContent = state.device.ip || '–';
  el.infoAccount.textContent = state.device.account || '–';
  el.infoFirmware.textContent = state.device.firmware || '–';
  if (document.activeElement !== el.netIp && !el.netIp.value) el.netIp.value = state.device.ip || '';
}

// Rows are built once and then only their values are refreshed, so the 3s
// poll never clobbers a name the user is in the middle of typing.
function renderRenameList(container, kind, label, ports) {
  if (container.children.length !== ports.length) {
    container.innerHTML = '';
    for (const port of ports) {
      const form = document.createElement('form');
      form.className = 'rename-row';
      const field = document.createElement('input');
      field.type = 'text';
      field.minLength = 3;
      field.maxLength = 15;
      field.pattern = '[a-zA-Z0-9_]{3,15}';
      field.required = true;
      field.autocomplete = 'off';
      field.dataset.index = String(port.index);
      field.addEventListener('input', () => { field.dataset.dirty = '1'; });
      const lbl = document.createElement('label');
      lbl.textContent = `${label} ${port.index}`;
      lbl.append(field);
      const save = document.createElement('button');
      save.type = 'submit';
      save.className = 'btn';
      save.textContent = 'Save';
      save.disabled = busy;
      form.append(lbl, save);
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        const name = field.value.trim();
        save.disabled = true;
        sendAction('/api/rename', { kind, index: port.index, name })
          .then(() => { delete field.dataset.dirty; showToast(`${label} ${port.index} renamed to ${name}`, 'success'); })
          .catch(() => {})
          .finally(() => { save.disabled = false; });
      });
      container.appendChild(form);
    }
  }
  for (const port of ports) {
    const field = container.querySelector(`input[data-index="${port.index}"]`);
    const save = field?.closest('form')?.querySelector('button[type="submit"]');
    if (field && document.activeElement !== field && !field.dataset.dirty) field.value = port.name;
    if (save) save.disabled = busy;
  }
}

// ---------- rename modal ----------

function openRename(kind, index, currentName) {
  renameTarget = { kind, index };
  el.renameInput.value = currentName;
  el.renameModal.showModal();
  setTimeout(() => el.renameInput.focus(), 0);
}

function closeRename() {
  if (el.renameModal.open) el.renameModal.close();
  renameTarget = null;
}

el.renameModal.addEventListener('click', (e) => {
  if (e.target.dataset.close !== undefined) closeRename();
});

el.renameForm.addEventListener('submit', (e) => {
  e.preventDefault();
  if (!renameTarget) return;
  const name = el.renameInput.value.trim();
  sendAction('/api/rename', { kind: renameTarget.kind, index: renameTarget.index, name })
    .then(() => { showToast('Renamed', 'success'); closeRename(); })
    .catch(() => {});
});

// ---------- advanced panel ----------

el.advancedToggle.addEventListener('click', () => {
  const expanded = el.advancedToggle.getAttribute('aria-expanded') === 'true';
  el.advancedToggle.setAttribute('aria-expanded', String(!expanded));
  el.advancedPanel.hidden = expanded;
});

el.retryBtn.addEventListener('click', () => {
  setConnState('connecting');
  poll();
});

el.networkForm.addEventListener('submit', (e) => {
  e.preventDefault();
  const ip = el.netIp.value.trim();
  const mask = el.netMask.value.trim();
  const gw = el.netGw.value.trim();
  if (!confirm(`Apply new network settings?\n\nIP: ${ip}\nMask: ${mask}\nGateway: ${gw}\n\nIf these are wrong the matrix may become unreachable.`)) return;
  sendAction('/api/network', { ip, mask, gw })
    .then(() => showToast('Network settings applied', 'success'))
    .catch(() => {});
});

el.passwordForm.addEventListener('submit', (e) => {
  e.preventDefault();
  const user = document.getElementById('pwUser').value.trim();
  const pass1 = document.getElementById('pwPass1').value;
  const pass2 = document.getElementById('pwPass2').value;
  if (pass1 !== pass2) { showToast('Passwords do not match', 'error'); return; }
  sendAction('/api/system/password', { user, password: pass1 })
    .then(() => { showToast('Password changed', 'success'); el.passwordForm.reset(); })
    .catch(() => {});
});

el.rebootBtn.addEventListener('click', () => {
  if (!confirm('Reboot the matrix now? Video will drop for about 15 seconds.')) return;
  sendAction('/api/system/reboot').then(() => showToast('Rebooting…', 'success')).catch(() => {});
});

el.factoryResetBtn.addEventListener('click', () => {
  if (!confirm('Factory reset the matrix? This erases all routing, names, EDID, and network settings. This cannot be undone.')) return;
  if (!confirm('Really sure? Type OK in the next prompt to confirm.')) return;
  const typed = prompt('Type RESET to confirm the factory reset:');
  if (typed !== 'RESET') { showToast('Factory reset cancelled', 'info'); return; }
  sendAction('/api/system/factory-reset').then(() => showToast('Factory reset sent', 'success')).catch(() => {});
});

// ---------- boot ----------

startPolling();

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').catch(() => { /* non-fatal */ });
  });
}
