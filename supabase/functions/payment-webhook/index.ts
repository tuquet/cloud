// ============================================================================
// TUQUET-CLOUD EDGE FUNCTION: UNIFIED MULTI-PLATFORM PAYMENT WEBHOOK
// Endpoint: POST /functions/v1/payment-webhook?gateway_id=<id>
// Architecture: Pluggable Provider Adapter + Idempotent ACID Settlement RPC
// ============================================================================

import { verifyAndParseBankWebhook } from './adapters/bank-webhook.ts';
import { verifyAndParseEWalletWebhook } from './adapters/ewallet-webhook.ts';
import { verifyAndParseIntlCryptoWebhook } from './adapters/intl-crypto-webhook.ts';
import type {
  GatewaySecretConfig,
  NormalizedWebhookSettlement,
} from './adapters/types.ts';

declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Promise<Response> | Response): void;
};

export async function handlePaymentWebhookRequest(
  req: Request,
  env: { supabaseUrl: string; serviceRoleKey: string },
): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method Not Allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const url = new URL(req.url);
  const gatewayId = url.searchParams.get('gateway_id') || 'bank_vietqr';
  const rawBody = await req.text();

  // 1. Fetch gateway metadata and isolated secret_config via service_role
  const gwRes = await fetch(
    `${env.supabaseUrl}/rest/v1/payment_gateways?id=eq.${encodeURIComponent(gatewayId)}&select=id,channel,driver,is_active`,
    {
      headers: {
        'Accept-Profile': 'billing',
        'apikey': env.serviceRoleKey,
        'Authorization': `Bearer ${env.serviceRoleKey}`,
      },
    },
  );
  const gateways = (await gwRes.json()) as Array<{
    channel: string;
    driver: string;
    id: string;
    is_active: boolean;
  }>;
  const gateway = gateways?.[0];

  if (!gateway || !gateway.is_active) {
    return new Response(
      JSON.stringify({ error: `Gateway ${gatewayId} not found or inactive` }),
      { status: 404, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const secretRes = await fetch(
    `${env.supabaseUrl}/rest/v1/payment_gateway_secrets?gateway_id=eq.${encodeURIComponent(gatewayId)}&select=secret_config`,
    {
      headers: {
        'Accept-Profile': 'billing',
        'apikey': env.serviceRoleKey,
        'Authorization': `Bearer ${env.serviceRoleKey}`,
      },
    },
  );
  const secretRows = (await secretRes.json()) as Array<{
    secret_config: GatewaySecretConfig;
  }>;
  const secretConfig = secretRows?.[0]?.secret_config || {};

  // 2. Dispatch to channel-specific webhook adapter
  let settlement: null | NormalizedWebhookSettlement = null;
  try {
    if (gateway.channel === 'bank_transfer') {
      settlement = await verifyAndParseBankWebhook(req, rawBody, secretConfig);
    } else if (gateway.channel === 'e_wallet') {
      settlement = await verifyAndParseEWalletWebhook(req, rawBody, secretConfig);
    } else if (gateway.channel === 'card_intl' || gateway.channel === 'crypto') {
      settlement = await verifyAndParseIntlCryptoWebhook(req, rawBody, secretConfig);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Webhook verification failed';
    return new Response(JSON.stringify({ error: message }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (!settlement) {
    return new Response(
      JSON.stringify({ settled: false, reason: 'ignored_or_no_matching_transfer_code' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // 3. Call atomic PostgreSQL settlement RPC (billing.settle_payment_intent)
  const settleRes = await fetch(
    `${env.supabaseUrl}/rest/v1/rpc/settle_payment_intent`,
    {
      method: 'POST',
      headers: {
        'Accept-Profile': 'billing',
        'Content-Profile': 'billing',
        'Content-Type': 'application/json',
        'apikey': env.serviceRoleKey,
        'Authorization': `Bearer ${env.serviceRoleKey}`,
      },
      body: JSON.stringify({
        _intent_id: settlement.intentId || null,
        _transfer_code: settlement.transferCode || null,
        _provider_tx_id: settlement.providerTxId,
        _actual_pay_amount: settlement.paidAmount,
        _raw_metadata: settlement.rawPayload,
        _force_approve: false,
      }),
    },
  );

  const settleData = await settleRes.json();
  return new Response(JSON.stringify(settleData), {
    status: settleRes.ok ? 200 : 500,
    headers: { 'Content-Type': 'application/json' },
  });
}

if (typeof Deno !== 'undefined' && typeof Deno.serve === 'function') {
  Deno.serve((req: Request) => {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    return handlePaymentWebhookRequest(req, { supabaseUrl, serviceRoleKey });
  });
}
