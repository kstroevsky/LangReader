(() => {
  const root = typeof globalThis !== 'undefined' ? globalThis : this;

  const makeSearchAPI = ({
    installReaderOverlayStyle,
    leafReaderFindSearchSpans,
    normalizedText,
    normalizedIndexForRoot,
    rangeFromNormalizedSpan
  }) => {
    let searchQuery = '';
    let searchIndex = -1;
    let searchRanges = [];
    let highlightGeneration = 0;

    const clearSearchHighlights = () => {
      searchRanges = [];
      highlightGeneration += 1;
      if (window.CSS && CSS.highlights) {
        CSS.highlights.delete('leaf-reader-search');
        CSS.highlights.delete('leaf-reader-search-current');
      }
      searchQuery = '';
      searchIndex = -1;
    };

    const findSearchRanges = (query) => {
      const needle = normalizedText
        ? normalizedText(query)
        : String(query || '').toLowerCase();
      if (!needle) return [];
      // Most interactive Find queries are simple letters/numbers. Walking text
      // nodes for those preserves literal offsets and avoids constructing the
      // whole-document normalization map before the first result can appear.
      // Queries whose normalization can change offsets retain the canonical
      // mapping path below.
      const canUseLiteralOffsets = /^[a-z0-9 ]+$/.test(needle);
      if (!canUseLiteralOffsets && normalizedIndexForRoot && rangeFromNormalizedSpan) {
        const index = normalizedIndexForRoot(document.body);
        const matches = [];
        let start = index.text.indexOf(needle);
        while (start >= 0) {
          const range = rangeFromNormalizedSpan(index, start, needle.length);
          if (range) matches.push(range);
          start = index.text.indexOf(needle, start + Math.max(1, needle.length));
        }
        return matches;
      }
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode(node) {
          const parent = node.parentElement;
          if (!parent || parent.closest('script,style,noscript')) return NodeFilter.FILTER_REJECT;
          if (!(node.nodeValue || '').toLowerCase().includes(needle)) return NodeFilter.FILTER_SKIP;
          return NodeFilter.FILTER_ACCEPT;
        }
      });
      const matches = [];
      let node;
      while ((node = walker.nextNode())) {
        const value = node.nodeValue || '';
        for (const span of leafReaderFindSearchSpans(value, needle)) {
          matches.push({ node, start: span.start, end: span.end });
        }
      }
      return matches.map((match) => ({
        node: match.node,
        start: match.start,
        end: match.end
      }));
    };

    const resolvedRange = (match) => {
      if (!match || !match.node) return match || null;
      const range = document.createRange();
      range.setStart(match.node, match.start);
      range.setEnd(match.node, match.end);
      return range;
    };

    const buildAllSearchHighlights = () => {
      const generation = ++highlightGeneration;
      if (!searchRanges.length) {
        CSS.highlights.delete('leaf-reader-search');
        return;
      }
      const highlight = new Highlight();
      CSS.highlights.set('leaf-reader-search', highlight);
      let cursor = 0;
      const appendBatch = () => {
        if (generation !== highlightGeneration) return;
        const limit = Math.min(searchRanges.length, cursor + 64);
        while (cursor < limit) {
          const range = resolvedRange(searchRanges[cursor]);
          if (range) highlight.add(range);
          cursor += 1;
        }
        if (cursor < searchRanges.length) setTimeout(appendBatch, 0);
      };
      setTimeout(appendBatch, 0);
    };

    const applySearchHighlights = (rebuildAll = false) => {
      if (!(window.CSS && CSS.highlights && window.Highlight)) return false;
      if (rebuildAll) buildAllSearchHighlights();
      const current = resolvedRange(searchRanges[searchIndex]);
      if (current) {
        CSS.highlights.set('leaf-reader-search-current', new Highlight(current));
      } else {
        CSS.highlights.delete('leaf-reader-search-current');
      }
      return true;
    };

    const search = (query, direction, reset) => {
      installReaderOverlayStyle();
      if (!(window.CSS && CSS.highlights && window.Highlight)) {
        const found = window.find(String(query || ''), false, direction < 0, true, false, true, false);
        return { index: found ? 1 : 0, total: found ? 1 : 0 };
      }
      const normalizedQuery = String(query || '').trim();
      if (!normalizedQuery) {
        clearSearchHighlights();
        return { index: 0, total: 0 };
      }
      const didReset = reset || normalizedQuery !== searchQuery;
      if (didReset) {
        searchQuery = normalizedQuery;
        searchIndex = -1;
        searchRanges = findSearchRanges(normalizedQuery);
      }
      const total = searchRanges.length;
      if (!total) return { index: 0, total: 0 };
      searchIndex = (searchIndex + (direction < 0 ? -1 : 1) + total) % total;
      applySearchHighlights(didReset);
      const current = resolvedRange(searchRanges[searchIndex]);
      const rect = current.getBoundingClientRect();
      window.scrollBy({ top: rect.top - (window.innerHeight * 0.35), behavior: 'smooth' });
      return { index: searchIndex + 1, total };
    };

    return { clearSearchHighlights, search };
  };

  const api = { makeSearchAPI };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.LeafReaderWebSearch = api;
})();
