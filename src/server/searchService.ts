import { Request, Response } from 'express';
import { GoogleGenAI } from '@google/genai';

export interface SearchResultItem {
  title: string;
  snippet: string;
  url: string;
  source: string;
  publishedDate?: string;
}

export interface SearchResponse {
  results: SearchResultItem[];
}

// ---------------------------------------------------------------------------
// Rate Limiting (In-memory sliding window: max 30 requests per minute per IP)
// ---------------------------------------------------------------------------
const rateLimitMap = new Map<string, number[]>();
const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const MAX_REQUESTS_PER_WINDOW = 30;

export function checkRateLimit(ip: string, now = Date.now()): boolean {
  const timestamps = rateLimitMap.get(ip) || [];
  const validTimestamps = timestamps.filter((t) => now - t < RATE_LIMIT_WINDOW_MS);

  if (validTimestamps.length >= MAX_REQUESTS_PER_WINDOW) {
    rateLimitMap.set(ip, validTimestamps);
    return false;
  }

  validTimestamps.push(now);
  rateLimitMap.set(ip, validTimestamps);
  return true;
}

export function resetRateLimits(): void {
  rateLimitMap.clear();
}

// ---------------------------------------------------------------------------
// Input Validation & SSRF Guard
// ---------------------------------------------------------------------------
export interface ValidatedSearchQuery {
  query: string;
  maxResults: number;
  language: 'en' | 'af';
}

export function validateSearchRequest(body: unknown): {
  isValid: boolean;
  error?: string;
  validated?: ValidatedSearchQuery;
} {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return { isValid: false, error: 'Request body must be a JSON object.' };
  }

  const payload = body as Record<string, unknown>;

  // Strict SSRF Guard: Reject any attempt to supply target URLs or hostnames
  const forbiddenKeys = ['url', 'target', 'uri', 'fetchUrl', 'endpoint', 'host', 'href'];
  for (const key of forbiddenKeys) {
    if (key in payload && payload[key] !== undefined && payload[key] !== null) {
      return {
        isValid: false,
        error: `Arbitrary URL fetching is forbidden. The "${key}" property is not allowed.`,
      };
    }
  }

  // Validate query
  if (typeof payload.query !== 'string') {
    return { isValid: false, error: 'The "query" field must be a non-empty string.' };
  }

  const query = payload.query.trim();
  if (query.length === 0) {
    return { isValid: false, error: 'The "query" field cannot be empty.' };
  }

  if (query.length > 500) {
    return { isValid: false, error: 'The "query" field exceeds the maximum limit of 500 characters.' };
  }

  // Validate maxResults
  let maxResults = 4;
  if (payload.maxResults !== undefined && payload.maxResults !== null) {
    if (
      typeof payload.maxResults !== 'number' ||
      !Number.isInteger(payload.maxResults) ||
      payload.maxResults < 1 ||
      payload.maxResults > 5
    ) {
      return { isValid: false, error: 'The "maxResults" field must be an integer between 1 and 5.' };
    }
    maxResults = payload.maxResults;
  }

  // Validate language
  let language: 'en' | 'af' = 'en';
  if (payload.language !== undefined && payload.language !== null) {
    if (payload.language !== 'en' && payload.language !== 'af') {
      return { isValid: false, error: 'The "language" field must be either "en" or "af".' };
    }
    language = payload.language;
  }

  return {
    isValid: true,
    validated: { query, maxResults, language },
  };
}

// ---------------------------------------------------------------------------
// Result Normalization & Truncation
// ---------------------------------------------------------------------------
export function normalizeSearchResult(
  rawItem: Partial<SearchResultItem>,
  maxSnippetLength = 400,
  maxTitleLength = 150
): SearchResultItem | null {
  const title = typeof rawItem.title === 'string' ? rawItem.title.trim() : String(rawItem.title || '').trim();
  const snippet = typeof rawItem.snippet === 'string' ? rawItem.snippet.trim() : String(rawItem.snippet || '').trim();
  const url = typeof rawItem.url === 'string' ? rawItem.url.trim() : String(rawItem.url || '').trim();

  if (!title && !snippet) return null;

  let source = typeof rawItem.source === 'string' ? rawItem.source.trim() : String(rawItem.source || '').trim();
  if (!source && url) {
    try {
      source = new URL(url).hostname.replace(/^www\./, '');
    } catch {
      source = 'web';
    }
  }

  return {
    title: title.slice(0, maxTitleLength),
    snippet: snippet.slice(0, maxSnippetLength),
    url: url || '',
    source: source || 'web',
    publishedDate: rawItem.publishedDate ? String(rawItem.publishedDate).slice(0, 50) : undefined,
  };
}

// ---------------------------------------------------------------------------
// Concrete Provider Fetchers
// ---------------------------------------------------------------------------

/**
 * Executes a search using Tavily API if TAVILY_API_KEY is available.
 */
async function searchWithTavily(
  query: string,
  apiKey: string,
  maxResults: number
): Promise<SearchResultItem[]> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 4500);

  try {
    const res = await fetch('https://api.tavily.com/search', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        query,
        max_results: maxResults,
        include_answer: false,
        search_depth: 'basic',
      }),
      signal: controller.signal,
    });

    if (!res.ok) return [];

    const data = (await res.json()) as { results?: Array<{ title?: string; content?: string; url?: string; published_date?: string }> };
    if (!data.results || !Array.isArray(data.results)) return [];

    return data.results
      .map((item) =>
        normalizeSearchResult({
          title: item.title,
          snippet: item.content,
          url: item.url,
          publishedDate: item.published_date,
        })
      )
      .filter((item): item is SearchResultItem => item !== null)
      .slice(0, maxResults);
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Executes a search using Serper API if SERPER_API_KEY is available.
 */
async function searchWithSerper(
  query: string,
  apiKey: string,
  maxResults: number,
  language: string
): Promise<SearchResultItem[]> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 4500);

  try {
    const res = await fetch('https://google.serper.dev/search', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-KEY': apiKey,
      },
      body: JSON.stringify({
        q: query,
        num: maxResults,
        hl: language === 'af' ? 'af' : 'en',
      }),
      signal: controller.signal,
    });

    if (!res.ok) return [];

    const data = (await res.json()) as { organic?: Array<{ title?: string; snippet?: string; link?: string; date?: string }> };
    if (!data.organic || !Array.isArray(data.organic)) return [];

    return data.organic
      .map((item) =>
        normalizeSearchResult({
          title: item.title,
          snippet: item.snippet,
          url: item.link,
          publishedDate: item.date,
        })
      )
      .filter((item): item is SearchResultItem => item !== null)
      .slice(0, maxResults);
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Executes a search using Brave Search API if BRAVE_SEARCH_API_KEY is available.
 */
async function searchWithBrave(
  query: string,
  apiKey: string,
  maxResults: number
): Promise<SearchResultItem[]> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 4500);

  try {
    const url = new URL('https://api.search.brave.com/res/v1/web/search');
    url.searchParams.set('q', query);
    url.searchParams.set('count', String(maxResults));

    const res = await fetch(url.toString(), {
      headers: {
        Accept: 'application/json',
        'X-Subscription-Token': apiKey,
      },
      signal: controller.signal,
    });

    if (!res.ok) return [];

    const data = (await res.json()) as { web?: { results?: Array<{ title?: string; description?: string; url?: string; page_age?: string }> } };
    const items = data.web?.results;
    if (!items || !Array.isArray(items)) return [];

    return items
      .map((item) =>
        normalizeSearchResult({
          title: item.title,
          snippet: item.description,
          url: item.url,
          publishedDate: item.page_age,
        })
      )
      .filter((item): item is SearchResultItem => item !== null)
      .slice(0, maxResults);
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Grounded search via Google GenAI with Google Search tool if GEMINI_API_KEY is available.
 */
async function searchWithGeminiGrounding(
  query: string,
  apiKey: string,
  maxResults: number
): Promise<SearchResultItem[]> {
  try {
    const ai = new GoogleGenAI({ apiKey });
    const response = await ai.models.generateContent({
      model: 'gemini-3.6-flash',
      contents: `Provide the latest factual information for the following search query: "${query}"`,
      config: {
        tools: [{ googleSearch: {} }],
      },
    });

    const candidate = response.candidates?.[0];
    const groundingMetadata = candidate?.groundingMetadata;
    const chunks = groundingMetadata?.groundingChunks || [];

    const results: SearchResultItem[] = [];
    for (const chunk of chunks) {
      if (chunk.web?.uri && chunk.web.title) {
        const item = normalizeSearchResult({
          title: chunk.web.title,
          snippet: candidate?.content?.parts?.[0]?.text?.slice(0, 300) || chunk.web.title,
          url: chunk.web.uri,
        });
        if (item && !results.some((r) => r.url === item.url)) {
          results.push(item);
          if (results.length >= maxResults) break;
        }
      }
    }

    if (results.length > 0) return results;

    // If grounding chunks weren't parsed but response text exists:
    if (candidate?.content?.parts?.[0]?.text) {
      const summaryItem = normalizeSearchResult({
        title: query,
        snippet: candidate.content.parts[0].text,
        url: '',
        source: 'google_grounding',
      });
      if (summaryItem) return [summaryItem];
    }
  } catch (e) {
    console.warn('[SearchService] Gemini grounding lookup warning:', e);
  }

  return [];
}

/**
 * Open factual search fallback (DuckDuckGo instant answer / Wikipedia API)
 * Ensures factual lookups function cleanly even when no commercial search API key is configured.
 */
async function searchWithOpenFallback(
  query: string,
  maxResults: number
): Promise<SearchResultItem[]> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 4000);

  try {
    // 1. DuckDuckGo Instant Answer API
    const ddgUrl = `https://api.duckduckgo.com/?q=${encodeURIComponent(query)}&format=json&no_html=1&skip_disambig=1`;
    const res = await fetch(ddgUrl, {
      headers: { 'User-Agent': 'ListenToEve/1.0' },
      signal: controller.signal,
    });

    if (res.ok) {
      const data = (await res.json()) as {
        Heading?: string;
        AbstractText?: string;
        AbstractURL?: string;
        AbstractSource?: string;
        RelatedTopics?: Array<{ Text?: string; FirstURL?: string }>;
      };

      const results: SearchResultItem[] = [];

      if (data.AbstractText && data.AbstractText.trim().length > 0) {
        const item = normalizeSearchResult({
          title: data.Heading || query,
          snippet: data.AbstractText,
          url: data.AbstractURL || '',
          source: data.AbstractSource || 'duckduckgo',
        });
        if (item) results.push(item);
      }

      if (data.RelatedTopics && Array.isArray(data.RelatedTopics)) {
        for (const topic of data.RelatedTopics) {
          if (topic.Text && topic.FirstURL) {
            const topicItem = normalizeSearchResult({
              title: topic.Text.split(' - ')[0] || query,
              snippet: topic.Text,
              url: topic.FirstURL,
              source: 'duckduckgo',
            });
            if (topicItem && !results.some((r) => r.url === topicItem.url)) {
              results.push(topicItem);
              if (results.length >= maxResults) break;
            }
          }
        }
      }

      if (results.length > 0) {
        return results.slice(0, maxResults);
      }
    }
  } catch {
    // Graceful fallback to Wikipedia or empty list
  } finally {
    clearTimeout(timeoutId);
  }

  // 2. Wikipedia Search API Fallback
  try {
    const wikiController = new AbortController();
    const wikiTimeoutId = setTimeout(() => wikiController.abort(), 3500);

    const wikiUrl = `https://en.wikipedia.org/w/api.php?action=opensearch&search=${encodeURIComponent(
      query
    )}&limit=${maxResults}&namespace=0&format=json`;

    const wikiRes = await fetch(wikiUrl, {
      headers: { 'User-Agent': 'ListenToEve/1.0' },
      signal: wikiController.signal,
    });
    clearTimeout(wikiTimeoutId);

    if (wikiRes.ok) {
      const wikiData = (await wikiRes.json()) as [string, string[], string[], string[]];
      const titles = wikiData[1] || [];
      const descriptions = wikiData[2] || [];
      const urls = wikiData[3] || [];

      const wikiResults: SearchResultItem[] = [];
      for (let i = 0; i < titles.length; i++) {
        if (descriptions[i] && descriptions[i].trim().length > 0) {
          const item = normalizeSearchResult({
            title: titles[i],
            snippet: descriptions[i],
            url: urls[i] || '',
            source: 'wikipedia.org',
          });
          if (item) wikiResults.push(item);
        }
      }

      if (wikiResults.length > 0) {
        return wikiResults.slice(0, maxResults);
      }
    }
  } catch {
    // Ignore and proceed to empty return
  }

  return [];
}

// ---------------------------------------------------------------------------
// Orchestrated Search Execution
// ---------------------------------------------------------------------------
export async function executeSearch(
  queryOrOptions: string | { query: string; maxResults?: number; language?: 'en' | 'af' },
  maxResults = 4,
  language: 'en' | 'af' = 'en'
): Promise<SearchResultItem[]> {
  let query: string;
  let limit = maxResults;
  let lang = language;

  if (typeof queryOrOptions === 'object' && queryOrOptions !== null) {
    query = String(queryOrOptions.query || '').trim();
    limit = queryOrOptions.maxResults ?? maxResults;
    lang = queryOrOptions.language ?? language;
  } else {
    query = String(queryOrOptions || '').trim();
  }

  const tavilyKey = process.env.TAVILY_API_KEY || process.env.SEARCH_API_KEY;
  if (tavilyKey) {
    try {
      const results = await searchWithTavily(query, tavilyKey, limit);
      if (results.length > 0) return results;
    } catch (e) {
      console.warn('[SearchService] Tavily search failed, falling back:', e);
    }
  }

  const serperKey = process.env.SERPER_API_KEY;
  if (serperKey) {
    try {
      const results = await searchWithSerper(query, serperKey, limit, lang);
      if (results.length > 0) return results;
    } catch (e) {
      console.warn('[SearchService] Serper search failed, falling back:', e);
    }
  }

  const braveKey = process.env.BRAVE_SEARCH_API_KEY;
  if (braveKey) {
    try {
      const results = await searchWithBrave(query, braveKey, limit);
      if (results.length > 0) return results;
    } catch (e) {
      console.warn('[SearchService] Brave search failed, falling back:', e);
    }
  }

  const geminiKey = process.env.GEMINI_API_KEY;
  if (geminiKey) {
    try {
      const results = await searchWithGeminiGrounding(query, geminiKey, limit);
      if (results.length > 0) return results;
    } catch (e) {
      console.warn('[SearchService] Gemini grounding failed, falling back:', e);
    }
  }

  // Open factual search fallback (DuckDuckGo / Wikipedia)
  try {
    return await searchWithOpenFallback(query, limit);
  } catch (e) {
    console.warn('[SearchService] Open fallback search failed:', e);
    return [];
  }
}

// ---------------------------------------------------------------------------
// Express Route Handler: POST /api/search
// ---------------------------------------------------------------------------
export async function handleSearchRoute(req: Request, res: Response): Promise<void> {
  // Method Check
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed. Use POST.' });
    return;
  }

  // Abuse Protection / Rate Limiting
  const clientIp = req.ip || req.socket.remoteAddress || '127.0.0.1';
  if (!checkRateLimit(clientIp)) {
    res.status(429).json({ error: 'Too many requests. Please try again shortly.' });
    return;
  }

  // Input Validation & SSRF Guard
  const validation = validateSearchRequest(req.body);
  if (!validation.isValid || !validation.validated) {
    res.status(400).json({ error: validation.error || 'Invalid request parameters.' });
    return;
  }

  const { query, maxResults, language } = validation.validated;

  try {
    const rawResults = await executeSearch(query, maxResults, language);

    // Final Normalization & Strict Bounding
    const boundedResults = rawResults
      .map((r) => normalizeSearchResult(r))
      .filter((r): r is SearchResultItem => r !== null)
      .slice(0, maxResults);

    res.status(200).json({ results: boundedResults });
  } catch (e) {
    // Never expose stack traces or provider keys to client
    console.error('[SearchService] Unhandled search error:', e);
    res.status(200).json({ results: [] });
  }
}
