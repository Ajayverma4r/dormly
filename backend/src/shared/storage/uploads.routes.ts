// shared/storage/uploads.routes.ts
import { Router, Response, NextFunction, Request } from 'express';
import { PRIVATE_UPLOAD_FOLDERS, assertValidKey, readUpload } from './file-storage';

/**
 * Serves /uploads/<folder>/<file> from the active storage. Private folders
 * (Aadhaar and other ID documents) answer 404 here; they are only served by
 * authenticated, property-scoped endpoints.
 */
export const uploadsRouter = Router();

uploadsRouter.get('/:folder/:file', async (req: Request, res: Response, next: NextFunction) => {
  const { folder, file } = req.params;
  const key = `${folder}/${file}`;
  if (PRIVATE_UPLOAD_FOLDERS.has(folder)) {
    return res.status(404).json({ error: 'Not found' });
  }
  try {
    assertValidKey(key);
  } catch {
    return res.status(404).json({ error: 'Not found' });
  }
  try {
    const stored = await readUpload(key);
    if (!stored) return res.status(404).json({ error: 'Not found' });
    res.setHeader('Content-Type', stored.contentType);
    res.setHeader('Cache-Control', 'public, max-age=86400');
    res.send(stored.body);
  } catch (err) {
    next(err);
  }
});
