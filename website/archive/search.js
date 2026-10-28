/* Added by Terada: local full-text search of the preserved archive pages. */
(() => {
  const bar = document.querySelector('.archive-search');
  if (!bar) return;
  const input = bar.querySelector('input');
  const results = bar.querySelector('.archive-search-results');
  const status = bar.querySelector('[role="status"]');
  const japanese = document.documentElement.lang === 'ja';
  const words = japanese ? ['アーカイブ内を検索', '検索中…', '件', '検索できませんでした。もう一度お試しください。'] : ['Search the archive', 'Searching…', 'matches', 'Search failed. Please try again.'];
  bar.querySelector('label').textContent = words[0];
  const nodes = doc => {
    const article = doc.querySelector('article.legacy');
    if (!article) return [];
    const walker = doc.createTreeWalker(article, NodeFilter.SHOW_TEXT);
    const list = [];
    while (walker.nextNode()) {
      const node = walker.currentNode;
      if (node.textContent.trim() && !node.parentElement.closest('script,style')) list.push(node);
    }
    return list;
  };
  const text = value => value.replace(/\s+/g, ' ').trim();
  function marked(target, value, query) {
    const lower = value.toLocaleLowerCase();
    const key = query.toLocaleLowerCase();
    let start = 0, at;
    while ((at = lower.indexOf(key, start)) !== -1) {
      target.append(document.createTextNode(value.slice(start, at)));
      const mark = document.createElement('mark');
      mark.textContent = value.slice(at, at + query.length);
      target.append(mark);
      start = at + query.length;
    }
    target.append(document.createTextNode(value.slice(start)));
  }
  let corpus;
  async function load() {
    if (!corpus) corpus = (async () => {
      const response = await fetch('manifest.json');
      if (!response.ok) throw new Error(response.status);
      const manifest = await response.json();
      return Promise.all(manifest.items.filter(item => item.type === 'page').map(async item => {
        const response = await fetch(item.file);
        if (!response.ok) throw new Error(response.status);
        const doc = new DOMParser().parseFromString(await response.text(), 'text/html');
        return {file: item.file, title: doc.querySelector('h1').textContent, texts: nodes(doc).map(n => text(n.textContent))};
      }));
    })().catch(error => { corpus = null; throw error; });
    return corpus;
  }
  let serial = 0, timer;
  input.addEventListener('input', () => {
    clearTimeout(timer);
    const run = ++serial;
    const query = input.value.trim();
    results.replaceChildren(); status.textContent = '';
    if (!query) return;
    timer = setTimeout(async () => {
      status.textContent = words[1];
      try {
        const pages = await load();
        if (run !== serial) return;
        let count = 0;
        const fragment = document.createDocumentFragment();
        for (const page of pages) page.texts.forEach((value, index) => {
          const at = value.toLocaleLowerCase().indexOf(query.toLocaleLowerCase());
          if (at < 0) return;
          count++;
          const li = document.createElement('li');
          const a = document.createElement('a');
          a.href = page.file + '#archive-search=' + index + ':' + encodeURIComponent(query);
          const title = document.createElement('strong'); title.textContent = page.title;
          a.append(title, document.createElement('br'));
          const begin = Math.max(0, at - 75), end = Math.min(value.length, at + query.length + 110);
          marked(a, (begin ? '…' : '') + value.slice(begin, end) + (end < value.length ? '…' : ''), query);
          li.append(a); fragment.append(li);
        });
        results.replaceChildren(fragment);
        status.textContent = count + ' ' + (!japanese && count === 1 ? 'match' : words[2]);
      } catch (error) { if (run === serial) status.textContent = words[3]; }
    }, 180);
  });
  function reveal() {
    const match = location.hash.match(/^#archive-search=(\d+):(.*)$/);
    if (!match) return;
    document.querySelectorAll('[data-archive-highlight]').forEach(span => span.replaceWith(document.createTextNode(span.textContent)));
    const node = nodes(document)[Number(match[1])];
    if (!node) return;
    let query;
    try { query = decodeURIComponent(match[2]); } catch { return; }
    if (!query) return;
    const span = document.createElement('span');
    span.dataset.archiveHighlight = '';
    marked(span, node.textContent, query);
    node.replaceWith(span);
    const target = span.querySelector('mark') || span;
    target.scrollIntoView({block: 'center'});
  }
  window.addEventListener('hashchange', reveal);
  reveal();
})();
