import { Pool } from 'pg';
import { config } from '../config';

export const pool = new Pool({
  connectionString: config.databaseUrl,
  connectionTimeoutMillis: 5000,
});

export async function testConnection(): Promise<void> {
  console.log('Mencoba menghubungkan ke Database...');
  try {
    const client = await pool.connect();
    console.log('✅ KONEKSI DATABASE BERHASIL!');
    client.release();
  } catch (err: any) {
    console.error('❌ GAGAL KONEK DATABASE:', err.message);
    console.log('Pastikan password di .env benar dan PostgreSQL Service sedang Running.');
  }
}

// Auto-create tables if not exist
export async function initDatabase(): Promise<void> {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        email VARCHAR(255) UNIQUE NOT NULL,
        auth_hash TEXT NOT NULL,
        kdf_salt TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW(),
        failed_login_attempts INTEGER DEFAULT 0,
        locked_until TIMESTAMP DEFAULT NULL
      );
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS vault_items (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        service_name VARCHAR(255) NOT NULL,
        encrypted_data TEXT NOT NULL,
        iv TEXT NOT NULL,
        category VARCHAR(100) DEFAULT 'general',
        notes TEXT DEFAULT '',
        favorite BOOLEAN DEFAULT false,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);

    // Add columns if they don't exist (safe for existing DBs)
    const alterQueries = [
      `ALTER TABLE vault_items ADD COLUMN IF NOT EXISTS category VARCHAR(100) DEFAULT 'general'`,
      `ALTER TABLE vault_items ADD COLUMN IF NOT EXISTS notes TEXT DEFAULT ''`,
      `ALTER TABLE vault_items ADD COLUMN IF NOT EXISTS favorite BOOLEAN DEFAULT false`,
      `ALTER TABLE vault_items ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW()`,
      `ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_login_attempts INTEGER DEFAULT 0`,
      `ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP DEFAULT NULL`,
      `ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW()`,
    ];

    for (const q of alterQueries) {
      try { await pool.query(q); } catch { /* column might already exist */ }
    }

    console.log('✅ Database tables initialized');
  } catch (err: any) {
    console.error('❌ Failed to init database:', err.message);
  }
}
