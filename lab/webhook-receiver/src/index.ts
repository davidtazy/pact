import { configFromEnv, createApp } from './server';

const config = configFromEnv();
const port = Number(process.env.PORT ?? 7070);

createApp(config).listen(port, () => {
  console.log(`webhook receiver listening on http://localhost:${port}`);
});
