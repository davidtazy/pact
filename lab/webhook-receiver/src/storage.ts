import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { WebhookPayload } from './validate';

export interface StoredEvent {
  id: string;
  receivedAt: string;
  payload: WebhookPayload;
}

export interface WriteResult {
  id: string;
  duplicate: boolean;
}

export class EventStore {
  private readonly pendingDir: string;
  private readonly processingDir: string;
  private readonly processedDir: string;

  constructor(root: string) {
    this.pendingDir = path.join(root, 'pending');
    this.processingDir = path.join(root, 'processing');
    this.processedDir = path.join(root, 'processed');

    for (const dir of [
      this.pendingDir,
      this.processingDir,
      this.processedDir,
    ]) {
      fs.mkdirSync(dir, { recursive: true });
    }
  }

  write(payload: WebhookPayload): WriteResult {
    const id = this.idFor(payload);
    const target = path.join(this.pendingDir, `${id}.json`);

    if (fs.existsSync(target)) {
      return { id, duplicate: true };
    }

    const event: StoredEvent = {
      id,
      receivedAt: new Date().toISOString(),
      payload,
    };

    const temporary = `${target}.tmp`;
    fs.writeFileSync(temporary, `${JSON.stringify(event, null, 2)}\n`);
    fs.renameSync(temporary, target);

    return { id, duplicate: false };
  }

  list(): StoredEvent[] {
    return [this.pendingDir, this.processingDir, this.processedDir]
      .flatMap((dir) =>
        fs
          .readdirSync(dir)
          .filter((name) => name.endsWith('.json'))
          .map((name) => path.join(dir, name)),
      )
      .sort()
      .map((file) => JSON.parse(fs.readFileSync(file, 'utf8')) as StoredEvent);
  }

  read(id: string): StoredEvent | undefined {
    for (const dir of [
      this.pendingDir,
      this.processingDir,
      this.processedDir,
    ]) {
      const file = path.join(dir, `${id}.json`);
      if (fs.existsSync(file)) {
        return JSON.parse(fs.readFileSync(file, 'utf8')) as StoredEvent;
      }
    }

    return undefined;
  }

  private idFor(payload: WebhookPayload): string {
    return crypto
      .createHash('sha256')
      .update(`${payload.pactUrl}|${payload.providerVersionNumber}`)
      .digest('hex')
      .slice(0, 32);
  }
}
