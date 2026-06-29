// tests/frontend/test.js
import sinon from 'sinon'
import { JSDOM } from 'jsdom'

// =========================
// Inline DOM shim
// =========================
function createDOM(html = '<!doctype html><html><body></body></html>') {
  const dom = new JSDOM(html, { url: 'http://localhost/' })
  global.window = dom.window
  global.document = dom.window.document
  global.Node = dom.window.Node
  global.HTMLElement = dom.window.HTMLElement
  global.CustomEvent = dom.window.CustomEvent
  global.requestAnimationFrame ??= (cb) => setTimeout(cb, 0)
  global.cancelAnimationFrame ??= (id) => clearTimeout(id)
  return dom
}

// =========================
// Import app modules (adjust paths if needed)
// =========================
import {
  initModalListeners,
  properEmail,
  properPasswordComplexity,
  wireLoginFormInside,
  wireSignupFormInside,
} from '../../src/dashboard/static/js/app.js'

import {
  toYMD, ymdToLocalDate, isOverdue, addCardToColumn
} from '../../src/dashboard/static/js/board.js'

// ============================================================================
// Helpers for board DOM tests
// ============================================================================
function installBoardFixture() {
  document.body.innerHTML = `
    <template id="task-card-template">
      <article class="task-card bg-white rounded-xl cursor-pointer" data-tags="">
        <div class="flex items-start justify-between gap-3 p-3">
          <div class="flex items-start gap-3 min-w-0">
            <span data-statusbar class="mt-1 h-4 w-1.5 rounded bg-slate-200 flex-shrink-0"></span>
            <div class="min-w-0">
              <div class="flex items-center gap-1.5" data-title-wrap data-fulltitle="">
                <span class="note-indicator hidden" data-note-indicator></span>
                <span class="comment-indicator hidden" data-comment-indicator></span>
                <h3 class="text-[15px] font-semibold leading-tight min-w-0">
                  <span class="title-clip truncate" data-title>New task</span>
                </h3>
              </div>
            </div>
          </div>

          <!-- Assignee (click-to-edit) -->
          <span class="inline-flex items-center gap-2 flex-shrink-0 ml-2 relative" data-assignee-container>
            <span class="inline-flex h-6 w-6 items-center justify-center rounded-full assignee-click no-modal" data-avatar>U</span>
            <span class="text-[13px] truncate max-w-[10rem] assignee-click no-modal" data-assignee>Unassigned</span>
            <div class="assignee-popover absolute right-0 mt-1 z-10 bg-white border rounded shadow p-2 no-modal" data-assignee-popover style="display:none;min-width:240px;">
              <div class="flex flex-col gap-2">
                <input type="text" class="assignee-input" data-assignee-input placeholder="Assignee name">
                <div class="flex items-center gap-2 justify-end">
                  <button type="button" class="assignee-save text-xs px-2 py-1 rounded border">Save</button>
                  <button type="button" class="assignee-cancel text-xs px-2 py-1 rounded border">Cancel</button>
                </div>
              </div>
            </div>
          </span>
        </div>

        <div class="px-3 pb-2">
          <div class="flex items-center gap-2 text-[13px] flex-nowrap">
            <span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 ring-1 ring-inset" data-chip>
              <span aria-hidden="true">●</span>
              <span class="sr-only">Status:</span>
              <span data-chip-text>Not Started</span>
            </span>

            <span class="overdue-chip hidden rounded-full px-2 py-0.5 ring-1 ring-inset" data-overdue>Overdue</span>

            <div class="relative ml-auto" data-date-container>
              <button type="button" data-date-btn class="inline-flex items-center gap-1 no-modal">
                <time data-due datetime="">—</time>
              </button>
              <div class="date-popover absolute right-0 mt-1 z-10 bg-white border rounded shadow p-2 no-modal" data-date-popover style="display:none;">
                <div class="flex items-center gap-2">
                  <input type="date" class="date-input border rounded px-2 py-1" data-due-input />
                  <button type="button" class="date-save text-xs px-2 py-1 rounded border">Save</button>
                  <button type="button" class="date-cancel text-xs px-2 py-1 rounded border">Cancel</button>
                </div>
              </div>
            </div>
          </div>
          <p class="mt-2 text-[13px] leading-snug" data-note></p>
        </div>

        <div class="px-3 pb-3">
          <div class="mt-2 flex items-center gap-1.5 flex-nowrap whitespace-nowrap overflow-x-auto" data-status-buttons>
            <button type="button" data-set-status="notexpected" class="no-modal">Not Expected</button>
            <button type="button" data-set-status="progress" class="no-modal">In Progress</button>
            <button type="button" data-set-status="stuck" class="no-modal">Stuck</button>
            <button type="button" data-set-status="done" class="no-modal">Done</button>
            <button type="button" data-action="revert-done" class="revert-btn hidden no-modal">revert</button>
            <button type="button" data-action="delete" class="no-modal">Delete</button>
          </div>
        </div>
      </article>
    </template>

    <section id="col-first"><div class="drop-zone"></div></section>
  `
}
function selectLastCard() {
  const cards = document.querySelectorAll('#col-first .drop-zone .task-card')
  return cards[cards.length - 1] || null
}

// ============================================================================
// board.js — helpers (unit tests)
// ============================================================================
QUnit.module('board.js — helpers', hooks => {
  let clock
  hooks.beforeEach(() => {
    createDOM()
    clock = sinon.useFakeTimers(new Date('2025-10-30T12:00:00Z'))
  })
  hooks.afterEach(() => {
    clock.restore()
    delete global.window
    delete global.document
    delete global.CustomEvent
  })

  QUnit.test('toYMD / ymdToLocalDate', assert => {
    assert.equal(toYMD('2025-10-05T23:59:59Z'), '2025-10-05', 'toYMD normalizes to YYYY-MM-DD')
    const d = ymdToLocalDate('2025-02-28')
    assert.ok(d instanceof Date && !Number.isNaN(d.getTime()), 'ymdToLocalDate returns valid Date')
  })

  QUnit.test('isOverdue hides for Done and Not Expected', assert => {
    assert.true(isOverdue('2025-10-01', 'progress'), 'Past date overdue for in-progress')
    assert.false(isOverdue('2025-10-31', 'progress'), 'Future date not overdue')
    assert.false(isOverdue('2025-10-01', 'done'), 'Done suppresses overdue')
    assert.false(isOverdue('2025-10-01', 'notexpected'), 'Not Expected suppresses overdue')
  })
})

// ============================================================================
// board.js — DOM interactions
// ============================================================================
QUnit.module('board.js — DOM interactions', hooks => {
  hooks.beforeEach(() => {
    createDOM()
    installBoardFixture()
  })
  hooks.afterEach(() => {
    delete global.window
    delete global.document
    delete global.CustomEvent
  })

  QUnit.test('Not Expected card is collapsed and hides overdue', assert => {
    addCardToColumn('col-first', { title:'Close Period', assignee:'Alex', due:'2025-10-20', status:'notexpected' })
    const card = selectLastCard()
    assert.ok(card, 'card created')
    assert.equal(card.querySelector('[data-assignee]').textContent.trim(), 'Alex', 'assignee set')
    assert.ok(card.classList.contains('task--notexpected'), 'has notexpected class')
    assert.ok(card.classList.contains('task-card--collapsed'), 'collapsed when Not Expected')
    assert.ok(card.querySelector('[data-overdue]').classList.contains('hidden'), 'overdue hidden')
  })

  QUnit.test('Done → Revert → In Progress + expanded', assert => {
    addCardToColumn('col-first', { title:'Post Flash JEs', assignee:'Bob', due:'2025-10-21', status:'done' })
    const card = selectLastCard()
    assert.ok(card.classList.contains('task-card--collapsed'), 'Done collapses')
    assert.ok(card.classList.contains('task-card--mini'), 'Done mini')

    const revert = card.querySelector('[data-action="revert-done"]')
    revert.dispatchEvent(new window.MouseEvent('click', { bubbles:true }))

    assert.equal(card.querySelector('[data-chip-text]').textContent.trim(), 'In Progress', 'status becomes In Progress')
    assert.notOk(card.classList.contains('task-card--collapsed'), 'expanded after revert')
    assert.notOk(card.classList.contains('task-card--mini'), 'mini removed')
  })

  QUnit.test('Assignee editor updates name + initials and fires event', assert => {
    addCardToColumn('col-first', { title:'Reconcile', assignee:'Sam', status:'progress' })
    const card = selectLastCard()

    let eventDetail = null
    card.addEventListener('task-assignee-updated', e => { eventDetail = e.detail })

    // Open editor via name click
    card.querySelector('[data-assignee]').dispatchEvent(new window.MouseEvent('click', { bubbles:true }))
    const input = card.querySelector('[data-assignee-input]')
    input.value = 'Jamie Lee'
    card.querySelector('.assignee-save').dispatchEvent(new window.MouseEvent('click', { bubbles:true }))

    assert.equal(card.querySelector('[data-assignee]').textContent.trim(), 'Jamie Lee', 'assignee updated')
    assert.equal(card.querySelector('[data-avatar]').textContent.trim(), 'JL', 'avatar initials updated')
    assert.ok(eventDetail && eventDetail.assignee === 'Jamie Lee', 'event emitted with payload')
  })

  QUnit.test('Date save stores YMD and shows local date (no off-by-one)', assert => {
    addCardToColumn('col-first', { title:'Dated Task', assignee:'Dana', due:'2025-10-15', status:'progress' })
    const card = selectLastCard()
    const due = card.querySelector('[data-due]')

    // Stored as YYYY-MM-DD
    assert.equal(due.getAttribute('datetime'), '2025-10-15', 'keeps pure YMD')
    // Shown as local date string
    const expected = ymdToLocalDate('2025-10-15').toLocaleDateString()
    assert.equal(due.textContent.trim(), expected, 'displayed date matches local formatting')
  })

  QUnit.test('Tag-driven backgrounds (overdue > stuck; notexpected suppresses)', assert => {
    addCardToColumn('col-first', { title:'A', assignee:'A', status:'progress', tags:'overdue' })
    const a = selectLastCard()
    assert.ok(a.classList.contains('task--overdue'), 'overdue tag applies background')

    addCardToColumn('col-first', { title:'B', assignee:'B', status:'progress', tags:'stuck' })
    const b = selectLastCard()
    assert.ok(b.classList.contains('task--stuck'), 'stuck tag applies background')

    addCardToColumn('col-first', { title:'C', assignee:'C', status:'notexpected', tags:'overdue' })
    const c = selectLastCard()
    assert.notOk(c.classList.contains('task--overdue'), 'notexpected suppresses overdue background')
    assert.notOk(c.classList.contains('task--stuck'), 'notexpected suppresses stuck background')
  })
})

// ============================================================================
// app.js — Modal Functionality (fetch template + open modal)
// ============================================================================
// We override fetch (window + globalThis) with a minimal stub.
// This avoids Node/undici absolute-URL requirements for "/templates/...".
QUnit.module('Modal Functionality', (hooks) => {
  let restoreWindowFetch, restoreGlobalFetch, sandbox

  hooks.beforeEach(function() {
    createDOM(`
      <!DOCTYPE html>
      <html>
        <body>
          <button class="modal-trigger" data-modal-url="/templates/_modal.html">Login</button>
          <div id="modal-container"></div>
        </body>
      </html>
    `)

    sandbox = sinon.createSandbox()

    const fakeModalHTML = `
      <div class="modal">
        <button class="close-modal-btn">&times;</button>
      </div>
    `
    const fetchResponse = {
      ok: true,
      status: 200,
      text: async () => fakeModalHTML
    }

    // Save originals
    const origWindowFetch = window.fetch
    const origGlobalFetch = globalThis.fetch

    // Install stub function directly (no sinon stub needed)
    const stub = (url) => {
      if (url === '/templates/_modal.html') return Promise.resolve(fetchResponse)
      return Promise.reject(new Error('Unstubbed URL: ' + url))
    }
    window.fetch = stub
    globalThis.fetch = stub

    // Restorers for afterEach
    restoreWindowFetch = () => {
      if (origWindowFetch === undefined) delete window.fetch
      else window.fetch = origWindowFetch
    }
    restoreGlobalFetch = () => {
      if (origGlobalFetch === undefined) delete globalThis.fetch
      else globalThis.fetch = origGlobalFetch
    }
  })

  hooks.afterEach(function() {
    sandbox.restore()
    restoreWindowFetch?.()
    restoreGlobalFetch?.()
    delete global.window
    delete global.document
    delete global.Node
    delete global.HTMLElement
    delete global.CustomEvent
    delete global.requestAnimationFrame
    delete global.cancelAnimationFrame
  })

  QUnit.test('opens the modal when the login button is clicked', async function(assert) {
    initModalListeners()

    document.querySelector('.modal-trigger').click()

    // Wait for fetch + DOM insertion
    await new Promise(r => setTimeout(r, 0))

    const modal = document.querySelector('.modal')
    assert.ok(modal, 'Modal element exists in the DOM.')
    assert.notOk(modal.classList.contains('hidden'), 'Modal is visible.')
  })
})

// ============================================================================
// app.js — Input Validation
// ============================================================================
QUnit.module('Input Validation', () => {
  QUnit.test('properEmail validates email formats', (assert) => {
    assert.true(properEmail('test@example.com'), 'Valid standard email')
    assert.true(properEmail('user.name+tag@domain.co.uk'), 'Valid multi-part domain')
    assert.true(properEmail('12345@gmail.com'), 'Valid numeric local part')

    assert.false(properEmail('plainaddress'), 'Missing @')
    assert.false(properEmail('@missing-local-part.com'), 'Missing local part')
    assert.false(properEmail('user@.com'), 'Dot directly after @')
    assert.false(properEmail('user@domain.'), 'Trailing dot in domain')
    assert.false(properEmail('user name@domain.com'), 'Spaces not allowed')
  })

  QUnit.test('properPasswordComplexity validates password rules', (assert) => {
    // Keep aligned with your implementation’s rules
    assert.true(properPasswordComplexity('aComplexPassword1!'), 'Valid password')
    assert.true(properPasswordComplexity('Another$Pass123'), 'Valid password')
    assert.true(properPasswordComplexity('Test@1234'), 'Valid password')
    assert.true(properPasswordComplexity('NOLOWERCASE1!'), 'Valid password (if lowercase not required)')

    assert.false(properPasswordComplexity('short'), 'Too short')
    assert.false(properPasswordComplexity('nouppercase1!'), 'No uppercase')
    assert.false(properPasswordComplexity('NoNumber!'), 'No digit')
    assert.false(properPasswordComplexity('NoSpecial1'), 'No special char')
  })
})

// ============================================================================
// app.js — Auth Form Validation (Refactored)
// ============================================================================

// --- Helper to fill form (can be shared) ---
function fillForm(formSelector, data) {
    for (const [key, value] of Object.entries(data)) {
        document.querySelector(`${formSelector} #${key}`).value = value
    }
}

// --- Signup Tests ---
QUnit.module('Signup Form Validation', (hooks) => {
    let sandbox, fetchStub
    let restoreWindowFetch, restoreGlobalFetch

    hooks.beforeEach(function() {
        this.sandbox = sinon.createSandbox()

        // 1. Create the DOM with ONLY the signup form
        createDOM(`
      <!doctype html><html><body>
        <div id="modal-scope">
          <form id="signup-form">
            <input id="email" />
            <input id="password" />
            <input id="first_name" />
            <input id="last_name" />
            <span id="email-error"></span>
            <span id="password-error"></span>
            <span id="form-error"></span>
            <button type="submit">Sign Up</button>
          </form>
        </div>
      </body></html>
    `)

        // 2. Stub global fetch
        const origWindowFetch = window.fetch
        const origGlobalFetch = globalThis.fetch
        const fakeResponse = {
            ok: true,
            json: async () => ({ data: { message: 'Success' } })
        }
        this.fetchStub = this.sandbox.stub().resolves(fakeResponse)
        window.fetch = this.fetchStub
        globalThis.fetch = this.fetchStub

        // Restorers
        this.restoreWindowFetch = () => {
            if (origWindowFetch === undefined) delete window.fetch
            else window.fetch = origWindowFetch
        }
        this.restoreGlobalFetch = () => {
            if (origGlobalFetch === undefined) delete globalThis.fetch
            else globalThis.fetch = origGlobalFetch
        }
    })

    hooks.afterEach(function() {
        this.sandbox.restore()
        this.restoreWindowFetch?.()
        this.restoreGlobalFetch?.()
        delete global.window
        delete global.document
        delete global.Node
        delete global.HTMLElement
        delete global.CustomEvent
        delete global.requestAnimationFrame
        delete global.cancelAnimationFrame
    })

    QUnit.test('wireSignupFormInside: shows error if fields are empty', async function(assert) {
        const scope = document.getElementById('modal-scope')
        wireSignupFormInside(scope)

        const form = scope.querySelector('#signup-form')
        const formError = form.querySelector('#form-error')

        // Form is empty by default, just submit it
        form.dispatchEvent(new window.CustomEvent('submit', { bubbles: true, cancelable: true }))
        await new Promise(r => setTimeout(r, 0)) // Wait for listener

        assert.equal(formError.textContent, 'Please enter information for all fields.', 'Form-level error is shown')
        assert.notOk(this.fetchStub.called, 'Fetch was not called')
    })

    QUnit.test('wireSignupFormInside: shows error for invalid email', async function(assert) {
        const scope = document.getElementById('modal-scope')
        wireSignupFormInside(scope)

        fillForm('#signup-form', {
            first_name: 'Test',
            last_name: 'User',
            email: 'bad-email', // Invalid
            password: 'ValidPassword1!'
        })

        const form = scope.querySelector('#signup-form')
        const emailError = form.querySelector('#email-error')

        form.dispatchEvent(new window.CustomEvent('submit', { bubbles: true, cancelable: true }))
        await new Promise(r => setTimeout(r, 0))

        assert.equal(emailError.textContent, 'Invalid email.', 'Email error is shown')
        assert.notOk(this.fetchStub.called, 'Fetch was not called')
    })

    QUnit.test('wireSignupFormInside: shows error for invalid password', async function(assert) {
        const scope = document.getElementById('modal-scope')
        wireSignupFormInside(scope)

        fillForm('#signup-form', {
            first_name: 'Test',
            last_name: 'User',
            email: 'good@email.com',
            password: 'weak' // Invalid
        })

        const form = scope.querySelector('#signup-form')
        const passwordError = form.querySelector('#password-error')

        // FIX: Dispatch event and wait
        form.dispatchEvent(new window.CustomEvent('submit', { bubbles: true, cancelable: true }))
        await new Promise(r => setTimeout(r, 0))

        assert.equal(passwordError.textContent, 'Password must be 8+ chars with uppercase, number, and symbol.', 'Password error is shown')
        assert.notOk(this.fetchStub.called, 'Fetch was not called')
    })
})

// --- Login Tests ---
QUnit.module('Login Form Validation', (hooks) => {
    let sandbox, fetchStub
    let restoreWindowFetch, restoreGlobalFetch

    hooks.beforeEach(function() {
        this.sandbox = sinon.createSandbox()

        // 1. Create the DOM with ONLY the login form
        createDOM(`
      <!doctype html><html><body>
        <div id="modal-scope">
          <form id="login-form">
            <input id="email" />
            <input id="password" />
            <span id="form-error"></span>
            <button type="submit">Login</button>
          </form>
        </div>
      </body></html>
    `)

        // 2. Stub global fetch
        const origWindowFetch = window.fetch
        const origGlobalFetch = globalThis.fetch
        const fakeResponse = {
            ok: true,
            json: async () => ({ data: { message: 'Success' } })
        }
        this.fetchStub = this.sandbox.stub().resolves(fakeResponse)
        window.fetch = this.fetchStub
        globalThis.fetch = this.fetchStub

        // Restorers
        this.restoreWindowFetch = () => {
            if (origWindowFetch === undefined) delete window.fetch
            else window.fetch = origWindowFetch
        }
        this.restoreGlobalFetch = () => {
            if (origGlobalFetch === undefined) delete globalThis.fetch
            else globalThis.fetch = origGlobalFetch
        }
    })

    hooks.afterEach(function() {
        this.sandbox.restore()
        this.restoreWindowFetch?.()
        this.restoreGlobalFetch?.()
        delete global.window
        delete global.document
        delete global.Node
        delete global.HTMLElement
        delete global.CustomEvent
        delete global.requestAnimationFrame
        delete global.cancelAnimationFrame
    })

    QUnit.test('wireLoginFormInside: shows error if fields are empty', async function(assert) {
        const scope = document.getElementById('modal-scope')
        wireLoginFormInside(scope)

        const form = scope.querySelector('#login-form')
        const formError = form.querySelector('#form-error')

        // FIX: Dispatch event and wait
        form.dispatchEvent(new window.CustomEvent('submit', { bubbles: true, cancelable: true }))
        await new Promise(r => setTimeout(r, 0))

        assert.equal(formError.textContent, 'Please enter information for all fields.', 'Form-level error is shown')
        assert.notOk(this.fetchStub.called, 'Fetch was not called')
    })
})