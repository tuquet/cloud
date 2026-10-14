import type {
  GatewaySecretConfig,
  NormalizedWebhookSettlement,
} from './types.ts';

const TRANSFER_CODE_REGEX = /\b(TQ[A-Z0-9]{6})\b/i;

export function extractTransferCode(text: null | string | undefined): null | string {
  if (!text) return null;
  const match = text.match(TRANSFER_CODE_REGEX);
  return match ? match[1].toUpperCase() : null;
}

export function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/**
 * Verifies and parses Domestic Bank Transfer webhooks (SePay, PayOS, Casso, Web2M).
 */
export async function verifyAndParseBankWebhook(
  req: Request,
  rawBody: string,
  secretConfig: GatewaySecretConfig,
): Promise<null | NormalizedWebhookSettlement> {
  const expectedSecret = secretConfig.webhook_secret || secretConfig.api_key || '';
  if (!expectedSecret) {
    throw new Error('Unauthorized: Missing gateway webhook_secret configuration');
  }

  const authHeader = req.headers.get('authorization') || '';
  const tokenHeader =
    req.headers.get('x-api-key') ||
    req.headers.get('secure-token') ||
    req.headers.get('x-webhook-secret') ||
    '';

  const bearerOrApikey = authHeader.replace(/^(Bearer|Apikey)\s+/i, '').trim();
  const candidateToken = bearerOrApikey || tokenHeader.trim();

  if (!candidateToken || !constantTimeEqual(candidateToken, expectedSecret)) {
    throw new Error('Unauthorized: Invalid bank webhook credentials');
  }

  const payload = JSON.parse(rawBody) as Record<string, unknown>;

  // Support SePay ({ transferType: 'in', transferAmount, content, referenceCode, id })
  // Support Casso / PayOS / Web2M ({ data: { amount, description, reference } })
  const dataNode =
    payload.data && typeof payload.data === 'object'
      ? (payload.data as Record<string, unknown>)
      : payload;

  if (
    typeof dataNode.transferType === 'string' &&
    dataNode.transferType.toLowerCase() !== 'in'
  ) {
    return null;
  }

  const rawContent = String(
    dataNode.content ||
      dataNode.description ||
      dataNode.addInfo ||
      dataNode.memo ||
      '',
  );
  const transferCode = extractTransferCode(rawContent);
  if (!transferCode) {
    return null;
  }

  const paidAmount = Number(
    dataNode.transferAmount ?? dataNode.amount ?? dataNode.value ?? 0,
  );
  const providerTxId = String(
    dataNode.referenceCode ||
      dataNode.reference ||
      dataNode.transactionId ||
      dataNode.id ||
      '',
  );

  if (!providerTxId || !(paidAmount > 0)) {
    return null;
  }

  return {
    transferCode,
    providerTxId,
    paidAmount,
    currency: 'VND',
    rawPayload: payload,
  };
}
