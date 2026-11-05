import { z } from 'zod';

export const webhookPayloadSchema = z.object({
  pactUrl: z.string().url(),
  consumerName: z.string().min(1),
  consumerVersionNumber: z.string().min(1),
  consumerVersionBranch: z.string().optional().default(''),
  providerName: z.string().min(1),
  providerVersionNumber: z.string().min(1),
  providerVersionBranch: z.string().min(1),
});

export type WebhookPayload = z.infer<typeof webhookPayloadSchema>;

export class ValidationError extends Error {}

export interface ValidationConfig {
  pactUrlHostAllowlist: string[];
  expectedConsumer?: string;
  expectedProvider?: string;
}

export function validateWebhookPayload(
  input: unknown,
  config: ValidationConfig,
): WebhookPayload {
  const parsed = webhookPayloadSchema.safeParse(input);

  if (!parsed.success) {
    throw new ValidationError(
      `invalid webhook payload: ${parsed.error.issues
        .map((issue) => `${issue.path.join('.')}: ${issue.message}`)
        .join('; ')}`,
    );
  }

  const payload = parsed.data;
  const pactUrl = new URL(payload.pactUrl);

  if (!config.pactUrlHostAllowlist.includes(pactUrl.hostname)) {
    throw new ValidationError(
      `pactUrl host '${pactUrl.hostname}' is not allowed`,
    );
  }

  if (config.expectedConsumer && payload.consumerName !== config.expectedConsumer) {
    throw new ValidationError(
      `unexpected consumer '${payload.consumerName}', expected '${config.expectedConsumer}'`,
    );
  }

  if (config.expectedProvider && payload.providerName !== config.expectedProvider) {
    throw new ValidationError(
      `unexpected provider '${payload.providerName}', expected '${config.expectedProvider}'`,
    );
  }

  return payload;
}
