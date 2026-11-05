import { createApp } from './app';

const port = Number(process.env.PORT ?? 8081);

createApp().listen(port, () => {
  console.log(`provider listening on http://localhost:${port}`);
});
