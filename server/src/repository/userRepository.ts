import { pool } from '../lib/db';

export const userRepository = {
  async findByEmail(email: string) {
    const result = await pool.query(
      'SELECT id, email, auth_hash, kdf_salt, failed_login_attempts, locked_until FROM users WHERE email = $1',
      [email]
    );
    return result.rows[0] || null;
  },

  async createUser(email: string, authHash: string, kdfSalt: string) {
    const result = await pool.query(
      'INSERT INTO users (email, auth_hash, kdf_salt) VALUES ($1, $2, $3) RETURNING id',
      [email, authHash, kdfSalt]
    );
    return result.rows[0].id;
  },

  async updateAuthHash(id: string, newHash: string) {
    await pool.query('UPDATE users SET auth_hash = $1 WHERE id = $2', [newHash, id]);
  },

  async recordFailedLogin(id: string, currentAttempts: number) {
    const newAttempts = currentAttempts + 1;
    const lockUntil = newAttempts >= 5 
      ? new Date(Date.now() + 15 * 60 * 1000).toISOString() 
      : null;
      
    await pool.query(
      'UPDATE users SET failed_login_attempts = $1, locked_until = $2 WHERE id = $3',
      [newAttempts, lockUntil, id]
    );
    return newAttempts;
  },

  async resetFailedLogins(id: string) {
    await pool.query(
      'UPDATE users SET failed_login_attempts = 0, locked_until = NULL WHERE id = $1',
      [id]
    );
  }
};
