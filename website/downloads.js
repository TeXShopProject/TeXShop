// Added by Terada: copy the checksum for the selected download.
(() => {
  const toast = document.querySelector('.copy-toast');
  let dismissTimer;

  function notify(message, event, button) {
    clearTimeout(dismissTimer);
    toast.textContent = message;
    const buttonBounds = button.getBoundingClientRect();
    const x = event.detail > 0 ? event.clientX : buttonBounds.right;
    const y = event.detail > 0 ? event.clientY : buttonBounds.top;
    const bounds = toast.getBoundingClientRect();
    const width = document.documentElement.clientWidth;
    const height = document.documentElement.clientHeight;
    const margin = 12;
    const offset = 18;
    let left = x + offset;
    let top = y + offset;
    if (left + bounds.width > width - margin) left = x - bounds.width - offset;
    if (top + bounds.height > height - margin) top = y - bounds.height - offset;
    toast.style.left = Math.max(margin, Math.min(left, width - bounds.width - margin)) + 'px';
    toast.style.top = Math.max(margin, Math.min(top, height - bounds.height - margin)) + 'px';
    toast.classList.add('is-visible');
    dismissTimer = setTimeout(() => toast.classList.remove('is-visible'), 1600);
  }

  function copyWithSelection(text, button) {
    const field = document.createElement('textarea');
    field.value = text;
    field.readOnly = true;
    field.className = 'clipboard-field';
    document.body.append(field);
    try {
      field.select();
      if (!document.execCommand('copy')) throw new Error('Copy failed');
    } finally {
      field.remove();
      button.focus({ preventScroll: true });
    }
  }

  for (const button of document.querySelectorAll('[data-sha256]')) {
    const hash = button.dataset.sha256;
    if (!/^[a-f0-9]{64}$/.test(hash)) continue;
    button.disabled = false;
    button.addEventListener('click', async event => {
      try {
        if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
          try {
            await navigator.clipboard.writeText(hash);
          } catch {
            copyWithSelection(hash, button);
          }
        } else {
          copyWithSelection(hash, button);
        }
        notify('✔Copied!', event, button);
      } catch {
        notify(document.documentElement.lang === 'ja' ? 'コピーできませんでした' : 'Could not copy', event, button);
      }
    });
  }
})();
