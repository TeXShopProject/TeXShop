// Added by Terada: copy the checksum for the selected download.
(() => {
  const toast = document.querySelector('.copy-toast');
  let dismissTimer;

  function notify(message) {
    clearTimeout(dismissTimer);
    toast.textContent = message;
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
    button.addEventListener('click', async () => {
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
        notify('✔Copied!');
      } catch {
        notify(document.documentElement.lang === 'ja' ? 'コピーできませんでした' : 'Could not copy');
      }
    });
  }
})();
