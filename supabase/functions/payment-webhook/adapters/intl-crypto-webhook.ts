import { constantTimeEqual, extractTransferCode } from './bank-webhook.ts';
import type {
  GatewaySecretConfig,
  NormalizedWebhookSettlement,
} from './types.ts';

const encoder = new TextEncoder();

export async function computeHmacSha256Hex(
  secret: string,
  message: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sigBuffer = await crypto.subtle.sign('HMAC', key, encoder.encode(message));
  return Array.from(new Uint8Array(sigBuffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Verifies and parses International Card (Stripe) & Crypto (USDT TRC20/BEP20 / Binance Pay) webhooks.
 */
export async function verifyAndParseIntlCryptoWebhook(
  req: Request,
  rawBody: string,
  secretConfig: GatewaySecretConfig,
): Promise<null | NormalizedWebhookSettlement> {
  const expectedSecret = secretConfig.webhook_secret || '';
  if (!expectedSecret) {
    throw new Error('Unauthorized: Missing international/crypto webhook_secret');
  }

  const stripeSigHeader = req.headers.get('stripe-signature');
  if (stripeSigHeader) {
    // Parse Stripe signature: t=timestamp,v1=hex
    const parts = Object.fromEntries(
      stripeSigHeader.split(',').map((item) => {
        const [k, v] = item.trim().split('=');
        return [k, v || ''];
      }),
    );
    const timestamp = parts.t || '';
    const v1Sig = parts.v1 || '';
    if (!timestamp || !v1Sig) {
      throw new Error('Unauthorized: Malformed stripe-signature header');
    }

    const expectedSig = await computeHmacSha256Hex(
      expectedSecret,
      `${timestamp}.${rawBody}`,
    );
    if (!constantTimeEqual(v1Sig.toLowerCase(), expectedSig.toLowerCase())) {
      throw new Error('Unauthorized: Invalid Stripe webhook HMAC signature');
    }

    const event = JSON.parse(rawBody) as Record<string, unknown>;
    if (
      event.type !== 'checkout.session.completed' &&
      event.type !== 'payment_intent.succeeded'
    ) {
      return null;
    }

    const dataObj = ((event.data as Record<string, unknown>)?.object || {}) as Record<
      string,
      unknown
    >;
    const metadata = (dataObj.metadata || {}) as Record<string, unknown>;
    const rawCode = String(
      metadata.transfer_code ||
        dataObj.client_reference_id ||
        dataObj.description ||
        '',
    );
    const transferCode = extractTransferCode(rawCode);
    const intentId = metadata.intent_id ? String(metadata.intent_id) : undefined;

    if (!transferCode && !intentId) {
      return null;
    }

    const cents = Number(dataObj.amount_total ?? dataObj.amount_received ?? 0);
    const paidAmount = Number((cents / 100).toFixed(2));
    const providerTxId = String(dataObj.id || event.id || '');

    return {
      intentId,
      transferCode: transferCode || undefined,
      providerTxId,
      paidAmount,
      currency: 'USD',
      rawPayload: event,
    };
  }

  // Crypto (USDT TRC20 / BEP20 / Binance Pay) HMAC verification
  const cryptoSigHeader =
    req.headers.get('x-webhook-signature') ||
    req.headers.get('binancepay-signature') ||
    '';
  const expectedCryptoSig = await computeHmacSha256Hex(expectedSecret, rawBody);

  if (
    !cryptoSigHeader ||
    !constantTimeEqual(cryptoSigHeader.toLowerCase(), expectedCryptoSig.toLowerCase())
  ) {
    throw new Error('Unauthorized: Invalid crypto webhook HMAC signature');
  }

  const payload = JSON.parse(rawBody) as Record<string, unknown>;
  if (
    payload.status &&
    String(payload.status).toLowerCase() !== 'confirmed' &&
    String(payload.status).toLowerCase() !== 'paid'
  ) {
    return null;
  }

  const transferCode = extractTransferCode(
    String(payload.memo || payload.orderInfo || payload.merchantTradeNo || ''),
  );
  const intentId = payload.intentId ? String(payload.intentId) : undefined;
  if (!transferCode && !intentId) {
    return null;
  }

  const paidAmount = Number(payload.amount ?? payload.totalFee ?? 0);
  const providerTxId = String(payload.txHash || payload.transactionId || payload.prepayId || '');

  if (!providerTxId || !(paidAmount > 0)) {
    return null;
  }

  return {
    intentId,
    transferCode: transferCode || undefined,
    providerTxId,
    paidAmount,
    currency: 'USDT',
    rawPayload: payload,
  };
}
