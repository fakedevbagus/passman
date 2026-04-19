import { Router, Response } from 'express';
import { pool } from '../lib/db';
import { authMiddleware, AuthRequest } from '../middleware/auth';
import { vaultRepository } from '../repository/vaultRepository';

const router = Router();

// All vault routes require authentication
router.use(authMiddleware);

// GET all vault items for authenticated user
router.get('/', async (req: AuthRequest, res: Response) => {
  try {
    const items = await vaultRepository.getAllByUserId(req.userId!);
    res.json(items);
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// GET vault stats — MUST be before /:id routes to avoid matching "stats" as an id
router.get('/stats', async (req: AuthRequest, res: Response) => {
  try {
    const stats = await vaultRepository.getStats(req.userId!);
    res.json(stats);
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
    const item = await vaultRepository.create(req.userId!, { serviceName, encryptedData, iv, category, notes });
    console.log('✅ Data berhasil disimpan secara terenkripsi!');
    res.json({ success: true, item });
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
    const item = await vaultRepository.update(id, req.userId!, { serviceName, encryptedData, iv, category, notes, favorite });
    if (!item) {
      res.status(404).json({ error: 'Asset not found or access denied.' });
      return;
    }
    res.json({ success: true, item });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE vault item
router.delete('/:id', async (req: AuthRequest, res: Response) => {
  const { id } = req.params;

  try {
    const success = await vaultRepository.delete(id, req.userId!);
    if (!success) {
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
    const item = await vaultRepository.toggleFavorite(id, req.userId!);
    if (!item) {
      res.status(404).json({ error: 'Asset not found.' });
      return;
    }
    res.json({ success: true, item });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

export default router;

