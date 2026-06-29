// static/js/logout.js — robust user dropdown + single-click logout

// Toggle the user dropdown
function initUserMenu() {
  const trigger = document.getElementById('user-menu-trigger');
  const menu = document.getElementById('user-menu');
  if (!trigger || !menu) return;

  const show = () => menu.classList.remove('hidden');
  const hide = () => menu.classList.add('hidden');
  const toggle = () => menu.classList.toggle('hidden');

  trigger.addEventListener('click', (e) => {
    e.preventDefault();
    e.stopPropagation();
    toggle();
  });

  document.addEventListener('click', (e) => {
    if (!menu.contains(e.target) && e.target !== trigger) hide();
  });
  window.addEventListener('resize', hide);
}

// Call /logout and return to landing
async function performLogout() {
  try {
    const payload = new Blob([JSON.stringify({})], { type: 'application/json' });
    if (navigator.sendBeacon) {
      navigator.sendBeacon('logout', payload);
    } else {
      await fetch('logout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        keepalive: true
      });
    }
  } catch (_) {
    // ignore network errors; we'll still navigate
  } finally {
    // After logout, unauthenticated header (Log in / Sign Up) is shown
    window.location.assign('/');
  }
}

function initLogoutLink() {
  const link = document.getElementById('logout-link');
  if (!link) return;

  // Ensure non-JS fallback is correct
  if (!link.getAttribute('href')) link.setAttribute('href', '/logout');

  link.addEventListener('click', (e) => {
    // Prevent default navigation so we can sendBeacon first
    e.preventDefault();
    e.stopPropagation(); // don't let document click close/toggle first
    performLogout();
  });
}

// ---- robust init (works even if DOMContentLoaded already fired)
function init() {
  initUserMenu();
  initLogoutLink();
}
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
