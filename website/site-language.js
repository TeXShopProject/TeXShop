(() => {
  'use strict';
  const key = 'texshop-language';
  const valid = value => value === 'en' || value === 'ja';
  const getPreference = () => {
    try { const value = localStorage.getItem(key); return valid(value) ? value : null; }
    catch (_) { return null; }
  };
  const setPreference = value => {
    try { localStorage.setItem(key, value); } catch (_) { /* Continue without persistence. */ }
  };
  document.addEventListener('DOMContentLoaded', () => {
    const languages = document.querySelector('header nav .languages');
    if (!languages) return;
    const archiveOnly = !!languages.querySelector('[lang="ja"][aria-disabled="true"]');
    const pageLanguage = document.documentElement.lang.toLowerCase().startsWith('ja') ? 'ja' : 'en';
    let preferred = getPreference();
    if (!preferred && !archiveOnly) {
      preferred = pageLanguage;
      setPreference(preferred);
    }
    languages.querySelectorAll('a[lang]').forEach(link => {
      link.addEventListener('click', () => setPreference(link.lang));
    });
    if (!archiveOnly) return;
    if (!preferred) {
      preferred = (navigator.languages || [navigator.language || 'en'])
        .map(value => value.toLowerCase().split('-')[0]).find(valid) || 'en';
    }
    // Only the archive article is English; its navigation returns to the preferred language.
    const nav = document.querySelector('header nav');
    const brand = document.querySelector('header .site-brand');
    if (brand) brand.setAttribute('href', preferred === 'ja' ? '../ja.html' : '../en.html');
    const parent = document.querySelector('.archive-pagination .archive-parent');
    if (parent) parent.setAttribute('href', preferred === 'ja' ? 'index-ja.html' : 'index.html');
    nav.querySelectorAll('a').forEach(link => {
      const href = link.getAttribute('href');
      if (href === '../downloads.html') link.setAttribute('href', preferred === 'ja' ? '../downloads-ja.html' : '../downloads.html');
      if (href === '../contact.html') link.setAttribute('href', preferred === 'ja' ? '../contact-ja.html' : '../contact.html');
      if (link.classList.contains('history-archive')) link.setAttribute('href', preferred === 'ja' ? 'index-ja.html' : 'index.html');
    });
  });
})();
