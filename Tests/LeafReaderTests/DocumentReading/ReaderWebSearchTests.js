const assert = require('assert');
const { makeSearchAPI } = require('../../../Sources/LeafReaderApp/Resources/reader-web-search.js');

class HighlightStub {
  constructor(...ranges) { this.ranges = ranges; }
  add(range) { this.ranges.push(range); return this; }
}

const highlights = new Map();
global.CSS = { highlights };
global.Highlight = HighlightStub;
global.window = {
  CSS: global.CSS,
  Highlight: HighlightStub,
  innerHeight: 900,
  scrollBy() {}
};
const scheduled = [];
global.setTimeout = (body) => { scheduled.push(body); };
global.NodeFilter = { SHOW_TEXT: 4, FILTER_REJECT: 2, FILTER_SKIP: 3, FILTER_ACCEPT: 1 };

const textNodes = ['Vokabel und Sprache', 'Noch eine Vokabel'].map((nodeValue) => ({
  nodeValue,
  parentElement: { closest() { return null; } }
}));
global.document = {
  body: {},
  createTreeWalker(_root, _what, filter) {
    const accepted = textNodes.filter((node) => filter.acceptNode(node) === NodeFilter.FILTER_ACCEPT);
    let index = -1;
    return { nextNode() { index += 1; return accepted[index] || null; } };
  },
  createRange() {
    return {
      setStart(node, offset) { this.startContainer = node; this.startOffset = offset; },
      setEnd(node, offset) { this.endContainer = node; this.endOffset = offset; },
      getBoundingClientRect() { return { top: 100 }; }
    };
  }
};

let canonicalIndexBuilds = 0;
const api = makeSearchAPI({
  installReaderOverlayStyle() {},
  leafReaderFindSearchSpans(value, query) {
    const source = String(value).toLowerCase();
    const matches = [];
    let start = source.indexOf(query);
    while (start >= 0) {
      matches.push({ start, end: start + query.length });
      start = source.indexOf(query, start + query.length);
    }
    return matches;
  },
  normalizedText(value) { return String(value || '').toLowerCase(); },
  normalizedIndexForRoot() {
    canonicalIndexBuilds += 1;
    return { text: 'cafe\u0301', mappingRuns: [] };
  },
  rangeFromNormalizedSpan() { return { getBoundingClientRect() { return { top: 100 }; } }; }
});

const literal = api.search('Vokabel', 1, true);
assert.deepStrictEqual(literal, { index: 1, total: 2 });
assert.strictEqual(canonicalIndexBuilds, 0, 'simple literal search must not build the canonical DOM index');
assert.strictEqual(highlights.get('leaf-reader-search').ranges.length, 0, 'all-result ranges are deferred past first-result delivery');
while (scheduled.length) scheduled.shift()();
assert.strictEqual(highlights.get('leaf-reader-search').ranges.length, 2);

api.search('Caf\u00e9', 1, true);
assert.strictEqual(canonicalIndexBuilds, 1, 'normalization-sensitive search retains canonical offset mapping');

console.log('ReaderWebSearchTests passed');
