(() => {
  'use strict';
  const key = 'texshop-theme';
  const valid = value => ['system', 'light', 'dark'].includes(value);
  let choice = 'system';
  try {
    const stored = localStorage.getItem(key);
    if (valid(stored)) choice = stored;
  } catch (_) { /* Storage may be disabled. */ }
  const system = window.matchMedia('(prefers-color-scheme: dark)');
  const apply = () => {
    document.documentElement.dataset.theme = choice === 'system' ? (system.matches ? 'dark' : 'light') : choice;
  };
  apply();
  system.addEventListener('change', () => { if (choice === 'system') apply(); });

  document.addEventListener('DOMContentLoaded', () => {
    const nav = document.querySelector('header nav');
    if (!nav) return;
    const japanese = document.documentElement.lang.toLowerCase().startsWith('ja');
    const labels = japanese ? ['システム', 'ライト', 'ダーク'] : ['System', 'Light', 'Dark'];
    const wrapper = document.createElement('div');
    wrapper.className = 'theme-switcher';
    const toggle = document.createElement('button');
    toggle.type = 'button';
    toggle.className = 'theme-toggle';
    toggle.setAttribute('aria-label', japanese ? '表示テーマ' : 'Appearance');
    toggle.setAttribute('title', japanese ? '表示テーマ' : 'Appearance');
    toggle.setAttribute('aria-haspopup', 'menu');
    toggle.setAttribute('aria-expanded', 'false');
    toggle.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 3a9 9 0 0 1 0 18Z" fill="currentColor"/></svg>';
    const menu = document.createElement('div');
    menu.className = 'theme-menu';
    menu.setAttribute('role', 'menu');
    menu.hidden = true;
    const buttons = ['system', 'light', 'dark'].map((value, index) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.setAttribute('role', 'menuitemradio');
      button.dataset.value = value;
      const check = document.createElement('span');
      check.className = 'theme-check';
      check.setAttribute('aria-hidden', 'true');
      check.textContent = '✓';
      button.append(check, document.createTextNode(labels[index]));
      button.addEventListener('click', () => {
        choice = value;
        try { localStorage.setItem(key, choice); } catch (_) { /* Use the choice for this page. */ }
        apply();
        update();
        close(true);
      });
      menu.append(button);
      return button;
    });
    const update = () => buttons.forEach(button => button.setAttribute('aria-checked', String(button.dataset.value === choice)));
    const close = focus => {
      menu.hidden = true;
      toggle.setAttribute('aria-expanded', 'false');
      if (focus) toggle.focus();
    };
    update();
    toggle.addEventListener('click', () => {
      if (!menu.hidden) return close(false);
      menu.hidden = false;
      toggle.setAttribute('aria-expanded', 'true');
      buttons.find(button => button.dataset.value === choice).focus();
    });
    wrapper.addEventListener('keydown', event => {
      if (event.key === 'Escape' && !menu.hidden) { event.preventDefault(); close(true); }
      else if (!menu.hidden && ['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
        event.preventDefault();
        const index = buttons.indexOf(document.activeElement);
        const next = event.key === 'Home' ? 0 : event.key === 'End' ? buttons.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length;
        buttons[next].focus();
      }
    });
    document.addEventListener('click', event => { if (!wrapper.contains(event.target)) close(false); });
    window.addEventListener('storage', event => {
      if (event.key === key || event.key === null) {
        choice = valid(event.newValue) ? event.newValue : 'system';
        apply(); update();
      }
    });
    wrapper.append(toggle, menu);
    nav.insertBefore(wrapper, nav.querySelector('.history-archive'));
  });
})();
