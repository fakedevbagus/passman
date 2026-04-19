import { pool } from '../lib/db';

export const vaultRepository = {
  async getAllByUserId(userId: string) {
    const result = await pool.query(
      `SELECT id, service_name, encrypted_data, iv, category, notes, favorite, created_at, updated_at 
       FROM vault_items WHERE user_id = $1 ORDER BY favorite DESC, updated_at DESC`,
      [userId]
    );
    return result.rows;
  },

  async getStats(userId: string) {
    const totalResult = await pool.query('SELECT COUNT(*) as total FROM vault_items WHERE user_id = $1', [userId]);
    const favResult = await pool.query('SELECT COUNT(*) as favorites FROM vault_items WHERE user_id = $1 AND favorite = true', [userId]);
    const catResult = await pool.query(
      `SELECT category, COUNT(*) as count FROM vault_items 
       WHERE user_id = $1 GROUP BY category ORDER BY count DESC`,
      [userId]
    );
    const recentResult = await pool.query(
      `SELECT service_name, updated_at FROM vault_items 
       WHERE user_id = $1 ORDER BY updated_at DESC LIMIT 5`,
      [userId]
    );

    return {
      total: parseInt(totalResult.rows[0].total),
      favorites: parseInt(favResult.rows[0].favorites),
      categories: catResult.rows,
      recentActivity: recentResult.rows,
    };
  },

  async create(userId: string, data: { serviceName: string; encryptedData: string; iv: string; category: string; notes: string }) {
    const result = await pool.query(
      `INSERT INTO vault_items (user_id, service_name, encrypted_data, iv, category, notes) 
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [userId, data.serviceName, data.encryptedData, data.iv, data.category || 'general', data.notes || '']
    );
    return result.rows[0];
  },

  async update(id: string, userId: string, data: any) {
    const check = await pool.query('SELECT id FROM vault_items WHERE id = $1 AND user_id = $2', [id, userId]);
    if (check.rows.length === 0) return null;

    const result = await pool.query(
      `UPDATE vault_items 
       SET service_name = COALESCE($1, service_name),
           encrypted_data = COALESCE($2, encrypted_data),
           iv = COALESCE($3, iv),
           category = COALESCE($4, category),
           notes = COALESCE($5, notes),
           favorite = COALESCE($6, favorite),
           updated_at = NOW()
       WHERE id = $7 AND user_id = $8 
       RETURNING *`,
      [data.serviceName, data.encryptedData, data.iv, data.category, data.notes, data.favorite, id, userId]
    );
    return result.rows[0];
  },

  async delete(id: string, userId: string) {
    const result = await pool.query('DELETE FROM vault_items WHERE id = $1 AND user_id = $2 RETURNING *', [id, userId]);
    return result.rowCount > 0;
  },

  async toggleFavorite(id: string, userId: string) {
    const result = await pool.query(
      `UPDATE vault_items SET favorite = NOT favorite, updated_at = NOW() 
       WHERE id = $1 AND user_id = $2 RETURNING *`,
      [id, userId]
    );
    return result.rows[0] || null;
  }
};
