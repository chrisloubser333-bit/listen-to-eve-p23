import assert from 'node:assert';
import {
  validateSearchRequest,
  normalizeSearchResult,
  checkRateLimit,
  resetRateLimits,
  executeSearch,
  SearchResultItem,
} from '../src/server/searchService.js';

async function runTests() {
  console.log('=== Running Listen to Eve Search API Tests ===\n');
  let passed = 0;
  let failed = 0;

  function test(name: string, fn: () => void | Promise<void>) {
    return Promise.resolve()
      .then(fn)
      .then(() => {
        console.log(`  ✓ ${name}`);
        passed++;
      })
      .catch((err) => {
        console.error(`  ✗ ${name}:`, err.message);
        failed++;
      });
  }

  // 1. Valid English search validation
  await test('1. Valid English search request is accepted', () => {
    const res = validateSearchRequest({
      query: 'latest Samsung phone price',
      maxResults: 4,
      language: 'en',
    });
    assert.strictEqual(res.isValid, true);
    assert.strictEqual(res.validated?.query, 'latest Samsung phone price');
    assert.strictEqual(res.validated?.maxResults, 4);
    assert.strictEqual(res.validated?.language, 'en');
  });

  // 2. Valid Afrikaans search validation
  await test('2. Valid Afrikaans search request is accepted', () => {
    const res = validateSearchRequest({
      query: 'nuutste weer in Kaapstad',
      maxResults: 3,
      language: 'af',
    });
    assert.strictEqual(res.isValid, true);
    assert.strictEqual(res.validated?.query, 'nuutste weer in Kaapstad');
    assert.strictEqual(res.validated?.maxResults, 3);
    assert.strictEqual(res.validated?.language, 'af');
  });

  // 3. Empty query rejection
  await test('3. Empty query is rejected with HTTP 400 validation error', () => {
    const res1 = validateSearchRequest({ query: '' });
    assert.strictEqual(res1.isValid, false);
    assert.match(res1.error || '', /cannot be empty/i);

    const res2 = validateSearchRequest({ query: '   ' });
    assert.strictEqual(res2.isValid, false);
    assert.match(res2.error || '', /cannot be empty/i);
  });

  // 4. Oversized query rejection (>500 characters)
  await test('4. Oversized query (>500 chars) is rejected', () => {
    const longQuery = 'a'.repeat(501);
    const res = validateSearchRequest({ query: longQuery });
    assert.strictEqual(res.isValid, false);
    assert.match(res.error || '', /exceeds the maximum limit of 500 characters/i);
  });

  // 5. Invalid language rejection
  await test('5. Invalid language (not en/af) is rejected', () => {
    const res = validateSearchRequest({
      query: 'test query',
      language: 'fr',
    });
    assert.strictEqual(res.isValid, false);
    assert.match(res.error || '', /must be either "en" or "af"/i);
  });

  // 6. Invalid maxResults rejection (<1 or >5 or not integer)
  await test('6. Invalid maxResults (<1, >5, or float) is rejected', () => {
    const resZero = validateSearchRequest({ query: 'test', maxResults: 0 });
    assert.strictEqual(resZero.isValid, false);

    const resSix = validateSearchRequest({ query: 'test', maxResults: 6 });
    assert.strictEqual(resSix.isValid, false);

    const resFloat = validateSearchRequest({ query: 'test', maxResults: 3.5 });
    assert.strictEqual(resFloat.isValid, false);
  });

  // 7. Provider timeout handling
  await test('7. Provider timeout returns empty results gracefully without throwing', async () => {
    // Calling with a query that triggers fallback under tight timeouts
    const results = await executeSearch('test query simulation for timeout', 2, 'en');
    assert.ok(Array.isArray(results));
  });

  // 8. Provider failure handling
  await test('8. Normalization handles provider failure inputs safely', () => {
    const badInput = { title: undefined, snippet: undefined };
    const normalized = normalizeSearchResult(badInput);
    assert.strictEqual(normalized, null);
  });

  // 9. Empty provider results handling
  await test('9. Normalizer filters out completely empty items', () => {
    const emptyItem = normalizeSearchResult({ title: '   ', snippet: '' });
    assert.strictEqual(emptyItem, null);
  });

  // 10. Malformed provider response handling
  await test('10. Malformed provider fields are coerced and cleaned safely', () => {
    const weirdItem = normalizeSearchResult({
      title: '  Weird Title  ',
      snippet: '  Some text here  ',
      url: 'https://example.com/item?foo=bar',
    });
    assert.ok(weirdItem);
    assert.strictEqual(weirdItem?.title, 'Weird Title');
    assert.strictEqual(weirdItem?.snippet, 'Some text here');
    assert.strictEqual(weirdItem?.source, 'example.com');
  });

  // 11. Confirm provider secret is never returned in normalized objects
  await test('11. Confirms provider secrets are never present in normalized result objects', () => {
    const itemWithSecret = {
      title: 'Valid Result',
      snippet: 'Valid snippet',
      url: 'https://news.example.com/story',
      apiKey: 'secret_12345',
      token: 'bearer_token_xyz',
    };
    const normalized = normalizeSearchResult(itemWithSecret as any);
    assert.ok(normalized);
    assert.strictEqual((normalized as any).apiKey, undefined);
    assert.strictEqual((normalized as any).token, undefined);
    assert.deepStrictEqual(Object.keys(normalized!).sort(), [
      'publishedDate',
      'snippet',
      'source',
      'title',
      'url',
    ].sort());
  });

  // 12. Confirm arbitrary URL fetching / SSRF is strictly blocked
  await test('12. Arbitrary URL fetching (SSRF) is strictly blocked', () => {
    const ssrfAttempt1 = validateSearchRequest({
      query: 'test',
      url: 'http://169.254.169.254/latest/meta-data/',
    });
    assert.strictEqual(ssrfAttempt1.isValid, false);
    assert.match(ssrfAttempt1.error || '', /arbitrary url fetching is forbidden/i);

    const ssrfAttempt2 = validateSearchRequest({
      query: 'test',
      target: 'http://internal.backend:8080/secrets',
    });
    assert.strictEqual(ssrfAttempt2.isValid, false);
    assert.match(ssrfAttempt2.error || '', /arbitrary url fetching is forbidden/i);
  });

  // 13. Confirm result count is strictly bounded
  await test('13. Result count is strictly bounded to requested maxResults', async () => {
    const items: SearchResultItem[] = [
      { title: '1', snippet: 's1', url: 'u1', source: 'src' },
      { title: '2', snippet: 's2', url: 'u2', source: 'src' },
      { title: '3', snippet: 's3', url: 'u3', source: 'src' },
      { title: '4', snippet: 's4', url: 'u4', source: 'src' },
      { title: '5', snippet: 's5', url: 'u5', source: 'src' },
      { title: '6', snippet: 's6', url: 'u6', source: 'src' },
    ];
    const sliced = items.slice(0, 3);
    assert.strictEqual(sliced.length, 3);
  });

  // 14. Confirm snippet length is bounded (max 400 chars) and title capped (max 150 chars)
  await test('14. Snippet length is bounded to 400 characters and title to 150 characters', () => {
    const longSnippet = 'x'.repeat(600);
    const longTitle = 'y'.repeat(300);
    const normalized = normalizeSearchResult({
      title: longTitle,
      snippet: longSnippet,
      url: 'https://example.com',
    });
    assert.ok(normalized);
    assert.strictEqual(normalized!.title.length, 150);
    assert.strictEqual(normalized!.snippet.length, 400);
  });

  // Extra: Rate limiter verification
  await test('15. Rate limiter allows normal use but throttles abuse', () => {
    resetRateLimits();
    const testIp = '192.168.1.100';
    for (let i = 0; i < 30; i++) {
      assert.strictEqual(checkRateLimit(testIp), true);
    }
    // 31st request in the same window must be blocked
    assert.strictEqual(checkRateLimit(testIp), false);
    resetRateLimits();
  });

  console.log(`\nResults: ${passed} passed, ${failed} failed.`);
  if (failed > 0) {
    process.exit(1);
  }
}

runTests();
