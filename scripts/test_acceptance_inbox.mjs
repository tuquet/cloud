// ============================================================================
// TUQUET E2E ACCEPTANCE TEST: INBOX CATCH-ALL & OTP SUBSYSTEM (SUPABASE CLOUD)
// Target: Supabase Cloud Dev / Staging (REST & RPC closed loop)
// ============================================================================

import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://dswhacsoaxgpfnkaxnhz.supabase.co";
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

console.log("================================================================================");
console.log(" [ACCEPTANCE TEST] Supabase Cloud Inbox Catch-All & OTP Interceptor Subsystem");
console.log(` Target Endpoint: ${SUPABASE_URL}`);
console.log("================================================================================");

if (!SERVICE_KEY) {
    console.warn("\n⚠️  [WARN] SUPABASE_SERVICE_ROLE_KEY not set in environment.");
    console.warn("   To run full RPC acceptance test against live cloud dev, pass:");
    console.warn("   $env:SUPABASE_SERVICE_ROLE_KEY = '<your_service_role_key>'");
    console.warn("   node scripts/test_acceptance_inbox.mjs\n");
}

async function runAcceptance() {
    // 1. Identify Local Workstation Identity (SSOT)
    let deviceId = null;
    const tuquetHome = process.env.TUQUET_HOME || process.env.SPECTER_HOME || (existsSync(join(homedir(), ".tuquet")) ? join(homedir(), ".tuquet") : join(homedir(), ".specter"));
    const identityPath = join(tuquetHome, "system", ".identity.json");
    if (existsSync(identityPath)) {
        try {
            const identity = JSON.parse(readFileSync(identityPath, "utf-8"));
            deviceId = identity.device_id;
            console.log(`[1/6] Workstation Identity Detected:`);
            console.log(`      Device ID:   ${deviceId}`);
            console.log(`      Device Name: ${identity.name || 'Workstation'}`);
        } catch (_) {}
    } else {
        console.log(`[1/6] Standalone test execution (No local .identity.json needed).`);
    }

    if (!SERVICE_KEY) {
        console.log("\n[SKIP] Live HTTP requests skipped because SUPABASE_SERVICE_ROLE_KEY is absent.");
        console.log("       SQL test suite has been prepared at: tests/db/07_verify_inbox_subsystem.sql");
        return;
    }

    const TEST_TENANT_ID = process.env.SUPABASE_TENANT_ID || "b0000000-0000-0000-0000-000000000001";
    const TEST_RECIPIENT = `e2e_test_${Date.now()}@catchall-test.io`;
    const TEST_OTP = `${Math.floor(100000 + Math.random() * 900000)}`;

    console.log(`\n[2/6] Ingesting simulated Catch-All email via RPC (inbox.ingest_email)...`);
    console.log(`      Recipient: ${TEST_RECIPIENT}`);
    console.log(`      Test OTP:  ${TEST_OTP}`);

    const ingestPayload = {
        p_tenant_id: TEST_TENANT_ID,
        p_recipient: TEST_RECIPIENT,
        p_sender: "security@google.com",
        p_subject: `Your Google verification code is ${TEST_OTP}`,
        p_body_text: `G-${TEST_OTP} is your Google verification code. Never share it with anyone.`,
        p_body_html: `<p>G-<b>${TEST_OTP}</b> is your verification code.</p>`,
        p_otp_code: TEST_OTP,
        p_sender_service: "Google",
        p_link_url: `https://accounts.google.com/verify?code=${TEST_OTP}`,
        p_link_type: "activation"
    };

    const ingestRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/ingest_email`, {
        method: "POST",
        headers: {
            "apikey": SERVICE_KEY,
            "Authorization": `Bearer ${SERVICE_KEY}`,
            "Content-Type": "application/json",
            "Prefer": "return=representation"
        },
        body: JSON.stringify(ingestPayload)
    });

    if (!ingestRes.ok) {
        const err = await ingestRes.text();
        throw new Error(`ingest_email failed HTTP ${ingestRes.status}: ${err}`);
    }

    const ingestData = await ingestRes.json();
    console.log(`      ✓ Ingest Success:`, ingestData);

    // 3. Verify OTP row created in inbox.otps
    console.log(`\n[3/6] Verifying OTP row in inbox.otps...`);
    const otpRes = await fetch(`${SUPABASE_URL}/rest/v1/inbox_otps?recipient=eq.${encodeURIComponent(TEST_RECIPIENT)}&limit=1`, {
        headers: {
            "apikey": SERVICE_KEY,
            "Authorization": `Bearer ${SERVICE_KEY}`
        }
    });

    if (!otpRes.ok) {
        console.warn(`      (Could not directly query inbox_otps via REST view, falling back to consume RPC)`);
    } else {
        const rows = await otpRes.json();
        if (rows.length > 0) {
            console.log(`      ✓ OTP row found: Code = ${rows[0].otp_code || rows[0].code}, Consumed = ${rows[0].is_consumed}`);
        }
    }

    // 4. Consume OTP atomically via RPC (inbox.consume_otp)
    console.log(`\n[4/6] Executing Atomic OTP Consumption (inbox.consume_otp)...`);
    const consumeRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/consume_otp`, {
        method: "POST",
        headers: {
            "apikey": SERVICE_KEY,
            "Authorization": `Bearer ${SERVICE_KEY}`,
            "Content-Type": "application/json"
        },
        body: JSON.stringify({
            p_tenant_id: TEST_TENANT_ID,
            p_recipient: TEST_RECIPIENT,
            p_device_id: deviceId
        })
    });

    if (!consumeRes.ok) {
        const err = await consumeRes.text();
        throw new Error(`consume_otp failed HTTP ${consumeRes.status}: ${err}`);
    }

    const consumeData = await consumeRes.json();
    if (!consumeData.found || consumeData.code !== TEST_OTP) {
        throw new Error(`consume_otp assertion failed: expected ${TEST_OTP}, got: ${JSON.stringify(consumeData)}`);
    }
    console.log(`      ✓ OTP consumed successfully: Code = ${consumeData.code}, Service = ${consumeData.sender_service}`);

    // 5. Test Idempotency (Second consume should return found: false)
    console.log(`\n[5/6] Testing Anti-Duplicate Lock (Second consume should be rejected)...`);
    const secondConsume = await fetch(`${SUPABASE_URL}/rest/v1/rpc/consume_otp`, {
        method: "POST",
        headers: {
            "apikey": SERVICE_KEY,
            "Authorization": `Bearer ${SERVICE_KEY}`,
            "Content-Type": "application/json"
        },
        body: JSON.stringify({
            p_tenant_id: TEST_TENANT_ID,
            p_recipient: TEST_RECIPIENT,
            p_device_id: deviceId
        })
    });

    const secondData = await secondConsume.json();
    if (secondData.found === true) {
        throw new Error(`Idempotency violated: second consume returned found = true!`);
    }
    console.log(`      ✓ Anti-Duplicate Lock confirmed: second consume returned found = false.`);

    // 6. Cleanup test records
    console.log(`\n[6/6] Cleaning up test records for ${TEST_RECIPIENT}...`);
    await fetch(`${SUPABASE_URL}/rest/v1/inbox_emails?recipient=eq.${encodeURIComponent(TEST_RECIPIENT)}`, {
        method: "DELETE",
        headers: {
            "apikey": SERVICE_KEY,
            "Authorization": `Bearer ${SERVICE_KEY}`
        }
    });

    console.log("================================================================================");
    console.log(" ✅ ALL ACCEPTANCE CHECKS PASSED: Supabase Cloud Inbox Subsystem is Healthy!");
    console.log("================================================================================");
}

runAcceptance().catch((err) => {
    console.error("\n❌ [ACCEPTANCE TEST FAILED]", err.message);
    process.exit(1);
});
