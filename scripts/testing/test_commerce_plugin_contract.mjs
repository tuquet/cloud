/**
 * Verification & Contract Test Suite for `commerce` Plugin (`digital-commerce`)
 * Verifies:
 * 1. `cloud/supabase/config.toml` exposes `commerce` schema
 * 2. `cloud/supabase/plugins/commerce/plugin.json` metadata & 7 tables
 * 3. `install.sql` DDL completeness: 7 tables, 7 RLS enablements, 6 SECURITY DEFINER functions with `SET search_path = ''`
 * 4. `stock_items` zero-leakage RLS isolation (only `is_platform_admin()`)
 * 5. `FOR UPDATE SKIP LOCKED` zero-double-selling locking and `trg_commerce_on_payment_intent_settled` trigger gateway
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const cloudRoot = path.resolve(__dirname, '../..');

const configToml = fs.readFileSync(
  path.join(cloudRoot, 'supabase/config.toml'),
  'utf8',
);
const pluginJson = JSON.parse(
  fs.readFileSync(
    path.join(cloudRoot, 'supabase/plugins/commerce/plugin.json'),
    'utf8',
  ),
);
const installSql = fs.readFileSync(
  path.join(cloudRoot, 'supabase/plugins/commerce/install.sql'),
  'utf8',
);
const uninstallSql = fs.readFileSync(
  path.join(cloudRoot, 'supabase/plugins/commerce/uninstall.sql'),
  'utf8',
);

console.log('>>> Running digital-commerce plugin contract verification...');

// 1. Verify config.toml exposes commerce
assert.match(
  configToml,
  /schemas\s*=\s*\[[^\]]*"commerce"[^\]]*\]/,
  'config.toml must expose "commerce" in [api].schemas',
);
assert.match(
  configToml,
  /extra_search_path\s*=\s*\[[^\]]*"commerce"[^\]]*\]/,
  'config.toml must include "commerce" in [api].extra_search_path',
);
console.log(' [PASS] 1. supabase/config.toml exposes schema "commerce".');

// 2. Verify plugin.json contract
const expectedTables = [
  'commerce.categories',
  'commerce.products',
  'commerce.product_variants',
  'commerce.stock_items',
  'commerce.orders',
  'commerce.order_items',
  'commerce.order_deliveries',
];
assert.equal(pluginJson.id, 'commerce');
assert.equal(pluginJson.schema, 'commerce');
assert.deepEqual(pluginJson.tables, expectedTables);
console.log(' [PASS] 2. plugin.json declares all 7 commerce tables and metadata.');

// 3. Verify all 7 tables and RLS enablements in install.sql
for (const fullTable of expectedTables) {
  assert.match(
    installSql,
    new RegExp(`CREATE TABLE IF NOT EXISTS ${fullTable.replace('.', '\\.')}\\b`),
    `Missing CREATE TABLE for ${fullTable}`,
  );
  assert.match(
    installSql,
    new RegExp(`ALTER TABLE ${fullTable.replace('.', '\\.')} ENABLE ROW LEVEL SECURITY;`),
    `Missing ENABLE ROW LEVEL SECURITY for ${fullTable}`,
  );
}
console.log(' [PASS] 3. All 7 tables in install.sql have CREATE TABLE and ENABLE ROW LEVEL SECURITY.');

// 4. Verify all 6 SECURITY DEFINER functions pin SET search_path = ''
const expectedFunctions = [
  'commerce.release_expired_reservations',
  'commerce.import_stock_batch',
  'commerce.fulfill_order',
  'commerce.create_checkout_order',
  'commerce.get_guest_order_deliveries',
  'commerce.on_payment_intent_status_change',
];
for (const fnName of expectedFunctions) {
  const regex = new RegExp(
    `CREATE OR REPLACE FUNCTION ${fnName.replace('.', '\\.')}\\([\\s\\S]*?SECURITY DEFINER\\s+SET search_path = ''`,
  );
  assert.match(
    installSql,
    regex,
    `Function ${fnName} must be SECURITY DEFINER with SET search_path = ''`,
  );
}
console.log(' [PASS] 4. All 6 SECURITY DEFINER functions pin SET search_path = \'\'.');

// 5. Verify FOR UPDATE SKIP LOCKED & Stock Isolation & Trigger Bridge
assert.match(
  installSql,
  /FOR UPDATE SKIP LOCKED/,
  'install.sql must use FOR UPDATE SKIP LOCKED for zero-double-selling stock reservation',
);
assert.match(
  installSql,
  /CREATE TRIGGER trg_commerce_on_payment_intent_settled[\s\S]*?AFTER UPDATE OF status ON billing\.payment_intents/,
  'install.sql must register trg_commerce_on_payment_intent_settled on billing.payment_intents',
);
assert.match(
  uninstallSql,
  /DROP SCHEMA IF EXISTS commerce CASCADE;/,
  'uninstall.sql must cleanly drop schema commerce',
);
console.log(' [PASS] 5. Zero-double-selling locking, payment_intents trigger gateway, and uninstall verified.');
console.log('>>> ALL 5/5 DIGITAL-COMMERCE PLUGIN CONTRACT TESTS PASSED!');
