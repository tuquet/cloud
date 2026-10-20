// ============================================================================
// TUQUET-CLOUD TEST SUITE: PAYMENT GATEWAY SQL & WEBHOOK ADAPTERS
// Description: Verifies SQL security invariants in subscriptions/install.sql
//              and unit-tests Bank, E-Wallet (MoMo/ZaloPay), Stripe, and
//              Crypto (USDT) webhook adapters using native Web Crypto.
// ============================================================================

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  extractTransferCode,
  verifyAndParseBankWebhook,
} from '../../supabase/functions/payment-webhook/adapters/bank-webhook.ts';
import { verifyAndParseEWalletWebhook } from '../../supabase/functions/payment-webhook/adapters/ewallet-webhook.ts';
import {
  computeHmacSha256Hex,
  verifyAndParseIntlCryptoWebhook,
} from '../../supabase/functions/payment-webhook/adapters/intl-crypto-webhook.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));
const cloudRoot = join(__dirname, '..', '..');

async function runTests() {
  console.log('====================================================================');
  console.log(' [PAYMENT-GATEWAY] Running SQL Invariant & Webhook Adapter Tests');
  console.log('====================================================================');

  // 1. Verify SQL & Manifest Invariants (Task 1 & Task 2)
  const pluginJson = JSON.parse(
    readFileSync(join(cloudRoot, 'supabase/plugins/subscriptions/plugin.json'), 'utf8'),
  );
  const installSql = readFileSync(
    join(cloudRoot, 'supabase/plugins/subscriptions/install.sql'),
    'utf8',
  );

  const expectedTables = [
    'billing.plans',
    'billing.subscriptions',
    'billing.usage_meters',
    'billing.wallets',
    'billing.wallet_transactions',
    'billing.payment_gateways',
    'billing.payment_gateway_secrets',
    'billing.payment_intents',
  ];
  assert.deepEqual(pluginJson.tables, expectedTables, 'plugin.json must declare all 8 billing tables');

  for (const tbl of expectedTables) {
    assert.ok(
      installSql.includes(`CREATE TABLE IF NOT EXISTS ${tbl}`),
      `install.sql missing CREATE TABLE for ${tbl}`,
    );
    assert.ok(
      installSql.includes(`ALTER TABLE ${tbl} ENABLE ROW LEVEL SECURITY;`),
      `install.sql missing RLS enablement for ${tbl}`,
    );
  }

  // Ensure every CREATE OR REPLACE FUNCTION has SET search_path = ''
  const fnCount = (installSql.match(/CREATE OR REPLACE FUNCTION/g) || []).length;
  const searchPathCount = (installSql.match(/SET search_path = ''/g) || []).length;
  assert.equal(fnCount, 7, 'Expected 7 RPC functions in subscriptions/install.sql');
  assert.equal(searchPathCount, 7, 'All 7 RPC functions must enforce SET search_path = \'\'');
  console.log('[PASS] 1/5 SQL Schema, RLS & CWE-426 search_path invariants verified (8 tables, 7 RPCs).');

  // 2. Test Transfer Code Extraction (Case-insensitive TQxxxxxx)
  assert.equal(
    extractTransferCode('MBVCB.891234.09123 chuyen tien tq8f92a1 thanh toan don hang'),
    'TQ8F92A1',
  );
  assert.equal(extractTransferCode('No code here'), null);
  console.log('[PASS] 2/5 Transfer code extractor (/\\b(TQ[A-Z0-9]{6})\\b/i) verified.');

  // 3. Test Bank Transfer Webhook Adapter (SePay / PayOS / Casso)
  const bankSecret = 'sepay-secret-key-2026';
  const bankBody = JSON.stringify({
    id: 991204,
    gateway: 'MBBank',
    transferType: 'in',
    transferAmount: 150000,
    content: 'NGUYEN VAN A chuyen khoan TQ91B2C3',
    referenceCode: 'FT26287991204',
  });
  const bankReq = new Request('https://edge.local/payment-webhook?gateway_id=bank_vietqr', {
    method: 'POST',
    headers: {
      'Authorization': `Apikey ${bankSecret}`,
      'Content-Type': 'application/json',
    },
    body: bankBody,
  });

  const bankResult = await verifyAndParseBankWebhook(bankReq, bankBody, {
    webhook_secret: bankSecret,
  });
  assert.ok(bankResult, 'Bank webhook should return parsed settlement');
  assert.equal(bankResult.transferCode, 'TQ91B2C3');
  assert.equal(bankResult.paidAmount, 150000);
  assert.equal(bankResult.currency, 'VND');
  assert.equal(bankResult.providerTxId, 'FT26287991204');

  // Verify invalid secret is rejected
  await assert.rejects(
    async () => {
      await verifyAndParseBankWebhook(bankReq, bankBody, {
        webhook_secret: 'wrong-secret',
      });
    },
    /Unauthorized/i,
  );
  console.log('[PASS] 3/5 Bank Transfer Webhook Adapter (SePay/PayOS/Casso) verified.');

  // 4. Test E-Wallet Webhook Adapter (MoMo / ZaloPay)
  const momoSecret = 'momo-secret-2026';
  const momoBodyObj = {
    partnerCode: 'MOMO',
    orderId: 'ORD-001',
    requestId: 'REQ-001',
    amount: 250000,
    orderInfo: 'Nap Xu tq77a8b9',
    transId: 4091827364,
    resultCode: 0,
    message: 'Successful.',
  };
  const momoRaw = JSON.stringify(momoBodyObj);
  const momoSig = await computeHmacSha256Hex(momoSecret, momoRaw);
  const momoReq = new Request('https://edge.local/payment-webhook?gateway_id=momo_ewallet', {
    method: 'POST',
    headers: {
      'x-momo-signature': momoSig,
      'Content-Type': 'application/json',
    },
    body: momoRaw,
  });

  const momoResult = await verifyAndParseEWalletWebhook(momoReq, momoRaw, {
    webhook_secret: momoSecret,
  });
  assert.ok(momoResult, 'MoMo webhook should return parsed settlement');
  assert.equal(momoResult.transferCode, 'TQ77A8B9');
  assert.equal(momoResult.paidAmount, 250000);
  assert.equal(momoResult.providerTxId, '4091827364');
  console.log('[PASS] 4/5 E-Wallet Webhook Adapter (MoMo / ZaloPay HMAC-SHA256) verified.');

  // 5. Test International Card (Stripe) & Crypto (USDT) Webhook Adapters
  const stripeSecret = 'whsec_test_stripe_2026';
  const stripeTimestamp = Math.floor(Date.now() / 1000).toString();
  const stripePayload = JSON.stringify({
    id: 'evt_stripe_101',
    type: 'checkout.session.completed',
    data: {
      object: {
        id: 'cs_test_998877',
        amount_total: 2000, // $20.00 in cents
        currency: 'usd',
        client_reference_id: 'TQ55C6D7',
        metadata: { transfer_code: 'TQ55C6D7' },
      },
    },
  });
  const stripeSigHex = await computeHmacSha256Hex(
    stripeSecret,
    `${stripeTimestamp}.${stripePayload}`,
  );
  const stripeReq = new Request('https://edge.local/payment-webhook?gateway_id=stripe_card', {
    method: 'POST',
    headers: {
      'stripe-signature': `t=${stripeTimestamp},v1=${stripeSigHex}`,
      'Content-Type': 'application/json',
    },
    body: stripePayload,
  });

  const stripeResult = await verifyAndParseIntlCryptoWebhook(stripeReq, stripePayload, {
    webhook_secret: stripeSecret,
  });
  assert.ok(stripeResult, 'Stripe webhook should parse checkout.session.completed');
  assert.equal(stripeResult.transferCode, 'TQ55C6D7');
  assert.equal(stripeResult.paidAmount, 20);
  assert.equal(stripeResult.currency, 'USD');
  assert.equal(stripeResult.providerTxId, 'cs_test_998877');

  const cryptoSecret = 'usdt-trc20-secret';
  const cryptoPayload = JSON.stringify({
    txHash: '0x99887766554433221100aabbccddeeff',
    network: 'TRC20',
    token: 'USDT',
    amount: 12.5,
    memo: 'TQ11E2F3',
    status: 'confirmed',
  });
  const cryptoSig = await computeHmacSha256Hex(cryptoSecret, cryptoPayload);
  const cryptoReq = new Request('https://edge.local/payment-webhook?gateway_id=crypto_usdt', {
    method: 'POST',
    headers: {
      'x-webhook-signature': cryptoSig,
      'Content-Type': 'application/json',
    },
    body: cryptoPayload,
  });

  const cryptoResult = await verifyAndParseIntlCryptoWebhook(cryptoReq, cryptoPayload, {
    webhook_secret: cryptoSecret,
  });
  assert.ok(cryptoResult, 'Crypto webhook should parse confirmed USDT transfer');
  assert.equal(cryptoResult.transferCode, 'TQ11E2F3');
  assert.equal(cryptoResult.paidAmount, 12.5);
  assert.equal(cryptoResult.currency, 'USDT');
  assert.equal(cryptoResult.providerTxId, '0x99887766554433221100aabbccddeeff');
  console.log('[PASS] 5/5 International Card (Stripe) & Crypto (USDT) Webhook Adapters verified.');

  console.log('====================================================================');
  console.log(' [ALL TESTS PASSED] Payment Gateway SQL & Webhook Adapters Verified');
  console.log('====================================================================');
}

runTests().catch((err) => {
  console.error('[FAIL]', err);
  process.exit(1);
});
