-- ============================================================================
-- TEST SUITE: 08_VERIFY_COMMERCE_PLUGIN.SQL
-- Description: Verification for Digital Products Store, Serialized Stock Locking,
--              Instant Xu Wallet Checkout, Auto-Fulfillment & Guest Claim Token
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_tbl TEXT;
    v_expected_tables TEXT[] := ARRAY[
        'categories',
        'products',
        'product_variants',
        'stock_items',
        'orders',
        'order_items',
        'order_deliveries'
    ];
    v_missing_tables TEXT[] := ARRAY[]::TEXT[];
    v_test_tenant_id UUID;
    v_serial_variant_id UUID;
    v_proxy_variant_id UUID;
    v_file_variant_id UUID;
    v_topup_variant_id UUID;
    v_import_res JSONB;
    v_wallet_order_res JSONB;
    v_wallet_order_id UUID;
    v_proxy_order_res JSONB;
    v_guest_order_res JSONB;
    v_guest_order_code TEXT;
    v_guest_claim_token TEXT;
    v_guest_intent_id UUID;
    v_guest_lookup_res JSONB;
    v_topup_order_res JSONB;
    v_topup_intent_id UUID;
    v_balance_after BIGINT;
    v_err_caught BOOLEAN := FALSE;
BEGIN
    RAISE NOTICE '>>> [TEST 1] Verifying schema commerce and all 7 tables...';
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'commerce') THEN
        RAISE EXCEPTION 'FAILED: Schema commerce does not exist!';
    END IF;

    FOREACH v_tbl IN ARRAY v_expected_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'commerce' AND table_name = v_tbl
        ) THEN
            v_missing_tables := array_append(v_missing_tables, v_tbl);
        END IF;
    END LOOP;

    IF array_length(v_missing_tables, 1) > 0 THEN
        RAISE EXCEPTION 'FAILED: Missing tables in schema commerce: %', v_missing_tables;
    ELSE
        RAISE NOTICE ' [PASS] All 7 Digital Commerce tables exist in schema commerce.';
    END IF;

    RAISE NOTICE '>>> [TEST 2] Verifying RLS on all 7 commerce tables...';
    FOREACH v_tbl IN ARRAY v_expected_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_tables
            WHERE schemaname = 'commerce' AND tablename = v_tbl AND rowsecurity = true
        ) THEN
            RAISE EXCEPTION 'FAILED: RLS is disabled on commerce.%!', v_tbl;
        END IF;
    END LOOP;
    RAISE NOTICE ' [PASS] RLS is active on 100%% of schema commerce tables.';

    RAISE NOTICE '>>> [TEST 3] Verifying Plugin Registry & RBAC Permissions...';
    IF NOT EXISTS (SELECT 1 FROM public.system_plugins WHERE id = 'commerce' AND status = 'installed') THEN
        RAISE EXCEPTION 'FAILED: Plugin commerce is not registered as installed!';
    END IF;
    IF (SELECT count(*) FROM public.permissions WHERE module = 'commerce') < 3 THEN
        RAISE EXCEPTION 'FAILED: Fewer than 3 commerce permissions registered in public.permissions!';
    END IF;
    RAISE NOTICE ' [PASS] Plugin commerce and permissions (commerce:read, commerce:purchase, commerce:manage) verified.';

    -- Locate or create test tenant
    SELECT id INTO v_test_tenant_id FROM public.tenants LIMIT 1;
    IF v_test_tenant_id IS NULL THEN
        INSERT INTO public.tenants (name, slug)
        VALUES ('Commerce Verify Tenant', 'commerce-verify-tenant')
        RETURNING id INTO v_test_tenant_id;
    END IF;

    SELECT id INTO v_serial_variant_id FROM commerce.product_variants WHERE sku = 'VIA-2FA-STD';
    SELECT id INTO v_proxy_variant_id FROM commerce.product_variants WHERE sku = 'PROXY-VN-ISP-30D';
    SELECT id INTO v_file_variant_id FROM commerce.product_variants WHERE sku = 'FP-PACK-500-ZIP';
    SELECT id INTO v_topup_variant_id FROM commerce.product_variants WHERE sku = 'XU-PACK-500-BONUS50';

    RAISE NOTICE '>>> [TEST 4] Verifying Bulk Stock Import & Deduplication (commerce.import_stock_batch)...';
    v_import_res := commerce.import_stock_batch(
        v_serial_variant_id,
        ARRAY[
            '100088001|passA|JBSWY3DPEHPK3PXP|mail1@example.com',
            '100088002|passB|JBSWY3DPEHPK3PXQ|mail2@example.com',
            '100088001|passA|JBSWY3DPEHPK3PXP|mail1@example.com' -- duplicate line
        ],
        'BATCH-VERIFY-01'
    );

    IF (v_import_res->>'imported_count')::int <> 2 OR (v_import_res->>'skipped_duplicates')::int <> 1 THEN
        RAISE EXCEPTION 'FAILED: Stock batch deduplication mismatch: %', v_import_res;
    END IF;
    RAISE NOTICE ' [PASS] Bulk stock import deduplicated accurately (2 imported, 1 duplicate skipped).';

    RAISE NOTICE '>>> [TEST 5] Verifying Tenant Instant Xu Wallet Checkout & Serial Stock Auto-Fulfillment...';
    PERFORM billing.credit_tenant_wallet(v_test_tenant_id, 500, 'topup', 'test_seed', 'seed-500', 'Seed 500 Xu');

    v_wallet_order_res := commerce.create_checkout_order(
        jsonb_build_array(jsonb_build_object('variant_id', v_serial_variant_id, 'quantity', 1)),
        'internal_wallet',
        v_test_tenant_id,
        'internal_wallet',
        'buyer@tuquet.com',
        'idem-wallet-order-1'
    );

    v_wallet_order_id := (v_wallet_order_res->'order'->>'id')::uuid;
    IF (v_wallet_order_res->'order'->>'status') <> 'completed' THEN
        RAISE EXCEPTION 'FAILED: Instant internal_wallet order did not reach completed status: %', v_wallet_order_res;
    END IF;
    IF jsonb_array_length(v_wallet_order_res->'fulfillment'->'deliveries') <> 1 THEN
        RAISE EXCEPTION 'FAILED: Expected 1 serial delivery, got: %', v_wallet_order_res;
    END IF;
    RAISE NOTICE ' [PASS] Instant Xu wallet checkout deducted 50 Xu and delivered serial_stock atomically.';

    RAISE NOTICE '>>> [TEST 6] Verifying Ecosystem Resource Provisioning (workers.proxies)...';
    PERFORM commerce.import_stock_batch(
        v_proxy_variant_id,
        ARRAY['198.51.100.25:10800:pxuser1:pxpass1'],
        'BATCH-PROXY-01'
    );

    v_proxy_order_res := commerce.create_checkout_order(
        jsonb_build_array(jsonb_build_object('variant_id', v_proxy_variant_id, 'quantity', 1)),
        'internal_wallet',
        v_test_tenant_id,
        'internal_wallet',
        'buyer@tuquet.com',
        'idem-proxy-order-1'
    );

    IF NOT EXISTS (
        SELECT 1 FROM workers.proxies
        WHERE tenant_id = v_test_tenant_id AND host = '198.51.100.25' AND port = 10800
    ) THEN
        RAISE EXCEPTION 'FAILED: Proxy resource was not provisioned into workers.proxies!';
    END IF;
    RAISE NOTICE ' [PASS] proxy_pool resource automatically provisioned into workers.proxies.';

    RAISE NOTICE '>>> [TEST 7] Verifying Guest Checkout, Webhook Settlement Trigger & Claim Token Lookup...';
    v_guest_order_res := commerce.create_checkout_order(
        jsonb_build_array(
            jsonb_build_object('variant_id', v_serial_variant_id, 'quantity', 1),
            jsonb_build_object('variant_id', v_file_variant_id, 'quantity', 1)
        ),
        'bank_transfer',
        NULL,
        'bank_vietqr',
        'guest@example.com',
        'idem-guest-order-1'
    );

    v_guest_order_code := v_guest_order_res->'order'->>'order_code';
    v_guest_claim_token := v_guest_order_res->>'claim_token';
    v_guest_intent_id := (v_guest_order_res->'payment_intent'->>'id')::uuid;

    IF v_guest_claim_token IS NULL OR (v_guest_order_res->'order'->>'status') <> 'pending_payment' THEN
        RAISE EXCEPTION 'FAILED: Guest order should start in pending_payment with a claim_token: %', v_guest_order_res;
    END IF;

    -- Settle the linked payment intent (simulating bank webhook arrival)
    PERFORM billing.settle_payment_intent(
        v_guest_intent_id,
        NULL,
        'BANK-TX-GUEST-01',
        250000,
        '{"gateway": "sepay"}'::jsonb,
        FALSE
    );

    -- Verify trigger automatically fulfilled the guest order
    v_guest_lookup_res := commerce.get_guest_order_deliveries(v_guest_order_code, v_guest_claim_token);
    IF (v_guest_lookup_res->'order'->>'status') <> 'completed'
       OR jsonb_array_length(v_guest_lookup_res->'deliveries') <> 2 THEN
        RAISE EXCEPTION 'FAILED: Guest order was not auto-fulfilled by payment_intent trigger: %', v_guest_lookup_res;
    END IF;

    -- Verify invalid claim token is rejected
    BEGIN
        PERFORM commerce.get_guest_order_deliveries(v_guest_order_code, 'CLM_INVALID_TOKEN');
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'FAILED: get_guest_order_deliveries accepted an invalid claim_token!';
    END IF;
    RAISE NOTICE ' [PASS] Guest checkout, payment_intent settlement trigger, and claim_token security verified.';

    RAISE NOTICE '>>> [TEST 8] Verifying Wallet Credit Bundle Order & Bonus Xu Fulfillment...';
    v_topup_order_res := commerce.create_checkout_order(
        jsonb_build_array(jsonb_build_object('variant_id', v_topup_variant_id, 'quantity', 1)),
        'e_wallet',
        v_test_tenant_id,
        'momo_ewallet',
        'buyer@tuquet.com',
        'idem-topup-order-1'
    );
    v_topup_intent_id := (v_topup_order_res->'payment_intent'->>'id')::uuid;

    PERFORM billing.settle_payment_intent(
        v_topup_intent_id,
        NULL,
        'MOMO-TX-TOPUP-01',
        500000,
        '{"gateway": "momo"}'::jsonb,
        FALSE
    );

    SELECT balance_credits INTO v_balance_after
    FROM billing.wallets
    WHERE tenant_id = v_test_tenant_id;

    -- Started with 500 Xu -> spent 50 (serial) -> spent 120 (proxy) = 330 Xu -> +550 Xu (500 + 50 bonus) = 880 Xu
    IF v_balance_after <> 880 THEN
        RAISE EXCEPTION 'FAILED: Expected tenant wallet balance 880 Xu after bundle fulfillment, got %', v_balance_after;
    END IF;
    RAISE NOTICE ' [PASS] Prepaid Xu bundle (500 + 50 bonus Xu) credited accurately (balance = 880 Xu).';
END $$;

ROLLBACK;
