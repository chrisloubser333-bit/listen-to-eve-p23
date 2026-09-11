import express from 'express';
import path from 'path';
import dotenv from 'dotenv';
import { createServer as createViteServer } from 'vite';
import { handleSearchRoute } from './src/server/searchService.js';

dotenv.config();

const app = express();
const PORT = 3000;

// Parse JSON request bodies
app.use(express.json({ limit: '1mb' }));

// ---------------------------------------------------------------------------
// API Routes (Mounted FIRST)
// ---------------------------------------------------------------------------
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Secure, provider-independent Web Search Proxy Endpoint
app.post('/api/search', handleSearchRoute);

// ---------------------------------------------------------------------------
// Vite / Static Serving
// ---------------------------------------------------------------------------
async function startServer() {
  if (process.env.NODE_ENV !== 'production') {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), 'dist');
    app.use(express.static(distPath));
    app.get('*', (_req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`[ListenToEve Server] Running on http://0.0.0.0:${PORT}`);
  });
}

startServer();

export { app };
