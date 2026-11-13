(() => {
  const items = [], seen = new Set();
  const valid = value => typeof value === 'string' && /^https?:\/\//i.test(value);
  function add(url, thumbnail, title, source) {
    if (!valid(url) || !valid(thumbnail) || seen.has(url) || items.length >= 80) return;
    seen.add(url);
    items.push({url, thumbnail, title: (title || '图片').slice(0, 160), source: valid(source) ? source : url});
  }
  for (const tile of document.querySelectorAll('a.iusc[m]')) {
    try {
      const m = JSON.parse(tile.getAttribute('m'));
      const image = tile.querySelector('img');
      add(m.murl, m.turl || image?.getAttribute('data-src') || image?.currentSrc || image?.src,
          m.t || image?.alt, m.purl);
    } catch (_) {}
  }
  // Baidu exposes original URLs on some result layouts. Never substitute a still thumbnail for an original.
  for (const tile of document.querySelectorAll('[data-imgurl], [data-objurl]')) {
    const image = tile.matches('img') ? tile : tile.querySelector('img');
    add(tile.getAttribute('data-imgurl') || tile.getAttribute('data-objurl'),
        image?.getAttribute('data-src') || image?.currentSrc || image?.src, image?.alt, tile.closest('a')?.href);
  }
  return {items, title: document.title, url: location.href};
})();
