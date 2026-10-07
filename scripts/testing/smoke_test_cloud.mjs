// ============================================================================
// TUQUET-CLOUD SMOKE TEST (CI & POST-DEPLOYMENT VERIFICATION)
// Description: Validates core Supabase Cloud endpoints, PostgREST queries,
//              and essential tenant connectivity after automated deployment.
// ============================================================================

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.log('[SKIP] SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not configured in environment.');
  process.exit(0);
}

async function runSmokeTest() {
  console.log("====================================================================");
  console.log(` [SMOKE TEST] Supabase Cloud Gateway Verification`);
  console.log(` Target Endpoint: ${SUPABASE_URL}`);
  console.log("====================================================================");

  let allPassed = true;

  // 1. Check REST API /tenants
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/tenants?select=id,name,slug&limit=5`, {
      method: "GET",
      headers: {
        "apikey": SERVICE_KEY,
        "Authorization": `Bearer ${SERVICE_KEY}`,
        "Content-Type": "application/json"
      }
    });

    if (res.ok) {
      const data = await res.json();
      console.log(`[PASS] Core IAM: /rest/v1/tenants query succeeded (${data.length} records found).`);
    } else {
      console.error(`[FAIL] Core IAM: /rest/v1/tenants returned HTTP ${res.status}: ${await res.text()}`);
      allPassed = false;
    }
  } catch (err) {
    console.error(`[FAIL] Core IAM query network error: ${err.message}`);
    allPassed = false;
  }

  // 2. Check Auth Service Health
  try {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/health`, {
      method: "GET",
      headers: { "apikey": SERVICE_KEY }
    });

    if (res.ok) {
      console.log(`[PASS] Auth Service: /auth/v1/health is operational.`);
    } else {
      console.warn(`[WARN] Auth Service /health returned HTTP ${res.status}`);
    }
  } catch (err) {
    console.warn(`[WARN] Auth Service health check skipped: ${err.message}`);
  }

  console.log("====================================================================");
  if (allPassed) {
    console.log(" [SUCCESS] All critical cloud services are verified operational!");
    console.log("====================================================================");
  } else {
    console.error(" [FAILURE] One or more critical smoke tests failed.");
    console.log("====================================================================");
    process.exit(1);
  }
}

runSmokeTest();
