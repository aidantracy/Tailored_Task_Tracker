// src/dashboard/static/js/comments.js
// Comments modal + DB integration + unread tracking + background polling.
// Align your own bubbles right; color the icon red only when there are unread comments.
// Modal header shows status + comment icon together.

export const commentsStore = new Map(); // taskId -> [{ comment_id?, text, atISO, who, user_id }]

let modalEl, dialogEl, headerEl, messagesEl, formEl, inputEl, closeEls, threadTitleEl;
let currentThreadTaskId = null;
let wired = false;

// cache of current user from api/me
let meCache = null;

// double-submit guards
let submitBusy = false;
let lastSubmit = { sig: null, at: 0 };

// unread polling
let unreadPollTimer = null;
const UNREAD_POLL_MS = 20000; // 20s

/* =========================
   DOM refs
   ========================= */
function initDomRefs() {
  modalEl = document.getElementById('task-thread-modal');
  dialogEl = modalEl?.querySelector('.tmodal__dialog');
  headerEl = dialogEl?.querySelector('header');
  messagesEl = document.getElementById('thread-messages');
  formEl = document.getElementById('thread-form');
  inputEl = document.getElementById('thread-input');
  closeEls = document.querySelectorAll('[data-close-modal]');
  threadTitleEl = document.getElementById('thread-title');
  return !!(modalEl && dialogEl && messagesEl && formEl && inputEl && threadTitleEl);
}

function showModal() {
  if (!initDomRefs()) return;
  modalEl.classList.remove('hidden');
  dialogEl.setAttribute('tabindex', '-1');
  dialogEl.focus({ preventScroll: true });
}

function hideModal() {
  if (!initDomRefs()) return;
  modalEl.classList.add('hidden');
  currentThreadTaskId = null;
}

/* =========================
   Current user helpers
   ========================= */
async function ensureMe() {
  if (meCache) return meCache;

  // Try DOM first
  const idEl = document.querySelector('[data-current-user-id]');
  const nameEl = document.querySelector('[data-current-user-name]');
  if (idEl || nameEl) {
    meCache = {
      user_id: idEl?.getAttribute('data-current-user-id') || idEl?.textContent || null,
      display_name: nameEl?.textContent?.trim() || 'You',
    };
    return meCache;
  }

  // Fallback to API
  try {
    const res = await fetch('api/me', { headers: { Accept: 'application/json' }, credentials: 'same-origin' });
    if (res.ok) {
      const json = await res.json();
      meCache = {
        user_id: json.user_id != null ? String(json.user_id) : null,
        display_name: json.display_name || 'You',
      };
      return meCache;
    }
  } catch (_) { /* ignore */ }

  meCache = { user_id: null, display_name: 'You' };
  return meCache;
}

function myIdSync() { return meCache?.user_id != null ? String(meCache.user_id) : null; }
function myNameSync() { return (meCache?.display_name || 'You'); }

/* =========================
   API helpers
   ========================= */
async function apiGetComments(taskId) {
  const res = await fetch(`api/tasks/${encodeURIComponent(taskId)}/comments`, {
    headers: { 'Accept': 'application/json' },
    credentials: 'same-origin',
  });
  if (res.status === 401) throw new Error('Unauthorized');
  if (!res.ok) throw new Error(await res.text().catch(()=>'GET comments failed'));
  const json = await res.json();
  const list = Array.isArray(json.comments) ? json.comments.map(c => ({
    comment_id: c.comment_id,
    text: c.text,
    who: c.who || '',
    atISO: c.at_iso || c.atISO || new Date().toISOString(),
    user_id: c.user_id,
  })) : [];
  return list;
}

async function apiCreateComment(taskId, textBody) {
  const res = await fetch(`api/tasks/${encodeURIComponent(taskId)}/comments`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
    body: JSON.stringify({ text: textBody }),
    credentials: 'same-origin',
  });
  if (res.status === 401) throw new Error('Unauthorized');
  if (!res.ok) throw new Error(await res.text().catch(()=>'POST comment failed'));
  const json = await res.json();
  const c = json.comment || {};
  return {
    comment_id: c.comment_id,
    text: c.text,
    who: c.who || '',
    atISO: c.at_iso || c.atISO || new Date().toISOString(),
    user_id: c.user_id,
  };
}

async function apiGetCounts(taskIds) {
  if (!taskIds?.length) return {};
  const qs = encodeURIComponent(taskIds.join(','));
  const res = await fetch(`api/comments/counts?task_ids=${qs}`, {
    headers: { 'Accept': 'application/json' },
    credentials: 'same-origin',
  });
  if (res.status === 401) return {};
  if (!res.ok) return {};
  const json = await res.json();
  return json.counts || {};
}

async function apiGetUnreadCounts(taskIds) {
  if (!taskIds?.length) return {};
  const qs = encodeURIComponent(taskIds.join(','));
  const res = await fetch(`api/comments/unread_counts?task_ids=${qs}`, {
    headers: { 'Accept': 'application/json' },
    credentials: 'same-origin',
  });
  if (res.status === 401) return {};
  if (!res.ok) return {};
  const json = await res.json();
  return json.counts || {};
}

async function apiMarkRead(taskId) {
  const res = await fetch(`api/tasks/${encodeURIComponent(taskId)}/comments/read_mark`, {
    method: 'POST',
    headers: { 'Accept': 'application/json' },
    credentials: 'same-origin',
  });
  return res.ok;
}

/* =========================
   Formatting
   ========================= */
function formatLocalNoSeconds(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return '';
  return d.toLocaleString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit'
  });
}

function isMine(message) {
  const myId = myIdSync();
  if (myId != null && message.user_id != null) {
    return String(message.user_id) === String(myId);
  }
  const mine = (myNameSync() || '').trim().toLowerCase();
  const who = (message.who || '').trim().toLowerCase();
  if (mine && who) return mine === who;
  return (message.who || '').trim() === 'You';
}

/* =========================
   Rendering
   ========================= */
function renderThread(taskId, titleText = null) {
  if (!initDomRefs()) return;

  // Title
  if (threadTitleEl) {
    threadTitleEl.textContent = titleText || `Task ${taskId}`;
  }

  messagesEl.innerHTML = '';
  const msgs = commentsStore.get(String(taskId)) || [];

  for (const m of msgs) {
    const mine = isMine(m);
    const row = document.createElement('div');
    row.className = `msg-row ${mine ? 'msg-right' : 'msg-left'}`;

    const bubble = document.createElement('div');
    bubble.className = `msg-bubble ${mine ? 'bubble-you' : 'bubble-other'}`;

    const metaTop = document.createElement('div');
    metaTop.className = 'flex items-center justify-between gap-3';
    const whoEl = document.createElement('strong');
    whoEl.className = 'text-slate-800';
    whoEl.textContent = m.who || (mine ? myNameSync() : 'Someone');

    const timeEl = document.createElement('time');
    timeEl.className = 'text-slate-400 text-[12px]';
    timeEl.setAttribute('datetime', m.atISO);
    timeEl.textContent = formatLocalNoSeconds(m.atISO);

    metaTop.appendChild(whoEl);
    metaTop.appendChild(timeEl);

    const textEl = document.createElement('p');
    textEl.className = 'msg-text mt-1';
    textEl.textContent = m.text;

    bubble.appendChild(metaTop);
    bubble.appendChild(textEl);
    row.appendChild(bubble);
    messagesEl.appendChild(row);
  }
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

/* ===== Status + indicators ===== */
function populateModalStatusFromCard(card) {
  const pill = document.getElementById('thread-status-pill');
  if (!pill) return;
  const statusTextEl = document.getElementById('thread-status-text');
  const dotEl = document.getElementById('thread-status-dot');

  const chip = card?.querySelector('[data-chip]');
  const chipText = card?.querySelector('[data-chip-text]')?.textContent?.trim();
  if (chip && chipText) {
    pill.style.display = '';
    statusTextEl.textContent = chipText;
    try {
      const cs = window.getComputedStyle(chip);
      pill.style.backgroundColor = cs.backgroundColor;
      pill.style.color = cs.color;
      if (dotEl) dotEl.style.backgroundColor = cs.color;
    } catch (_) {}
  } else {
    pill.style.display = 'none';
  }
}

// Simple unread color toggle (no glow)
function setIconUnread(el, on) {
  if (!el) return;
  el.classList.toggle('comment-unread', !!on);
}

function updateModalIndicator(unreadCount) {
  const icon = document.getElementById('thread-comment-indicator');
  if (!icon) return;
  const badge = icon.querySelector('[data-modal-unread-count]');
  if (badge) badge.textContent = unreadCount > 0 ? String(unreadCount) : '';
  setIconUnread(icon, unreadCount > 0);
}

/* ===== Comment indicator helpers for cards ===== */
function findCardByTaskId(taskId) {
  return document.querySelector(`.task-card[data-task-id="${taskId}"]`);
}
export function updateCommentIndicator(taskId, { hasComments, unread = 0, markNew } = {}) {
  const card = findCardByTaskId(taskId);
  if (!card) return;
  const icon = card.querySelector('[data-comment-indicator]');
  const badge = card.querySelector('[data-unread-count], [data-comment-count]'); // support both
  if (!icon) return;

  // badge shows only unread
  if (badge) {
    badge.textContent = unread > 0 ? String(unread) : '';
  }

  if (hasComments === true) {
    card.classList.add('has-comments');
    icon.style.removeProperty('display'); // clear any inline 'display:none'
  }
  if (hasComments === false) {
    card.classList.remove('has-comments');
    icon.style.display = 'none';
  }

  // keep ping dot behavior, but color is controlled by .comment-unread
  if (typeof markNew === 'boolean') {
    if (markNew) card.classList.add('has-new'); else card.classList.remove('has-new');
  }

  // color the icon when unread > 0 (neutral otherwise)
  setIconUnread(icon, (unread || 0) > 0);
}

/* =========================
   Counts + unread prefetch (debounced batch)
   ========================= */
const pendingIdSet = new Set();
let pendingTimer = null;

function queueCountsFetch(ids) {
  for (const id of ids) {
    if (id != null && String(id).trim() !== '') pendingIdSet.add(String(id));
  }
  if (pendingTimer) clearTimeout(pendingTimer);
  pendingTimer = setTimeout(flushCountsFetch, 120);
}

async function flushCountsFetch() {
  if (!pendingIdSet.size) return;
  const all = Array.from(pendingIdSet);
  pendingIdSet.clear();

  const chunkSize = 60;
  for (let i = 0; i < all.length; i += chunkSize) {
    const chunk = all.slice(i, i + chunkSize);
    try {
      const [counts, unread] = await Promise.all([
        apiGetCounts(chunk),
        apiGetUnreadCounts(chunk)
      ]);

      for (const id of chunk) {
        const total = parseInt(counts?.[id] || 0, 10);
        const unreadCnt = parseInt(unread?.[id] || 0, 10);

        if (total > 0) {
          updateCommentIndicator(id, { hasComments: true, unread: unreadCnt, markNew: unreadCnt > 0 });
        } else {
          updateCommentIndicator(id, { hasComments: false, unread: 0, markNew: false });
        }

        // if this modal is open for this task, reflect unread here too
        if (currentThreadTaskId && String(currentThreadTaskId) === String(id)) {
          updateModalIndicator(unreadCnt);
        }
      }
    } catch (err) {
      console.warn('count/unread fetch failed', err);
    }
  }
}

export function refreshCommentCountsFor(taskIdsOrNodes) {
  const ids = [];
  if (!taskIdsOrNodes) return;
  if (Array.isArray(taskIdsOrNodes)) {
    for (const x of taskIdsOrNodes) {
      if (typeof x === 'string' || typeof x === 'number') ids.push(String(x));
      else if (x?.nodeType === 1 && x.matches?.('.task-card[data-task-id]')) ids.push(x.dataset.taskId);
    }
  } else if (typeof taskIdsOrNodes === 'string' || typeof taskIdsOrNodes === 'number') {
    ids.push(String(taskIdsOrNodes));
  } else if (taskIdsOrNodes?.nodeType === 1) {
    taskIdsOrNodes.querySelectorAll?.('.task-card[data-task-id]').forEach(el => ids.push(el.dataset.taskId));
  }
  if (ids.length) queueCountsFetch(ids);
}

function primeCountsForVisibleCards() {
  const ids = Array.from(document.querySelectorAll('.task-card[data-task-id]'))
    .map(n => n.dataset.taskId)
    .filter(Boolean);
  if (ids.length) queueCountsFetch(ids);
}

/* =========================
   Background polling for unread
   ========================= */
function allVisibleTaskIds() {
  return Array.from(document.querySelectorAll('.task-card[data-task-id]'))
    .map(el => el.dataset.taskId)
    .filter(Boolean);
}

function startUnreadPolling() {
  stopUnreadPolling();
  const tick = () => {
    const ids = allVisibleTaskIds();
    if (ids.length) queueCountsFetch(ids);
  };
  tick(); // immediate check
  unreadPollTimer = setInterval(tick, UNREAD_POLL_MS);
}

function stopUnreadPolling() {
  if (unreadPollTimer) {
    clearInterval(unreadPollTimer);
    unreadPollTimer = null;
  }
}

// Pause polling when the tab is hidden; resume when visible
function wireVisibilityHandlers() {
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') {
      stopUnreadPolling();
    } else {
      startUnreadPolling();
    }
  });
  window.addEventListener('focus', startUnreadPolling);
  window.addEventListener('blur', stopUnreadPolling);
}

/* =========================
   Observe new cards appended later
   ========================= */
function observeTaskCardAdditions() {
  const board = document.getElementById('board') || document.body;
  const mo = new MutationObserver((mutations) => {
    const newIds = [];
    for (const m of mutations) {
      m.addedNodes && m.addedNodes.forEach(node => {
        if (!(node && node.nodeType === 1)) return;
        if (node.matches?.('.task-card[data-task-id]')) {
          newIds.push(node.dataset.taskId);
        }
        node.querySelectorAll?.('.task-card[data-task-id]').forEach(el => {
          if (el.dataset.taskId) newIds.push(el.dataset.taskId);
        });
      });
    }
    if (newIds.length) queueCountsFetch(newIds);
  });
  mo.observe(board, { childList: true, subtree: true });
}

/* =========================
   Modal open
   ========================= */
export async function openThreadModal(target) {
  const reopen = () => openThreadModal(target); // for deferred call if DOM not ready

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', reopen, { once: true });
    return;
  }
  if (!initDomRefs()) {
    setTimeout(reopen, 0);
    return;
  }

  await ensureMe();

  // Resolve taskId + title + status
  let taskId = null;
  let titleText = null;
  let card = null;

  if (target && target.nodeType === 1) {
    card = target.closest?.('.task-card') || target;
    taskId = card.dataset.taskId || card.getAttribute('data-task-id') || null;
    titleText = card.querySelector('[data-title]')?.textContent?.trim() || null;
  } else if (typeof target === 'object' && target != null) {
    taskId = target.taskId ?? target.id ?? null;
    titleText = target.title ?? null;
    card = document.querySelector(`.task-card[data-task-id="${taskId}"]`);
  } else {
    taskId = target;
    card = document.querySelector(`.task-card[data-task-id="${taskId}"]`);
  }

  if (taskId == null) return;
  currentThreadTaskId = String(taskId);

  // Populate status pill from the card
  populateModalStatusFromCard(card);

  try {
    const list = await apiGetComments(currentThreadTaskId);
    commentsStore.set(currentThreadTaskId, list);
    // Mark as read up to latest on open (server state)
    await apiMarkRead(currentThreadTaskId);
    // Update indicators locally: unread -> 0 now
    updateCommentIndicator(currentThreadTaskId, {
      hasComments: list.length > 0,
      unread: 0,
      markNew: false
    });
    updateModalIndicator(0);
  } catch (err) {
    console.warn('fetch/mark-read failed', err);
  }

  renderThread(currentThreadTaskId, titleText || `Task ${currentThreadTaskId}`);
  showModal();
}

/* =========================
   Init + wiring
   ========================= */
export async function initComments() {
  if (wired) return;
  if (!initDomRefs()) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', initComments, { once: true });
      return;
    }
    if (!initDomRefs()) return;
  }

  await ensureMe();

  // Legacy discuss button (safe even if present)
  document.addEventListener('click', (e) => {
    const btn = e.target.closest?.('[data-open-thread]');
    if (!btn) return;
    const card = btn.closest('.task-card');
    if (card) openThreadModal(card);
  });

  // Click blank space on a card to open modal
  document.addEventListener('dblclick', (e) => {
    const card = e.target.closest?.('.task-card');
    if (!card) return;
    const ignore = e.target.closest?.(
      'button, a, input, select, textarea, [data-action], [data-set-status], .no-modal, [data-assignee-popover], [data-date-popover]'
    );
    if (ignore) return;
    openThreadModal(card);
  });

  // Keyboard open on Enter
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter') return;
    const card = e.target.closest?.('.task-card');
    if (card && document.activeElement === card) {
      e.preventDefault();
      openThreadModal(card);
    }
  });

  // Close handlers
  modalEl.addEventListener('click', (e) => {
    if (e.target.matches('[data-close-modal]')) hideModal();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !modalEl.classList.contains('hidden')) hideModal();
  });

  // Submit new comment
  formEl.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!currentThreadTaskId) return;
    const text = inputEl.value.trim();
    if (!text) return;

    // dedupe guard
    const sig = `${currentThreadTaskId}|${text}`;
    const now = Date.now();
    if (submitBusy || (lastSubmit.sig === sig && now - lastSubmit.at < 1500)) return;
    submitBusy = true;
    lastSubmit = { sig, at: now };

    try {
      const created = await apiCreateComment(currentThreadTaskId, text);
      // Local push
      const mine = {
        comment_id: created.comment_id,
        text: created.text,
        who: myNameSync(),
        atISO: created.atISO,
        user_id: myIdSync()
      };
      const list = commentsStore.get(currentThreadTaskId) || [];
      list.push(mine);
      commentsStore.set(currentThreadTaskId, list);
      renderThread(currentThreadTaskId);

      // Clear input
      inputEl.value = '';

      // Mark read immediately for myself (avoid showing as unread)
      await apiMarkRead(currentThreadTaskId);

      // Update indicators: current task unread -> 0
      updateCommentIndicator(currentThreadTaskId, { hasComments: true, unread: 0, markNew: false });
      updateModalIndicator(0);
    } catch (err) {
      console.error('post comment failed', err);
    } finally {
      submitBusy = false;
    }
  });

  // Prefetch counts and start background polling
  primeCountsForVisibleCards();
  startUnreadPolling();
  wireVisibilityHandlers();
  observeTaskCardAdditions();

  wired = true;
}
