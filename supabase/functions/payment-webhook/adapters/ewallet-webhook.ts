import { constantTimeEqual, extractTransferCode } from './bank-webhook.ts';
import { computeHmacSha256Hex } from './intl-crypto-webhook.ts';
import type {
  GatewaySecretConfig,
  NormalizedWebhookSettlement,
} from './types.ts';

/**
 * Verifies and parses Domestic E-Wallet webhooks (MoMo IPN, ZaloPay callback, personal MoMo listener).
 */
export async function verifyAndParseEWalletWebhook(
  req: Request,
  rawBody: string,
  secretConfig: GatewaySecretConfig,
): Promise<null | NormalizedWebhookSettlement> {
  const expectedSecret = secretConfig.webhook_secret || '';
  if (!expectedSecret) {
    throw new Error('Unauthorized: Missing e-wallet webhook_secret');
  }

  const payload = JSON.parse(rawBody) as Record<string, unknown>;
  const headerSig =
    req.headers.get('x-momo-signature') ||
    req.headers.get('x-zalopay-signature') ||
    req.headers.get('x-webhook-signature') ||
    String(payload.signature || '');

  const computedHmac = await computeHmacSha256Hex(expectedSecret, rawBody);
  const authHeader = (req.headers.get('authorization') || '')
    .replace(/^(Bearer|Apikey)\s+/i, '')
    .trim();

  const isValidHmac =
    Boolean(headerSig) && constantTimeEqual(headerSig.toLowerCase(), computedHmac.toLowerCase());
  const isValidToken =
    Boolean(authHeader) && constantTimeEqual(authHeader, expectedSecret);

  if (!isValidHmac && !isValidToken) {
    throw new Error('Unauthorized: Invalid e-wallet webhook signature');
  }

  // MoMo IPN resultCode check (0 = success)
  if (payload.resultCode !== undefined && Number(payload.resultCode) !== 0) {
    return null;
  }

  const memoText = String(
    payload.orderInfo ||
      payload.description ||
      payload.content ||
      payload.extraData ||
      payload.orderId ||
      '',
  );
  const transferCode = extractTransferCode(memoText);
  if (!transferCode) {
    return null;
  }

  const paidAmount = Number(payload.amount ?? payload.transferAmount ?? 0);
  const providerTxId = String(
    payload.transId || payload.zp_trans_id || payload.transactionId || payload.id || '',
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
