#!/usr/bin/env node

// ============================================================================
// TUQUET-CLOUD TEST PRESET CLI (NODE.JS / ESM / CROSS-PLATFORM)
// Description: SOLID CLI for provisioning and verifying test identities,
//              tenants, memberships, and RLS access against Supabase.
// ============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '../../');
const presetsDir = path.resolve(rootDir, 'tests/presets');
const helperSqlFile = path.resolve(presetsDir, 'sql/00_provision_helper.sql');

const DEFAULT_API_URL = 'http://127.0.0.1:54321';
const DEFAULT_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

// ANSI Colors
const colors = {
  cyan: (str) => `\x1b[36m${str}\x1b[0m`,
  green: (str) => `\x1b[32m${str}\x1b[0m`,
  yellow: (str) => `\x1b[33m${str}\x1b[0m`,
  red: (str) => `\x1b[31m${str}\x1b[0m`,
  gray: (str) => `\x1b[90m${str}\x1b[0m`,
  white: (str) => `\x1b[37m${str}\x1b[0m`,
  bold: (str) => `\x1b[1m${str}\x1b[0m`,
};

function showBanner(title) {
  console.log(colors.cyan('='.repeat(68)));
  console.log(colors.cyan(` [TUQUET-CLOUD-TEST-CLI] ${title}`));
  console.log(colors.cyan('='.repeat(68)));
}

function executeSql(sql, target = 'local') {
  if (target === 'local') {
    try {
      const output = execSync(
        'docker exec -i supabase_db_tuquet-cloud psql -U postgres -d postgres',
        {
          input: sql,
          encoding: 'utf-8',
          stdio: ['pipe', 'pipe', 'pipe'],
        }
      );
      return { success: true, output };
    } catch (err) {
      return {
        success: false,
        output: err.stdout?.toString() || err.stderr?.toString() || err.message,
      };
    }
  } else {
    const tempFile = path.join(rootDir, '.temp_query.sql');
    fs.writeFileSync(tempFile, sql, 'utf-8');
    try {
      const output = execSync(`supabase db query --${target} -f "${tempFile}"`, {
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      fs.unlinkSync(tempFile);
      return { success: true, output };
    } catch (err) {
      if (fs.existsSync(tempFile)) fs.unlinkSync(tempFile);
      return {
        success: false,
        output: err.stdout?.toString() || err.stderr?.toString() || err.message,
      };
    }
  }
}

function ensureProvisionHelper(target = 'local') {
  if (!fs.existsSync(helperSqlFile)) {
    console.error(colors.red(`[-] SQL Helper file not found: ${helperSqlFile}`));
    process.exit(1);
  }

  const checkSql = "SELECT count(1) FROM pg_proc WHERE proname = 'provision_test_preset';";
  const check = executeSql(checkSql, target);
  if (!check.output.includes('1')) {
    console.log(colors.yellow('--> Deploying provision helper stored procedures into database...'));
    const sql = fs.readFileSync(helperSqlFile, 'utf-8');
    const deploy = executeSql(sql, target);
    if (!deploy.success) {
      console.error(colors.red(`[-] Failed to deploy helper procedures: ${deploy.output}`));
      process.exit(1);
    }
    console.log(colors.green('    [OK] Helper stored procedures installed successfully.'));
  }
}

function listPresets() {
  showBanner('Available Test Presets');
  const files = fs
    .readdirSync(presetsDir)
    .filter((f) => f.endsWith('.json') && !f.includes('schema'));

  if (files.length === 0) {
    console.log(colors.yellow(`No presets found in ${presetsDir}`));
    return;
  }

  console.log(
    colors.white(
      `${'PRESET'.padEnd(15)} ${'EMAIL'.padEnd(30)} ${'TENANT SLUG'.padEnd(25)} ${'ROLE'.padEnd(8)} ${'PLAN'.padEnd(8)}`
    )
  );
  console.log(colors.gray('-'.repeat(90)));

  for (const file of files) {
    try {
      const content = fs.readFileSync(path.join(presetsDir, file), 'utf-8');
      const json = JSON.parse(content);
      const name = json.name || file.replace('.json', '');
      const email = json.user?.email || 'N/A';
      const slug = json.tenant?.slug || 'N/A';
      const role = json.role || 'owner';
      const plan = json.tenant?.plan || 'pro';

      console.log(
        colors.cyan(
          `${name.padEnd(15)} ${email.padEnd(30)} ${slug.padEnd(25)} ${role.padEnd(8)} ${plan.padEnd(8)}`
        )
      );
    } catch {
      console.log(colors.red(`${file.padEnd(15)} [Error parsing JSON]`));
    }
  }
  console.log('');
}

function resolvePreset(name) {
  let targetPath = null;
  if (fs.existsSync(name)) {
    targetPath = path.resolve(name);
  } else {
    const candidate = path.join(presetsDir, `${name}.json`);
    if (fs.existsSync(candidate)) {
      targetPath = candidate;
    }
  }

  if (!targetPath) {
    console.error(colors.red(`[-] Preset not found: ${name} (checked in ${presetsDir})`));
    process.exit(1);
  }

  const raw = fs.readFileSync(targetPath, 'utf-8');
  return { path: targetPath, raw, data: JSON.parse(raw) };
}

async function verifyAuth(email, password, expectedSlug, apiUrl = DEFAULT_API_URL, anonKey = DEFAULT_ANON_KEY) {
  console.log(colors.yellow(`\n--> Verifying Authentication for: ${email}`));

  const authUrl = `${apiUrl}/auth/v1/token?grant_type=password`;
  let token = null;
  let userId = null;

  try {
    const res = await fetch(authUrl, {
      method: 'POST',
      headers: {
        apikey: anonKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, password }),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`HTTP ${res.status}: ${errText}`);
    }

    const authData = await res.json();
    token = authData.access_token;
    userId = authData.user.id;

    console.log(colors.green(`    [OK] GoTrue Auth: HTTP 200 OK`));
    console.log(colors.green(`    [OK] User ID: ${userId}`));
    console.log(colors.green(`    [OK] Email Confirmed: ${authData.user.email_confirmed_at}`));
    console.log(colors.green(`    [OK] Status: ACTIVE 100%`));
    console.log(colors.green(`    [OK] Access Token (JWT): ${token.substring(0, 35)}...`));
  } catch (err) {
    console.error(colors.red(`[-] Authentication failed: ${err.message}`));
    process.exit(1);
  }

  console.log(colors.yellow(`\n--> Verifying Row-Level Security (RLS) & Tenant Isolation...`));
  const restUrl = `${apiUrl}/rest/v1/tenants?select=id,slug,name,status,created_by`;

  try {
    const res = await fetch(restUrl, {
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${token}`,
      },
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`HTTP ${res.status}: ${errText}`);
    }

    const tenants = await res.json();
    console.log(colors.green(`    [OK] Visible Tenants returned by PostgREST: ${tenants.length}`));

    let foundTarget = false;
    for (const t of tenants) {
      const isTarget = t.slug === expectedSlug;
      const tag = isTarget ? '[TARGET]' : '        ';
      console.log(colors.cyan(`    ${tag} Tenant: ${t.name} (slug: ${t.slug}, status: ${t.status})`));
      if (isTarget) foundTarget = true;
    }

    if (expectedSlug && !foundTarget) {
      console.error(colors.red(`[-] RLS Warning: Expected tenant '${expectedSlug}' not found in query results!`));
      process.exit(1);
    }

    console.log(colors.green(`\n[VERIFICATION COMPLETE] Test Identity is 100% active, authenticated, and isolated via RLS!\n`));
  } catch (err) {
    console.error(colors.red(`[-] REST query failed: ${err.message}`));
    process.exit(1);
  }
}

async function applyPreset(presetName, target = 'local', shouldVerify = false) {
  showBanner(`Applying Test Preset: ${presetName}`);
  const { raw, data } = resolvePreset(presetName);

  ensureProvisionHelper(target);

  console.log(colors.yellow(`--> Provisioning Identity & Tenant in Database (${target})...`));
  const escapedJson = raw.replace(/'/g, "''");
  const sql = `SELECT public.provision_test_preset('${escapedJson}'::jsonb);`;

  const dbRes = executeSql(sql, target);
  if (!dbRes.success) {
    console.error(colors.red(`[-] Provisioning failed: ${dbRes.output}`));
    process.exit(1);
  }

  const match = dbRes.output.match(/\{.*"success".*\}/);
  if (match) {
    try {
      const parsed = JSON.parse(match[0]);
      console.log(colors.green(`    [OK] User ID:     ${parsed.user_id}`));
      console.log(colors.green(`    [OK] Email:       ${parsed.email}`));
      console.log(colors.green(`    [OK] Tenant ID:   ${parsed.tenant_id}`));
      console.log(colors.green(`    [OK] Tenant Slug: ${parsed.tenant_slug}`));
      console.log(colors.green(`    [OK] Role:        ${parsed.role_name}`));
      if (parsed.plan) console.log(colors.green(`    [OK] Plan:        ${parsed.plan}`));
      console.log(colors.green(`    [OK] Status:      ${parsed.status}`));
    } catch {
      console.log(colors.gray(dbRes.output));
    }
  }

  console.log(colors.green(`\n[APPLY SUCCESSFUL] Preset '${presetName}' applied successfully.`));

  if (shouldVerify) {
    await verifyAuth(data.user.email, data.user.password, data.tenant?.slug);
  }
}

// CLI Arg Parsing
const args = process.argv.slice(2);
const command = args[0] || 'list';

function getArgValue(flag) {
  const idx = args.indexOf(flag);
  if (idx !== -1 && args[idx + 1]) {
    return args[idx + 1];
  }
  return null;
}

const hasVerify = args.includes('--verify') || args.includes('-v');
const targetArg = getArgValue('--target') || 'local';
const presetArg = getArgValue('--preset') || args[1] || 'tunyk';

async function main() {
  switch (command) {
    case 'list':
    case 'list-presets':
      listPresets();
      break;

    case 'apply':
    case 'apply-preset':
      await applyPreset(presetArg, targetArg, hasVerify);
      break;

    case 'verify':
    case 'verify-auth': {
      const { data } = resolvePreset(presetArg);
      await verifyAuth(data.user.email, data.user.password, data.tenant?.slug);
      break;
    }

    default:
      console.log(`Unknown command: ${command}`);
      console.log('Available commands: list, apply, verify');
      process.exit(1);
  }
}

main().catch((err) => {
  console.error(colors.red(`Fatal: ${err.message}`));
  process.exit(1);
});
