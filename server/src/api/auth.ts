import { Router, Request, Response } from 'express';
import argon2 from 'argon2';
import { pool } from '../lib/db';
import { generateToken } from '../middleware/auth';

const router = Router();

// REGISTER
router.post('/signup', async (req: Request, res: Response) => {
  const { email, master_password_hash, kdf_salt } = req.body;
  console.log('📩 Request masuk ke /api/auth/signup:', email);

  if (!email || !master_password_hash || !kdf_salt) {
    res.status(400).json({ error: 'Email, master_password_hash, dan kdf_salt wajib diisi.' });
    return;
  }

  try {
    // Hash the client-side hash again with Argon2 for storage
    const serverHash = await argon2.hash(master_password_hash, {
      type: argon2.argon2id,
      memoryCost: 65536,
      timeCost: 3,
      parallelism: 4,
    });

    const result = await pool.query(
      'INSERT INTO users (email, auth_hash, kdf_salt) VALUES ($1, $2, $3) RETURNING id',
      [email, serverHash, kdf_salt]
    );

    const userId = result.rows[0].id;
    const token = generateToken(userId, email);

    console.log('✅ User registered:', email);
    res.json({ success: true, userId, token });
  } catch (err: any) {
    if (err.code === '23505') {
      res.status(409).json({ error: 'Email sudah terdaftar.' });
      return;
    }
    console.error('🔥 Gagal Insert DB:', err.message);
    res.status(500).json({ error: 'Registration failed.' });
  }
});

// LOGIN
router.post('/login', async (req: Request, res: Response) => {
  const { email, master_password_hash } = req.body;
  console.log('📩 Request masuk ke /api/auth/login:', email);

  if (!email || !master_password_hash) {
    res.status(400).json({ error: 'Email dan master_password_hash wajib diisi.' });
    return;
  }

  try {
    const result = await pool.query(
      'SELECT id, auth_hash, kdf_salt, failed_login_attempts, locked_until FROM users WHERE email = $1',
      [email]
    );

    if (result.rows.length === 0) {
      res.status(401).json({ error: 'Email atau password salah.' });
      return;
    }

    const user = result.rows[0];

    // Check account lockout
    if (user.locked_until && new Date(user.locked_until) > new Date()) {
      const remainingMs = new Date(user.locked_until).getTime() - Date.now();
      const remainingMin = Math.ceil(remainingMs / 60000);
      res.status(429).json({ 
        error: `Akun terkunci. Coba lagi dalam ${remainingMin} menit.` 
      });
      return;
    }

    // Verify password with Argon2 (with legacy fallback)
    let isValid = false;
    const isArgonHash = user.auth_hash.startsWith('$argon2');

    if (isArgonHash) {
      isValid = await argon2.verify(user.auth_hash, master_password_hash);
    } else {
      // Legacy fallback: old users may have plaintext or SHA-256 hash stored
      isValid = user.auth_hash === master_password_hash;
      
      // Auto-upgrade to Argon2 if legacy login succeeds
      if (isValid) {
        console.log('🔄 Upgrading legacy hash to Argon2 for user:', email);
        const upgradedHash = await argon2.hash(master_password_hash, {
          type: argon2.argon2id,
          memoryCost: 65536,
          timeCost: 3,
          parallelism: 4,
        });
        await pool.query('UPDATE users SET auth_hash = $1 WHERE id = $2', [upgradedHash, user.id]);
      }
    }

    if (!isValid) {
      // Increment failed attempts
      const attempts = (user.failed_login_attempts || 0) + 1;
      const lockUntil = attempts >= 5 
        ? new Date(Date.now() + 15 * 60 * 1000).toISOString()  // Lock 15 min after 5 fails
        : null;
      
      await pool.query(
        'UPDATE users SET failed_login_attempts = $1, locked_until = $2 WHERE id = $3',
        [attempts, lockUntil, user.id]
      );

      res.status(401).json({ 
        error: 'Email atau password salah.',
        attemptsRemaining: Math.max(0, 5 - attempts)
      });
      return;
    }

    // Reset failed attempts on success
    await pool.query(
      'UPDATE users SET failed_login_attempts = 0, locked_until = NULL WHERE id = $1',
      [user.id]
    );

    const token = generateToken(user.id, email);

    console.log('✅ User logged in:', email);
    res.json({
      success: true,
      userId: user.id,
      salt: user.kdf_salt,
      token,
    });
  } catch (err: any) {
    console.error('🔥 Login error:', err.message);
    res.status(500).json({ error: 'Login failed.' });
  }
});

// VERIFY TOKEN (check if still valid)
router.get('/verify', async (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({ valid: false });
    return;
  }

  try {
    const jwt = await import('jsonwebtoken');
    const { config } = await import('../config');
    const decoded = jwt.verify(authHeader.split(' ')[1], config.jwtSecret) as any;
    res.json({ valid: true, userId: decoded.userId });
  } catch {
    res.status(401).json({ valid: false });
  }
});

export default router;

