// user_menu.js — ONLY handles dropdown show/hide (no logout interception)
function initUserMenu() {
  const trigger = document.getElementById('user-menu-trigger');
  const menu = document.getElementById('user-menu');
  if (!trigger || !menu) return;

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

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initUserMenu);
} else {
  initUserMenu();
}
