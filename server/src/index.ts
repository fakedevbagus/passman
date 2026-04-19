import express from 'express';
import cors from 'cors';
import { config } from './config';
import { testConnection, initDatabase } from './lib/db';
import authRoutes from './api/auth';
import vaultRoutes from './api/vault';

console.log('--- MEMULAI SERVER ---');

const app = express();

// Middleware
app.use(cors({
  origin: config.cors.origin,
  credentials: config.cors.credentials,
}));
app.use(express.json({ limit: '10mb' }));

// Simple rate limiter (in-memory, good enough for self-hosted)
const requestCounts = new Map<string, { count: number; resetTime: number }>();

function rateLimiter(windowMs: number, max: number) {
  return (req: express.Request, res: express.Response, next: express.NextFunction) => {
    const ip = req.ip || req.socket.remoteAddress || 'unknown';
    const now = Date.now();
    const record = requestCounts.get(ip);
    
    if (!record || now > record.resetTime) {
      requestCounts.set(ip, { count: 1, resetTime: now + windowMs });
      return next();
    }
    
    if (record.count >= max) {
      res.status(429).json({ error: 'Too many requests. Please try again later.' });
      return;
    }
    
    record.count++;
    next();
  };
}

// Routes
app.get('/ping', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.use('/api/auth', rateLimiter(config.authRateLimit.windowMs, config.authRateLimit.max), authRoutes);
app.use('/api/vault', rateLimiter(config.rateLimit.windowMs, config.rateLimit.max), vaultRoutes);

// Global error handler
app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('💥 Unhandled error:', err.message);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
async function start() {
  await testConnection();
  await initDatabase();
  
  app.listen(config.port, () => {
    console.log(`🚀 SERVER MENYALA DI: http://localhost:${config.port}`);
    console.log(`📡 CORS origin: ${config.cors.origin}`);
  });
}

start();