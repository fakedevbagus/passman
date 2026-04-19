import { Router, Response } from 'express';
import { pool } from '../lib/db';
import { authMiddleware, AuthRequest } from '../middleware/auth';

const router = Router();

// All vault routes require authentication
router.use(authMiddleware);

// GET all vault items for authenticated user
router.get('/', async (req: AuthRequest, res: Response) => {
  try {
    const result = await pool.query(
      `SELECT id, service_name, encrypted_data, iv, category, notes, favorite, created_at, updated_at 
       FROM vault_items WHERE user_id = $1 ORDER BY favorite DESC, updated_at DESC`,
      [req.userId]
    );
    res.json(result.rows);
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// GET vault stats — MUST be before /:id routes to avoid matching "stats" as an id
router.get('/stats', async (req: AuthRequest, res: Response) => {
  try {
    const totalResult = await pool.query(
      'SELECT COUNT(*) as total FROM vault_items WHERE user_id = $1',
      [req.userId]
    );
    const favResult = await pool.query(
      'SELECT COUNT(*) as favorites FROM vault_items WHERE user_id = $1 AND favorite = true',
      [req.userId]
    );
    const catResult = await pool.query(
      `SELECT category, COUNT(*) as count FROM vault_items 
       WHERE user_id = $1 GROUP BY category ORDER BY count DESC`,
      [req.userId]
    );
    const recentResult = await pool.query(
      `SELECT service_name, updated_at FROM vault_items 
       WHERE user_id = $1 ORDER BY updated_at DESC LIMIT 5`,
      [req.userId]
    );

    res.json({
      total: parseInt(totalResult.rows[0].total),
      favorites: parseInt(favResult.rows[0].favorites),
      categories: catResult.rows,
      recentActivity: recentResult.rows,
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// POST new vault item
router.post('/', async (req: AuthRequest, res: Response) => {
  const { serviceName, encryptedData, iv, category, notes } = req.body;

  if (!serviceName || !encryptedData || !iv) {
    res.status(400).json({ error: 'serviceName, encryptedData, dan iv wajib diisi.' });
    return;
  }

  console.log('📩 Mencoba menyimpan data vault untuk user:', req.userId);

  try {
    const result = await pool.query(
      `INSERT INTO vault_items (user_id, service_name, encrypted_data, iv, category, notes) 
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [req.userId, serviceName, encryptedData, iv, category || 'general', notes || '']
    );
    console.log('✅ Data berhasil disimpan secara terenkripsi!');
    res.json({ success: true, item: result.rows[0] });
  } catch (err: any) {
    console.error('🔥 GAGAL SIMPAN VAULT:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// PUT update vault item
router.put('/:id', async (req: AuthRequest, res: Response) => {
  const { id } = req.params;
  const { serviceName, encryptedData, iv, category, notes, favorite } = req.body;

  try {
    // Verify the item belongs to user
    const check = await pool.query(
      'SELECT id FROM vault_items WHERE id = $1 AND user_id = $2',
      [id, req.userId]
    );

    if (check.rows.length === 0) {
      res.status(404).json({ error: 'Asset not found or access denied.' });
      return;
    }

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
      [serviceName, encryptedData, iv, category, notes, favorite, id, req.userId]
    );

    res.json({ success: true, item: result.rows[0] });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE vault item
router.delete('/:id', async (req: AuthRequest, res: Response) => {
  const { id } = req.params;

  try {
    const result = await pool.query(
      'DELETE FROM vault_items WHERE id = $1 AND user_id = $2 RETURNING *',
      [id, req.userId]
    );

    if (result.rowCount === 0) {
      res.status(404).json({ error: 'Asset not found or access denied.' });
      return;
    }

    res.json({ success: true, message: 'Asset deleted securely.' });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH toggle favorite
router.patch('/:id/favorite', async (req: AuthRequest, res: Response) => {
  const { id } = req.params;

  try {
    const result = await pool.query(
      `UPDATE vault_items SET favorite = NOT favorite, updated_at = NOW() 
       WHERE id = $1 AND user_id = $2 RETURNING *`,
      [id, req.userId]
    );

    if (result.rowCount === 0) {
      res.status(404).json({ error: 'Asset not found.' });
      return;
    }

    res.json({ success: true, item: result.rows[0] });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

export default router;

