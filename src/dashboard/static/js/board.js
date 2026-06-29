// src/dashboard/static/js/board.js
// board.js — board wiring, DB hydration, and create/update/delete flow
import { openThreadModal, commentsStore, initComments } from './comments.js'

export function hasDOM() {
  try { return !!(globalThis?.document?.createElement) } catch { return false }
}

/* =========================
   Net guard (skip in QUnit/jsdom)
   ========================= */
const CAN_FETCH =
  typeof fetch === 'function' &&
  typeof window !== 'undefined' &&
  /^https?:/.test(window.location?.protocol || '');

/* Hard cap for notes (prevents giant columns) */
const NOTE_MAX_CHARS = 500;

/* Force note text to wrap vertically (even for long tokens) and clamp to 3 lines. */
function applyNoteLayout(el) {
  if (!el) return;
  el.classList?.remove('truncate', 'whitespace-nowrap');
  el.style.whiteSpace = 'normal';
  el.style.wordBreak = 'break-word';
  el.style.overflowWrap = 'anywhere';
  el.style.maxWidth = '100%';
  el.style.minWidth = '0';
  el.style.overflow = 'hidden';
  el.style.textOverflow = 'ellipsis';
  el.style.lineHeight = '1.25';
  el.style.display = '-webkit-box';
  // @ts-ignore
  el.style.webkitLineClamp = '3';
  // @ts-ignore
  el.style.webkitBoxOrient = 'vertical';
}

async function apiUpdateTask(taskId, patch) {
  if (!CAN_FETCH) return { ok: true };
  const res = await fetch(`api/tasks/${taskId}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
    body: JSON.stringify(patch),
    credentials: 'same-origin',
  });
  if (!res.ok) throw new Error(await res.text().catch(()=> 'PATCH failed'));
  return res.json();
}

/* =========================
   Debounced update queue (coalesce PATCHes per task)
   ========================= */
const UPDATE_DEBOUNCE_MS = 350;

const updateQueue = new Map(); // taskId -> { patch, timerId, resolvers, rejecters }

function scheduleTaskPatch(taskId, patch) {
  if (!CAN_FETCH) return Promise.resolve({ ok: true });
  if (!taskId)   return Promise.resolve({ ok: false });

  let entry = updateQueue.get(taskId);
  if (!entry) {
    entry = { patch: {}, timerId: null, resolvers: [], rejecters: [] };
    updateQueue.set(taskId, entry);
  }

  // Merge new fields into the pending patch (last write wins per key)
  Object.assign(entry.patch, patch);

  const p = new Promise((resolve, reject) => {
    entry.resolvers.push(resolve);
    entry.rejecters.push(reject);
  });

  if (entry.timerId) clearTimeout(entry.timerId);

  entry.timerId = setTimeout(async () => {
    const finalPatch  = entry.patch;
    const resolvers   = entry.resolvers;
    const rejecters   = entry.rejecters;
    updateQueue.delete(taskId);

    try {
      const res = await apiUpdateTask(taskId, finalPatch);
      resolvers.forEach(fn => fn(res));
    } catch (err) {
      rejecters.forEach(fn => fn(err));
    }
  }, UPDATE_DEBOUNCE_MS);

  return p;
}

async function apiDeleteTask(taskId) {
  if (!CAN_FETCH) return { ok: true };
  const res = await fetch(`api/tasks/${taskId}`, {
    method: 'DELETE',
    headers: { 'Accept': 'application/json' },
    credentials: 'same-origin',
  });
  if (!res.ok) throw new Error(await res.text().catch(()=> 'DELETE failed'));
  return res.json();
}

/* =========================
   Status + date helpers (exported for QUnit)
   ========================= */
const STATUS_MAP = {
  notexpected: { bar: '#e7e5e4', chip: ['bg-[#e7e5e4]','text-[#1f2937]','ring-[#d6d3d1]'], label: 'Not Expected' },
  notstarted:  { bar: '#e2e8f0', chip: ['bg-[#e2e8f0]','text-[#334155]','ring-[#cbd5e1]'], label: 'Not Started' },
  progress:    { bar: '#fff3cd', chip: ['bg-[var(--status-progress)]','text-[var(--status-progress-text)]','ring-[#f7e7a3]'], label: 'In Progress' },
  stuck:       { bar: '#fed7aa', chip: ['bg-[var(--status-stuck)]','text-[var(--status-stuck-text)]','ring-[#f3b98b]'], label: 'Stuck' },
  done:        { bar: '#d4edda', chip: ['bg-[var(--status-done)]','text-[var(--status-done-text)]','ring-[#c7e8cf]'], label: 'Done' },
};
export const YMD_RE = /^\d{4}-\d{2}-\d{2}$/;

export function toYMD(input) {
  if (!input) return '';
  if (YMD_RE.test(input)) return input;
  const d = new Date(input);
  if (isNaN(d)) return '';
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}
export function ymdToLocalDate(ymd) {
  if (!YMD_RE.test(ymd)) return null;
  const [y, m, d] = ymd.split('-').map(Number);
  return new Date(y, m - 1, d); // local midnight
}

/* =========================
   Generic helpers
   ========================= */
const initials = (name) => {
  if (!name) return 'U';
  const p = name.trim().split(/\s+/);
  const f = p[0]?.[0] || '';
  const l = p.length > 1 ? p[p.length - 1][0] : (p[0]?.[1] || '');
  return (f + l).toUpperCase() || 'U';
};
const inferStatusKeyFromLabel=(lbl)=>{ for(const [k,v] of Object.entries(STATUS_MAP)) if(v.label===lbl) return k; return 'notstarted'; }
const getStatusKey=(node)=> inferStatusKeyFromLabel(node.querySelector('[data-chip-text]')?.textContent || 'Not Started')
const statusKeyToLabel=(key)=>{ switch((key||'').toLowerCase()){ case 'progress':return 'In Progress'; case 'stuck':return 'Stuck'; case 'done':return 'Done'; case 'notexpected':return 'Not Expected'; default:return 'Not Started'; } };

export function isOverdue(dueYMD, primaryStatusKey) {
  if (!YMD_RE.test(dueYMD)) return false;
  const d = ymdToLocalDate(dueYMD);
  if (!d) return false;
  const now = new Date();
  const dd = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return dd < today && primaryStatusKey !== 'done' && primaryStatusKey !== 'notexpected';
}
function updateOverdue(node){
  const ymd=node.querySelector('[data-due]')?.getAttribute('datetime')||'';
  const sk=getStatusKey(node);
  const el=node.querySelector('[data-overdue]');
  const show= isOverdue(ymd,sk);
  if(el) el.classList.toggle('hidden', !show);
}

const show=(el)=>{ if(!el) return; el.classList.remove('hidden'); el.style.display=''; }
const hide=(el)=>{ if(!el) return; el.classList.add('hidden'); el.style.display='none'; }
const ensureTaskId=(task)=> (task && task.id != null) ? String(task.id) : String(Date.now()+Math.random());
const emitStatusChange=(node, prevKey, nextKey)=> node.dispatchEvent(new CustomEvent('taskstatuschange',{ bubbles:true, detail:{ taskId: node.dataset.taskId, prevStatus: prevKey, nextStatus: nextKey, nextStatusKey: nextKey }}));

/* =========================
   Visuals
   ========================= */
function applyTagStyles(node, statusKey){
  node.classList.remove('task--stuck','task--overdue');
  const raw=(node.getAttribute('data-tags')||'').toLowerCase();
  if(statusKey==='notexpected') return;
  if(raw.includes('overdue')) node.classList.add('task--overdue');
  else if(raw.includes('stuck') || statusKey==='stuck') node.classList.add('task--stuck');
}

function setCollapsed(node, collapsed) {
  node.classList.toggle('task-card--collapsed', !!collapsed);

  const dc = node.querySelector('[data-date-container]');
  if (dc) dc.style.display = collapsed ? 'none' : '';

  const note = node.querySelector('[data-note]');
  if (note) note.style.display = collapsed ? 'none' : '';

  const noteArea = node.querySelector('[data-note-area]');
  if (noteArea) noteArea.style.display = collapsed ? 'none' : '';

  const addBtn = node.querySelector('[data-action="add-note"]');
  if (addBtn) {
    if (collapsed) {
      addBtn.style.display = 'none';
    } else {
      const hasNote = !!(node.querySelector('[data-note]')?.textContent || '').trim();
      addBtn.style.display = hasNote ? 'none' : 'inline-flex';
    }
  }

  const wrap = node.querySelector('.px-3.pb-3');
  if (wrap){
    wrap.style.display='';
    wrap.querySelectorAll('[data-set-status]').forEach(b=>collapsed?hide(b):show(b));
    const rb=wrap.querySelector('[data-action="revert-done"]');
    if(rb) collapsed?show(rb):hide(rb);
  }
}

function applyStatus(node, statusKey){
  const conf=STATUS_MAP[statusKey]||STATUS_MAP.notstarted;
  const bar=node.querySelector('[data-statusbar]'); if(bar) bar.style.backgroundColor=conf.bar;

  const chip=node.querySelector('[data-chip]'); const chipText=node.querySelector('[data-chip-text]');
  if(chip && chipText){ chip.className='status-chip inline-flex items-center gap-1 rounded-full px-2 py-0.5 ring-1 ring-inset '+conf.chip.join(' '); chipText.textContent=conf.label; }

  node.classList.toggle('task-card--done', statusKey==='done');
  node.classList.toggle('task--notexpected', statusKey==='notexpected');
  node.style.setProperty('--card-accent', conf.bar);

  const collapsed = (statusKey==='done' || statusKey==='notexpected');
  setCollapsed(node, collapsed);
  node.classList.toggle('task-card--mini', statusKey==='done');

  const rb = node.querySelector('[data-action="revert-done"]');
  if(rb){ collapsed ? (show(rb), rb.title = (statusKey==='notexpected'?'Revert to previous status':'Reopen (In Progress)')) : hide(rb); }
  applyTagStyles(node, statusKey);
  updateOverdue(node);

  if(!collapsed){ const n=node.querySelector('[data-note]'); if(n) { n.style.display=''; applyNoteLayout(n); } }
}

function isFutureDashboardForDueDate(dueYMD) {
  if (!dueYMD) return false;

  const due = new Date(dueYMD);
  if (Number.isNaN(due.getTime())) return false;

  const boardEl = document.getElementById("board");
  const boardYear = Number(boardEl?.dataset.boardYear || 0);
  const boardMonth = Number(boardEl?.dataset.boardMonth || 0);

  const dueYear = due.getFullYear();
  const dueMonth = due.getMonth() + 1; // JS months are 0-based

  // If we somehow don't know the board's month/year, treat everything as "this board"
  if (!boardYear || !boardMonth) return false;

  if (dueYear > boardYear) return true;
  if (dueYear < boardYear) return false;

  // same year → compare month
  return dueMonth > boardMonth;
}


/* =========================
   Popovers
   ========================= */
const openDatePopover=(container,ymd)=>{ const pop=container.querySelector('[data-date-popover]'); const input=container.querySelector('[data-due-input]'); if(!pop||!input) return; input.value=ymd||''; pop.style.display='block'; input.focus(); }
const closeDatePopover=(container)=>{ const pop=container.querySelector('[data-date-popover]'); if(pop) pop.style.display='none'; }
const openAssigneePopover=(container,name)=>{ const pop=container.querySelector('[data-assignee-popover]'); const input=container.querySelector('[data-assignee-input]'); if(!pop||!input) return; input.value=name||''; pop.style.display='block'; input.focus(); }
const closeAssigneePopover=(container)=>{ const pop=container.querySelector('[data-assignee-popover]'); if(pop) pop.style.display='none'; }

/* =========================
   Inline editing (Title & Notes) — blocks card click while editing
   ========================= */
function setEditing(node, on) {
  if (!node) return;
  if (on) node.dataset.inlineEditing = '1';
  else delete node.dataset.inlineEditing;
}

function enableInlineTitleEdit(node, taskId) {
  const titleSpan = node.querySelector('[data-title]');
  if (!titleSpan) return;

  const stop = (e) => { e.stopPropagation(); };

  titleSpan.addEventListener('mousedown', stop);
  titleSpan.addEventListener('click', stop);

  const startEdit = () => {
    const current = (titleSpan.textContent || '').trim();
    const input = document.createElement('input');
    input.type = 'text';
    input.value = current;
    input.className = 'border border-slate-300 rounded px-2 py-1 text-sm';
    input.style.minWidth = '12rem';

    setEditing(node, true);
    titleSpan.replaceWith(input);
    input.focus();
    input.select();

    const restore = (text) => {
      const span = document.createElement('span');
      span.className = titleSpan.className || 'title-clip truncate';
      span.setAttribute('data-title', '');
      span.textContent = text;
      span.setAttribute('data-tooltip', text);
      input.replaceWith(span);
      setEditing(node, false);
      enableInlineTitleEdit(node, taskId);
    };

    const save = async () => {
      const next = input.value.trim();
      if (!next || next === current) { restore(current); return; }
      try {
        await scheduleTaskPatch(taskId, { title: next });
        restore(next);
      } catch (e) {
        console.warn('title PATCH failed', e);
        restore(current);
      }
    };

    input.addEventListener('mousedown', stop);
    input.addEventListener('click', stop);

    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { save(); stop(e); }
      else if (e.key === 'Escape') { restore(current); stop(e); }
    });
    input.addEventListener('blur', save);
  };

  titleSpan.addEventListener('dblclick', (e) => {
    e.stopPropagation();
    startEdit();
  });
}

function enableInlineNotesEdit(node, taskId) {
  const noteEl = node.querySelector('[data-note]');
  const addBtn = node.querySelector('[data-action="add-note"]');
  const noteArea = node.querySelector('[data-note-area]');
  if (!noteEl) return;

  applyNoteLayout(noteEl);

  const stop = (e) => { e.stopPropagation(); };

  noteEl.addEventListener('mousedown', stop);
  noteEl.addEventListener('click', stop);
  addBtn?.addEventListener('mousedown', stop);
  addBtn?.addEventListener('click', stop);

  const startEdit = () => {
    const current = (noteEl.textContent || '').trim();
    const area = document.createElement('textarea');
    area.value = current;
    area.rows = Math.max(2, Math.min(6, current.split('\n').length || 2));
    area.className = 'w-full border border-slate-300 rounded px-2 py-1 text-[13px]';
    area.setAttribute('maxlength', String(NOTE_MAX_CHARS));

    area.style.whiteSpace = 'pre-wrap';
    area.style.wordBreak = 'break-word';
    area.style.overflowWrap = 'anywhere';

    setEditing(node, true);
    if (noteArea) noteArea.classList.add('open');

    // Editing controls (✓ / ×)
    const actions = document.createElement('div');
    actions.className = 'note-edit-actions no-modal';
    actions.innerHTML = `
      <button type="button" class="note-btn note-btn--save" title="Save (Enter)">
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d="M20 6L9 17l-5-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
      </button>
      <button type="button" class="note-btn note-btn--cancel" title="Cancel (Esc)">
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d="M18 6L6 18M6 6l12 12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
      </button>
    `;

    // Make room if we overlay actions
    area.style.paddingRight = '2.25rem';

    // Swap in textarea & actions
    noteEl.replaceWith(area);
    if (addBtn) addBtn.style.display = 'none';
    noteArea?.appendChild(actions);
    area.focus();

    const cleanupActions = () => { try { actions.remove(); } catch {} };

    let isSaving = false; // <<< prevent double save (blur + click)

    const restore = (text) => {
      const p = document.createElement('p');
      p.className = noteEl.className || 'mt-2 text-[13px] leading-snug text-[var(--brand-text-light)]';
      p.setAttribute('data-note', '');
      p.textContent = text;
      applyNoteLayout(p);
      area.replaceWith(p);
      cleanupActions();
      setEditing(node, false);
      if (noteArea) noteArea.classList.toggle('open', !!text);
      if (addBtn) addBtn.style.display = (text && text.trim()) ? 'none' : 'inline-flex';
      enableInlineNotesEdit(node, taskId);
      requestAnimationFrame(updateTopScrollerWidth);
    };

    const save = async () => {
      if (isSaving) return;
      isSaving = true;
      const next = (area.value || '').trim().slice(0, NOTE_MAX_CHARS);
      try {
        await scheduleTaskPatch(taskId, { notes: next || null });
        restore(next);
      } catch (e) {
        console.warn('notes PATCH failed', e);
        restore(current);
      } finally {
        isSaving = false;
      }
    };

    // === >>> Fix: capture pointer BEFORE blur moves focus away
    const saveBtn = actions.querySelector('.note-btn--save');
    const cancelBtn = actions.querySelector('.note-btn--cancel');
    saveBtn?.addEventListener('pointerdown', (e) => { e.preventDefault(); e.stopPropagation(); save(); }, { capture: true });
    cancelBtn?.addEventListener('pointerdown', (e) => { e.preventDefault(); e.stopPropagation(); restore(current); }, { capture: true });

    // Keep clicks inside from bubbling
    actions.addEventListener('mousedown', stop);
    actions.addEventListener('click', stop);
    area.addEventListener('mousedown', stop);
    area.addEventListener('click', stop);

    // Fallback click handlers (still fine if blur already handled)
    saveBtn?.addEventListener('click', (e) => { e.stopPropagation(); });
    cancelBtn?.addEventListener('click', (e) => { e.stopPropagation(); });

    // Keyboard: Enter saves, Shift+Enter inserts newline, Esc cancels
    area.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); save(); }
      else if (e.key === 'Escape') { e.preventDefault(); restore(current); }
    });

    // Blur also saves (convenience)
    area.addEventListener('blur', () => { if (!isSaving) save(); });
  };

  noteEl.addEventListener('dblclick', (e) => { e.stopPropagation(); startEdit(); });
  addBtn?.addEventListener('click', (e) => { e.stopPropagation(); startEdit(); });
}

/* =========================
   Top sync scrollbar wiring
   ========================= */
let boardEl, topScrollEl, topInnerEl, gridResizeObserver;

function getPaddingX(el){
  const cs = getComputedStyle(el);
  return (parseFloat(cs.paddingLeft)||0) + (parseFloat(cs.paddingRight)||0);
}

function updateTopScrollerWidth(){
  if (!boardEl || !topScrollEl || !topInnerEl) return;
  const grid = boardEl.querySelector('.board-grid');
  const padX = getPaddingX(boardEl);
  const gridW = grid ? grid.scrollWidth : 0;
  const desired = Math.max(gridW + padX, boardEl.scrollWidth, boardEl.clientWidth);
  topInnerEl.style.width = desired + 'px';
  const hasOverflow = desired > boardEl.clientWidth + 1;
  topScrollEl.style.display = hasOverflow ? 'block' : 'none';
}

function wireTopScrollbar(){
  boardEl = document.getElementById('board');
  topScrollEl = document.getElementById('board-scroll-top');
  topInnerEl = topScrollEl?.querySelector('.board-top-scroll-inner');
  if (!boardEl || !topScrollEl || !topInnerEl) return;

  const syncFromBoard = () => {
    if (topScrollEl.scrollLeft !== boardEl.scrollLeft) topScrollEl.scrollLeft = boardEl.scrollLeft;
  };
  const syncFromTop = () => {
    if (boardEl.scrollLeft !== topScrollEl.scrollLeft) boardEl.scrollLeft = topScrollEl.scrollLeft;
  };

  boardEl.addEventListener('scroll', syncFromBoard, { passive: true });
  topScrollEl.addEventListener('scroll', syncFromTop, { passive: true });

  const grid = boardEl.querySelector('.board-grid');
  if (grid && 'ResizeObserver' in window) {
    gridResizeObserver = new ResizeObserver(() => updateTopScrollerWidth());
    gridResizeObserver.observe(grid);
  }
  window.addEventListener('resize', updateTopScrollerWidth);

  updateTopScrollerWidth();
}

/* =========================
   Drag & drop between columns
   ========================= */
let draggedCard = null;

function wireTaskDrag(node) {
  if (!node || !hasDOM()) return;

  node.setAttribute('draggable', 'true');

  node.addEventListener('dragstart', (e) => {
    // Don't allow dragging while inline-editing title/notes
    if (node.dataset.inlineEditing === '1') {
      e.preventDefault();
      return;
    }

    draggedCard = node;
    node.classList.add('dragging');

    try {
      if (e.dataTransfer) {
        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.setData('text/plain', node.dataset.taskId || '');
      }
    } catch {
      // ignore DataTransfer errors in jsdom/tests
    }
  });

  node.addEventListener('dragend', () => {
    node.classList.remove('dragging');
    draggedCard = null;
    document
      .querySelectorAll('.drop-zone.drag-over')
      .forEach((dz) => dz.classList.remove('drag-over'));
  });
}

function ensureEmptyState(dz) {
  if (!dz) return;
  const hasTask = dz.querySelector('.task-card');
  const empty = dz.querySelector('.empty-state');

  if (!hasTask && !empty) {
    const div = document.createElement('div');
    div.className = 'text-center text-brand-light py-10 select-none empty-state';
    div.textContent = 'No tasks yet.';
    dz.appendChild(div);
  } else if (hasTask && empty) {
    empty.remove();
  }
}

function wireDropZones() {
  if (!hasDOM()) return;

  document.querySelectorAll('.drop-zone').forEach((dz) => {
    // Track nested dragenter/dragleave so we don't flicker
    dz._dragDepth = 0;

    dz.addEventListener('dragenter', (e) => {
      if (!draggedCard) return;
      e.preventDefault();

      dz._dragDepth += 1;

      dz.classList.add('drag-over');
      const colSection = dz.closest('.section-col');
      if (colSection) colSection.classList.add('drag-over');
    });

    dz.addEventListener('dragover', (e) => {
      if (!draggedCard) return;
      e.preventDefault();
      if (e.dataTransfer) e.dataTransfer.dropEffect = 'move';
      // We *don't* toggle classes here anymore; dragenter handles that
    });

    dz.addEventListener('dragleave', (e) => {
      if (dz._dragDepth > 0) {
        dz._dragDepth -= 1;
      }

      if (dz._dragDepth === 0) {
        dz.classList.remove('drag-over');
        const colSection = dz.closest('.section-col');
        if (colSection) colSection.classList.remove('drag-over');
      }
    });

    dz.addEventListener('drop', (e) => {
      e.preventDefault();

      // Reset depth + highlight
      dz._dragDepth = 0;
      dz.classList.remove('drag-over');
      const colSection = dz.closest('.section-col');
      if (colSection) colSection.classList.remove('drag-over');

      const card = draggedCard;
      if (!card) return;

      const prevDz = card.closest('.drop-zone');

      // Move the card in the DOM
      if (!dz.contains(card)) {
        dz.appendChild(card);
      }

      ensureEmptyState(prevDz);
      ensureEmptyState(dz);

      const taskId = card.dataset.taskId;
      if (!taskId) return;

      // Figure out which column we dropped into
      const colSection2 = dz.closest('.section-col');
      const headerSpan =
        colSection2?.querySelector('h2 [data-col-name]');
      const stepTitle =
        dz.getAttribute('data-col-title') ||
        headerSpan?.getAttribute('data-col-title') ||
        headerSpan?.textContent?.trim() ||
        '';

      if (!stepTitle) return;

      // Get current dashboard context so we resolve the correct Step row
      const boardEl = document.getElementById('board');
      const dashIdAttr = boardEl?.getAttribute('data-dashboard-id');
      const rawDashId =
        dashIdAttr && String(dashIdAttr).trim()
          ? String(dashIdAttr).trim()
          : null;

      // Optional: send business day hint for extra safety
      const bizSpan = colSection2?.querySelector('[data-biz-day]');
      const bizDayAttr = bizSpan?.getAttribute('data-biz-day');
      let bizHint = null;
      if (bizDayAttr && String(bizDayAttr).trim()) {
        const parsed = parseInt(bizDayAttr, 10);
        if (!Number.isNaN(parsed)) bizHint = parsed;
      }

      const patch = { step_title: stepTitle };
      if (rawDashId) patch.dashboard_id = rawDashId;
      if (bizHint !== null) patch.business_day_hint = bizHint;

      scheduleTaskPatch(taskId, patch)
        .catch(err => console.warn('drag/drop PATCH failed', err));
    });
  });
}



/* =========================
   Create card (exported)
   ========================= */
export function addCardToColumn(colId, task){
  try{
    if(!hasDOM()) return;
    const col=document.getElementById(colId); if(!col){ console.error('addCardToColumn: missing column', colId); return; }
    const dz=col.querySelector('.drop-zone');
    const tmpl=document.getElementById('task-card-template');
    if(!dz||!tmpl){ console.error('addCardToColumn: missing drop-zone or template'); return; }

    const node=tmpl.content.firstElementChild.cloneNode(true);
    const taskId=ensureTaskId(task);
    node.dataset.taskId=taskId;
    node.setAttribute('data-tags', (task?.tags||'').trim());
    node.style.minWidth = '0';

    const titleEl=node.querySelector('[data-title]');
    const safeTitle=(task?.title||'Untitled').trim();
    titleEl.textContent=safeTitle; titleEl.setAttribute('data-tooltip', safeTitle);

    const noteEl = node.querySelector('[data-note]');
    const noteBtn = node.querySelector('[data-action="add-note"]');
    const noteArea = node.querySelector('[data-note-area]');
    if (noteEl) {
      const safeNote = (task?.notes ?? task?.note ?? '').toString().trim();
      noteEl.textContent = safeNote;
      applyNoteLayout(noteEl);
      if (noteBtn) noteBtn.style.display = safeNote ? 'none' : 'inline-flex';
      if (noteArea) noteArea.classList.toggle('open', !!safeNote);
    }

    const assigneeName=(task?.assignee||'Unassigned').trim();
    node.querySelector('[data-assignee]').textContent=assigneeName;
    node.querySelector('[data-avatar]').textContent=initials(assigneeName);

    const assigneeContainer=node.querySelector('[data-assignee-container]');
    const assigneeSpan=node.querySelector('[data-assignee]');
    const avatarSpan=node.querySelector('[data-avatar]');
    const assigneeSave=node.querySelector('.assignee-save');
    const assigneeCancel=node.querySelector('.assignee-cancel');
    const assigneeInput=node.querySelector('[data-assignee-input]');
    const stopEv=(e)=>e.stopPropagation();

    function openAssignee(){ const current=node.querySelector('[data-assignee]')?.textContent?.trim()||''; openAssigneePopover(assigneeContainer, current); }
    assigneeSpan?.addEventListener('click',(e)=>{ stopEv(e); openAssignee(); });
    avatarSpan?.addEventListener('click',(e)=>{ stopEv(e); openAssignee(); });
    assigneeCancel?.addEventListener('click',(e)=>{ stopEv(e); closeAssigneePopover(assigneeContainer); });
    assigneeSave?.addEventListener('click',(e)=>{ 
      stopEv(e);
      const newName=assigneeInput.value.trim()||'Unassigned';
      node.querySelector('[data-assignee]').textContent=newName;
      node.querySelector('[data-avatar]').textContent=initials(newName);
      closeAssigneePopover(assigneeContainer);
      node.dispatchEvent(new CustomEvent('task-assignee-updated',{bubbles:true,detail:{taskId,assignee:newName}}));
      scheduleTaskPatch(taskId, { assignee_name: (newName === 'Unassigned') ? null : newName })
        .catch(err => console.warn('assignee PATCH failed', err));
    });

    const dueEl=node.querySelector('[data-due]'); const dateContainer=node.querySelector('[data-date-container]');
    const dateBtn=node.querySelector('[data-date-btn]'); const dateInput=node.querySelector('[data-due-input]');
    const dateSave=node.querySelector('.date-save'); const dateCancel=node.querySelector('.date-cancel');

    const renderDue=(ymd)=>{
      if(YMD_RE.test(ymd)){
        const d=ymdToLocalDate(ymd);
        dueEl.textContent=d.toLocaleDateString();
        dueEl.setAttribute('datetime', ymd);
        node.dataset.duedate = ymd;
        updateOverdue(node);
        return true;
      }
      dueEl.textContent='—';
      dueEl.removeAttribute('datetime');
      delete node.dataset.duedate;
      updateOverdue(node);
      return false;
    };
    const setDue=(v)=>renderDue(toYMD(v));
    setDue(task?.due);

    dateBtn?.addEventListener('click',(e)=>{ 
      stopEv(e); 
      openDatePopover(dateContainer, dueEl.getAttribute('datetime')||''); 
    });
    dateCancel?.addEventListener('click',(e)=>{ 
      stopEv(e); 
      closeDatePopover(dateContainer); 
    });
    dateSave?.addEventListener('click', (e)=>{ 
      stopEv(e);
      const raw = dateInput.value || '';
      const ymd = toYMD(raw); // normalize

      // Update UI immediately
      setDue(ymd);
      closeDatePopover(dateContainer);

      // Decide if this task now belongs to a future dashboard
      const isFuture = ymd ? isFutureDashboardForDueDate(ymd) : false;

      if (isFuture) {
        const dzHere = node.closest('.drop-zone');
        if (node.parentElement) {
          node.parentElement.removeChild(node);
        }
        if (dzHere) ensureEmptyState(dzHere);

        // Derive monthKey from the new due date (YYYY-MM)
        let monthKey = null;
        if (ymd && YMD_RE.test(ymd)) {
          monthKey = ymd.slice(0, 7);
        }
        showTaskRedirectBanner(monthKey);
      }

      // Debounced DB update
      scheduleTaskPatch(taskId, { due_date: ymd || null })
        .catch((err) => { console.warn('due_date PATCH failed', err); });
    });

    // Recurring toggle UI
    const recToggle = node.querySelector('[data-recurring-toggle]');
    if (recToggle) {
      const initialRecurring = task?.is_recurring ?? true;
      node.dataset.isRecurring = initialRecurring ? '1' : '0';

      const applyRecurringUI = (flag) => {
        recToggle.setAttribute('aria-pressed', flag ? 'true' : 'false');
        recToggle.setAttribute('title', flag ? 'Recurring task' : 'One-time task');
        // dim the icon when not recurring
        recToggle.classList.toggle('opacity-30', !flag);
      };
      applyRecurringUI(initialRecurring);

      recToggle.addEventListener('click', (e) => {
        e.stopPropagation();
        const current = node.dataset.isRecurring === '1';
        const next = !current;
        node.dataset.isRecurring = next ? '1' : '0';
        applyRecurringUI(next);
        scheduleTaskPatch(taskId, { is_recurring: next })
          .catch((err) => {
            console.warn('recurring PATCH failed', err);
          });
      });
    }

    const initialKey=(task?.status||'notstarted');
    applyStatus(node, initialKey);

    node.querySelectorAll('[data-set-status]').forEach(btn=>{
      btn.addEventListener('click', (e)=>{
        e.stopPropagation();
        const newKey=btn.getAttribute('data-set-status');
        const prevKey=getStatusKey(node);
        if (newKey==='notexpected' && prevKey!=='notexpected') node.dataset.prevStatus=prevKey;
        applyStatus(node, newKey);
        emitStatusChange(node, prevKey, newKey);
        scheduleTaskPatch(taskId, { status_label: statusKeyToLabel(newKey) })
          .catch(err => console.warn('status PATCH failed', err));
      });
    });

    const revertEl=node.querySelector('[data-action="revert-done"]');
    if (revertEl){
      (initialKey==='done'||initialKey==='notexpected')?show(revertEl):hide(revertEl);
      revertEl.addEventListener('click', (e)=>{
        e.stopPropagation();
        const current=getStatusKey(node);
        if(current==='notexpected'){
          const prev=node.dataset.prevStatus||'notstarted';
          node.dataset.prevStatus='';
          applyStatus(node, prev);
          emitStatusChange(node,'notexpected',prev);
          scheduleTaskPatch(taskId, { status_label: statusKeyToLabel(prev) })
            .catch(err => console.warn('revert PATCH failed', err));
        } else {
          applyStatus(node,'progress');
          emitStatusChange(node,current,'progress');
          node.classList.remove('task-card--mini');
          scheduleTaskPatch(taskId, { status_label: 'In Progress' })
            .catch(err => console.warn('reopen PATCH failed', err));
        }
      });
    }

    node.querySelector('[data-action="delete"]')?.addEventListener('click', async (e)=>{
      e.stopPropagation();
      const t=node.querySelector('[data-title]')?.textContent?.trim()||'this task';
      const ok=confirm(`Delete "${t}"?\nThis will remove it from the board.`);
      if(!ok) return;
      try {
        await apiDeleteTask(taskId);
        node.remove();
        commentsStore.delete(taskId);
        requestAnimationFrame(updateTopScrollerWidth);
      } catch(err){
        console.error(err);
        alert('Delete failed:\n'+(err.message||err));
      }
    });

    enableInlineTitleEdit(node, taskId);
    enableInlineNotesEdit(node, taskId);

    // Make this card draggable between columns
    wireTaskDrag(node);

    const initial=STATUS_MAP[initialKey]||STATUS_MAP.notstarted;
    node.style.setProperty('--card-accent', initial.bar);
    dz.querySelector('.empty-state')?.remove();
    dz.appendChild(node);
    applyTagStyles(node, initialKey);
    updateOverdue(node);

    requestAnimationFrame(updateTopScrollerWidth);
  } catch(err){ console.error('addCardToColumn failed:', err); }
}

/* =========================
   Add form wiring + POST
   ========================= */
function getStepMetaForColumn(colId) {
  const root = document.getElementById(colId);
  const headerSpan = root?.querySelector('h2 [data-col-title]');
  const dropZone = root?.querySelector('.drop-zone');
  const title =
    headerSpan?.getAttribute('data-col-title') ||
    dropZone?.getAttribute('data-col-title') ||
    '';
  const bizDay = headerSpan?.getAttribute('data-biz-day');
  return { title, business_day: bizDay ? parseInt(bizDay, 10) : undefined };
}

async function persistTaskToDB({ title, colId, assignee, due, status, note, is_recurring }) {
  const { title: stepTitle, business_day } = getStepMetaForColumn(colId);

  // Get the current dashboard id from the board element
  const boardEl = document.getElementById('board');
  const dashIdAttr = boardEl?.getAttribute('data-dashboard-id');
  const dashboardId =
    dashIdAttr && String(dashIdAttr).trim()
      ? parseInt(dashIdAttr, 10)
      : null;

  const body = {
    title,
    step_title: stepTitle,
    business_day_hint: business_day,
    due_date: due || null,
    assignee_name: assignee || null,
    status_label: statusKeyToLabel(status || 'notstarted'),
    notes: note || null,
    // Tell backend which dashboard this task is being created from
    dashboard_id: dashboardId,
    // Recurring flag (default to true if omitted)
    is_recurring: is_recurring !== false,
  };

  // Offline / test fallback: return a task-shaped object just like the API
  if (!CAN_FETCH) {
    return {
      task_id: String(Date.now()),
      title: body.title,
      due_date: body.due_date,
      assignee: assignee ? { name: assignee } : null,
      notes: body.notes,
      is_recurring: body.is_recurring,
      dashboard_id: body.dashboard_id,
      month_key: body.due_date ? String(body.due_date).slice(0, 7) : null,
    };
  }

  const res = await fetch('api/tasks', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify(body),
    credentials: 'same-origin',
  });

  if (!res.ok) {
    let errText = '';
    try {
      errText = await res.text();
    } catch {
      // ignore
    }
    throw new Error(`POST api/tasks ${res.status}: ${errText}`);
  }

  const json = await res.json();
  // IMPORTANT: backend is already including dashboard_id + month_key in json.task
  return json.task;
}



function showTaskRedirectBanner(monthKey) {
  if (!hasDOM()) return;

  let toast = document.getElementById('task-redirect-banner');
  let textSpan;

  if (!toast) {
    toast = document.createElement('div');
    toast.id = 'task-redirect-banner';

    // Outer toast container (positioning + animation)
    Object.assign(toast.style, {
      position: 'fixed',
      left: '50%',
      top: '18%',
      transform: 'translateX(-50%) translateY(10px)', // start slightly lower for slide-in
      zIndex: '9999',
      padding: '0',
      margin: '0',
      pointerEvents: 'none',
      opacity: '0',
      transition: 'opacity 0.4s ease-out, transform 0.4s ease-out',
      maxWidth: '95vw',
    });

    // Inner content shell
    const inner = document.createElement('div');
    Object.assign(inner.style, {
      display: 'inline-flex',
      alignItems: 'center',
      gap: '10px',
      padding: '12px 20px',            // bigger padding
      borderRadius: '999px',
      background:
        'linear-gradient(135deg, #16a34a, #22c55e)', // green gradient
      color: '#ffffff',
      boxShadow: '0 14px 34px rgba(0,0,0,0.25)',
      backdropFilter: 'blur(10px)',
      border: '1px solid rgba(255,255,255,0.18)',
      fontSize: '0.95rem',             // slightly larger text
      lineHeight: '1.35',
      textAlign: 'left',
      whiteSpace: 'normal',
    });

    // Icon
    const iconWrap = document.createElement('span');
    Object.assign(iconWrap.style, {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: '22px',                   // slightly bigger icon
      height: '22px',
      borderRadius: '999px',
      backgroundColor: 'rgba(255,255,255,0.2)',
      flexShrink: '0',
    });
    iconWrap.innerHTML = `
      <svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true">
        <path d="M20 6L9 17l-5-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
    `;

    // Text wrapper
    const textWrap = document.createElement('div');
    Object.assign(textWrap.style, {
      display: 'flex',
      flexDirection: 'column',
      gap: '3px',
    });

    const titleSpan = document.createElement('span');
    titleSpan.textContent = 'Task added';
    Object.assign(titleSpan.style, {
      fontWeight: '600',
      fontSize: '0.95rem',
    });

    textSpan = document.createElement('span');
    textSpan.id = 'task-redirect-banner-text';
    Object.assign(textSpan.style, {
      fontSize: '0.85rem',
      opacity: '0.95',
    });

    textWrap.appendChild(titleSpan);
    textWrap.appendChild(textSpan);

    inner.appendChild(iconWrap);
    inner.appendChild(textWrap);
    toast.appendChild(inner);
    document.body.appendChild(toast);
  } else {
    textSpan = document.getElementById('task-redirect-banner-text');
  }

  // --- Build human-readable month (fixing off-by-one) ---
  let humanMonth = 'target';
  if (typeof monthKey === 'string' && monthKey.length === 7) {
    const [yStr, mStr] = monthKey.split('-');
    const y = parseInt(yStr, 10);
    const m = parseInt(mStr, 10); // 1–12
    if (!Number.isNaN(y) && !Number.isNaN(m) && m >= 1 && m <= 12) {
      // local date: avoid UTC → previous month issue
      const dt = new Date(y, m - 1, 1);
      humanMonth = dt.toLocaleString(undefined, {
        month: 'long',
        year: 'numeric',
      });
    } else {
      humanMonth = monthKey;
    }
  } else if (monthKey) {
    humanMonth = monthKey;
  }

  if (textSpan) {
    textSpan.textContent = `Task added to the ${humanMonth} dashboard.`;
  }

  // Animate in (fade + slide up)
  toast.style.opacity = '1';
  toast.style.transform = 'translateX(-50%) translateY(0)';

  // Clear any existing timer
  if (toast._hideTimer) {
    clearTimeout(toast._hideTimer);
  }

  // Stay visible ~4.5s, then fade + slide out
  toast._hideTimer = setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateX(-50%) translateY(-4px)';
  }, 3500);
}




export function wireAddButtons() {
  if (!document?.addEventListener) return;
  if (window.__BOARD_WIRED__) return;
  window.__BOARD_WIRED__ = true;

  const onClick = (e) => {
    // Open/close "add task" form when clicking the circle plus button
    const plus = e.target.closest?.('.add-task-btn');
    if (plus) {
      e.preventDefault();
      e.stopImmediatePropagation();
      e.stopPropagation();

      const colId = plus.dataset.col;
      const form = document.querySelector(`.add-form[data-for="${colId}"]`);
      if (!form) {
        console.warn('[board] add-form not found for', colId);
        return;
      }

      const nextOpen = !form.classList.contains('is-open');
      form.classList.toggle('is-open', nextOpen);
      form.style.setProperty('display', nextOpen ? 'block' : 'none', 'important');
      plus.setAttribute('aria-expanded', String(nextOpen));
      if (nextOpen) {
        form.querySelector('[data-field="title"]')?.focus();
      }
      return;
    }

    // Cancel button inside add-form
    const cancel = e.target.closest?.('.add-form .cancel');
    if (cancel) {
      e.preventDefault();
      e.stopImmediatePropagation();
      e.stopPropagation();

      const form = cancel.closest('.add-form');
      if (form) {
        form.classList.remove('is-open');
        form.style.setProperty('display', 'none', 'important');
        const opener = document.querySelector(
          `.add-task-btn[data-col="${form.getAttribute('data-for')}"]`
        );
        opener?.setAttribute('aria-expanded', 'false');
      }
      return;
    }
  };

  // Global click handler (capture) for opening/closing add forms
  window.addEventListener('click', onClick, true);

  // Wire all add-form save buttons
  document.querySelectorAll('.add-form').forEach((form) => {
    const saveBtn = form.querySelector('.save');
    if (!saveBtn) return;

    saveBtn.setAttribute('type', 'button');

    saveBtn.addEventListener('click', async (e) => {
      const colId = e.currentTarget.dataset.col || form.getAttribute('data-for');
      if (!colId) {
        console.error('Save clicked without column id');
        return;
      }

      const payload = {
        title: form.querySelector('[data-field="title"]')?.value.trim(),
        assignee: form.querySelector('[data-field="assignee"]')?.value.trim(),
        due: form.querySelector('[data-field="due"]')?.value,
        status:
          form.querySelector('[data-field="status"]')?.value || 'notstarted',
        note: (form.querySelector('[data-field="note"]')?.value || '')
          .trim()
          .slice(0, NOTE_MAX_CHARS),
        is_recurring:
          form.querySelector('[data-field="is_recurring"]')?.checked ?? true,
      };

      if (!payload.title) {
        alert('Please add a title');
        return;
      }

      saveBtn.disabled = true;
      saveBtn.style.opacity = '0.6';

      try {
        const created = await persistTaskToDB({ ...payload, colId });

        // Figure out which dashboard we're currently on
        const boardElNow = document.getElementById('board');
        const dashIdAttrNow = boardElNow?.getAttribute('data-dashboard-id');
        const currentDashId =
          dashIdAttrNow && String(dashIdAttrNow).trim()
            ? parseInt(dashIdAttrNow, 10)
            : null;

        // Due date from server (preferred) or the form
        const dueYMD = created?.due_date || payload.due || null;

        // Is this task for a future dashboard relative to the current board?
        const isFuture = dueYMD ? isFutureDashboardForDueDate(dueYMD) : false;

        // Server's notion of which dashboard it belongs to
        const belongsById =
          !created ||
          !created.dashboard_id ||
          !currentDashId ||
          created.dashboard_id === currentDashId;

        // Final decision: must BOTH match dashboard id AND NOT be a future month
        const belongsHere = belongsById && !isFuture;

        if (belongsHere) {
          // Normal case: render the new card in this column
          addCardToColumn(colId, {
            id: created.task_id || String(Date.now()),
            title: created.title || payload.title,
            assignee:
              created.assignee?.name || payload.assignee || 'Unassigned',
            due: created.due_date || payload.due || '',
            status: payload.status,
            notes: (created.notes ?? payload.note ?? '').slice(
              0,
              NOTE_MAX_CHARS
            ),
            is_recurring:
              created.is_recurring ?? payload.is_recurring ?? true,
          });
        } else {
          // Future-month or explicitly different dashboard → show green banner

          // Prefer backend month_key; otherwise derive YYYY-MM from due date
          let monthKey = created?.month_key || null;
          if (!monthKey && dueYMD && /^\d{4}-\d{2}-\d{2}$/.test(dueYMD)) {
            monthKey = dueYMD.slice(0, 7); // "YYYY-MM"
          }

          showTaskRedirectBanner(monthKey);
          // IMPORTANT: do NOT render this task on the current board;
          // it will show up when that month’s dashboard is loaded.
        }

        // Reset fields (always)
        ['title', 'assignee', 'due', 'note'].forEach((k) => {
          const el = form.querySelector(`[data-field="${k}"]`);
          if (el) el.value = '';
        });
        const sel = form.querySelector('[data-field="status"]');
        if (sel) sel.value = '';
        const recur = form.querySelector('[data-field="is_recurring"]');
        if (recur) recur.checked = true; // default back to recurring

        // Close the form + update aria-expanded (always)
        form.classList.remove('is-open');
        form.style.setProperty('display', 'none', 'important');
        const opener = document.querySelector(
          `.add-task-btn[data-col="${colId}"]`
        );
        if (opener) opener.setAttribute('aria-expanded', 'false');

      } catch (err) {
        console.error('Failed to create task', err);
        alert('Save failed:\n' + (err.message || err));
      } finally {
        saveBtn.disabled = false;
        saveBtn.style.opacity = '';
      }
    });
  }); // <-- closes .forEach
} // <-- closes wireAddButtons


/* =========================
   DB → UI hydration (dynamic title→column map)
   ========================= */
function buildTitleToColMap() {
  const map = new Map();
  document.querySelectorAll('section.section-col').forEach(section => {
    const colId = section.id;
    const headerTitle = section.querySelector('h2 [data-col-name]')?.getAttribute('data-col-title') || '';
    const dzTitle = section.querySelector('.drop-zone')?.getAttribute('data-col-title') || '';
    const title = headerTitle || dzTitle;
    if (title) map.set(title, colId);
  });
  return map;
}

const resetColumn=(colId)=>{
  const dz=document.querySelector(`#${colId} .drop-zone`);
  if(!dz) return;
  dz.querySelectorAll('.task-card').forEach(n=>n.remove());
  if(!dz.querySelector('.empty-state')){
    const div=document.createElement('div');
    div.className='text-center text-brand-light py-10 select-none empty-state';
    div.textContent='No tasks yet.';
    dz.appendChild(div);
  }
};

const normalizeStatusKey=(s)=>{ switch((s||'').toLowerCase()){ case 'in progress':return 'progress'; case 'stuck':return 'stuck'; case 'done':return 'done'; case 'not expected':return 'notexpected'; default:return 'notstarted'; } }

async function hydrateBoardFromDB(){
  try{
    let url = 'api/board';
    const boardEl = document.getElementById('board');
    const dashIdAttr = boardEl?.getAttribute('data-dashboard-id');
    if (dashIdAttr && String(dashIdAttr).trim()) {
      const trimmed = String(dashIdAttr).trim();
      url += `?dashboard_id=${encodeURIComponent(trimmed)}`;
    }

    const res = await fetch(url, {
      headers: { 'Accept': 'application/json' },
      credentials: 'same-origin',
    });

    if (res.status === 401) {
      document.querySelectorAll('.drop-zone .empty-state')
        .forEach(el => el.textContent = 'Please log in to see tasks.');
      return;
    }
    if(!res.ok) return;
    const data=await res.json();

    if (data && data.dashboard_id) {
      window.BOARD_DASH_ID = String(data.dashboard_id);
      const boardEl2 = document.getElementById('board');
      if (boardEl2 && !boardEl2.getAttribute('data-dashboard-id')) {
        boardEl2.setAttribute('data-dashboard-id', String(data.dashboard_id));
      }
    }

    if(!data || !Array.isArray(data.steps)) {
      requestAnimationFrame(updateTopScrollerWidth);
      return;
    }

    const titleToCol = buildTitleToColMap();
    document.querySelectorAll('section.section-col').forEach(s => resetColumn(s.id));

    for(const step of data.steps){
      const stepTitle=(step?.step_title||'').trim();
      const colId=titleToCol.get(stepTitle);
      if(!colId){ console.warn('No column for step:', stepTitle); continue; }
      const tasks=Array.isArray(step.tasks)?step.tasks:[];
      for(const t of tasks){
        addCardToColumn(colId, {
          id:       t.task_id,
          title:    t.title || 'Untitled',
          assignee: t.assignee?.name || 'Unassigned',
          due:      t.due_date || '',
          status:   normalizeStatusKey(t.status),
          notes:    (t.notes || '').slice(0, NOTE_MAX_CHARS),
          is_recurring: t.is_recurring !== false,  // default true if missing
        });
      }
    }
  }catch(err){ console.error('hydrateBoardFromDB failed:', err); }
  finally {
    requestAnimationFrame(updateTopScrollerWidth);
  }
}

/* =========================
   Bootstrap
   ========================= */
if (hasDOM()) {
  const boot = () => {
    console.log('[board] init');
    initComments();
    wireAddButtons();
    wireTopScrollbar();
    wireDropZones(); 
    hydrateBoardFromDB();
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, { once: true });
  else boot();
}
