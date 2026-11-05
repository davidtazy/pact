import express, { Express } from 'express';

export function createApp(): Express {
  const app = express();

  app.get('/health', (_req, res) => {
    res.status(200).json({ status: 'ok' });
  });

  app.get('/widgets/:id', (req, res) => {
    const id = req.params.id;

    if (process.env.BREAK_PROVIDER === '1') {
      res.status(200).json({ id, displayName: 'Example widget' });
      return;
    }

    res.status(200).json({ id, name: 'Example widget' });
  });

  return app;
}
