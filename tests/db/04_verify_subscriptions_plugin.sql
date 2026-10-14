-- ============================================================================
-- TEST SUITE: 04_VERIFY_SUBSCRIPTIONS_PLUGIN.SQL
-- Description: Verification for Subscriptions, Xu Wallet Ledger, and Payment Gateway
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_tbl TEXT;
    v_expected_tables TEXT[] := ARRAY[
        'plans',
        'subscriptions',
        'usage_meters',
        'wallets',
        'wallet_transactions',
        'payment_gateways',
        'payment_gateway_secrets',
        'payment_intents'
    ];
    v_missing_tables TEXT[] := ARRAY[]::TEXT[];
    v_test_tenant_id UUID;
    v_balance BIGINT;
    v_ledger_sum BIGINT;
    v_err_caught BOOLEAN := FALSE;
    v_gateway_count INT;
    v_bank_intent JSONB;
    v_bank_intent_id UUID;
    v_bank_transfer_code TEXT;
    v_wallet_intent JSONB;
    v_late_intent JSONB;
    v_late_intent_id UUID;
    v_late_transfer_code TEXT;
    v_settle_res JSONB;
    v_settle_idem JSONB;
    v_settle_late JSONB;
    v_settle_force JSONB;
BEGIN
    RAISE NOTICE '>>> [TEST 1] Verifying schema billing and all 8 tables...';
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'billing') THEN
        RAISE EXCEPTION 'FAILED: Schema billing does not exist!';
    END IF;

    FOREACH v_tbl IN ARRAY v_expected_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'billing' AND table_name = v_tbl
        ) THEN
            v_missing_tables := array_append(v_missing_tables, v_tbl);
        END IF;
    END LOOP;

    IF array_length(v_missing_tables, 1) > 0 THEN
        RAISE EXCEPTION 'FAILED: Missing tables in schema billing: %', v_missing_tables;
    ELSE
        RAISE NOTICE ' [PASS] All 8 Billing, Wallet & Payment Gateway tables exist in schema billing.';
    END IF;

    RAISE NOTICE '>>> [TEST 2] Verifying RLS on all 8 billing tables...';
    FOREACH v_tbl IN ARRAY v_expected_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_tables 
            WHERE schemaname = 'billing' AND tablename = v_tbl AND rowsecurity = true
        ) THEN
            RAISE EXCEPTION 'FAILED: RLS is disabled on billing.%!', v_tbl;
        END IF;
    END LOOP;
    RAISE NOTICE ' [PASS] RLS is active on 100%% of schema billing tables.';

    RAISE NOTICE '>>> [TEST 3] Verifying Plugin Registry entry...';
    IF NOT EXISTS (SELECT 1 FROM public.system_plugins WHERE id = 'subscriptions' AND status = 'installed') THEN
        RAISE EXCEPTION 'FAILED: Plugin subscriptions is not registered as installed!';
    ELSE
        RAISE NOTICE ' [PASS] Plugin subscriptions is active in public.system_plugins.';
    END IF;

    RAISE NOTICE '>>> [TEST 4] Verifying Billing, Wallet & Payment Permissions...';
    IF (SELECT count(*) FROM public.permissions WHERE module = 'billing') < 7 THEN
        RAISE EXCEPTION 'FAILED: Fewer than 7 billing permissions registered in public.permissions!';
    ELSE
        RAISE NOTICE ' [PASS] All 7 Billing, Wallet & Payment permissions registered successfully.';
    END IF;

    RAISE NOTICE '>>> [TEST 5] Verifying Tenant Xu Wallet Credit, Debit & Ledger Invariants...';
    INSERT INTO public.tenants (name, slug)
    VALUES ('Wallet Test Tenant', 'wallet-test-' || substr(md5(random()::text), 1, 8))
    RETURNING id INTO v_test_tenant_id;

    -- Credit 500 Xu
    v_balance := billing.credit_tenant_wallet(
        v_test_tenant_id,
        500,
        'topup',
        'manual',
        'seed-topup-001',
        'Initial topup 500 Xu'
    );
    IF v_balance <> 500 THEN
        RAISE EXCEPTION 'FAILED: Expected wallet balance 500 Xu after credit, got %', v_balance;
    END IF;

    -- Debit 180 Xu
    v_balance := billing.debit_tenant_wallet(
        v_test_tenant_id,
        180,
        'purchase',
        'commerce_order',
        'order-001',
        'Purchase digital item 180 Xu'
    );
    IF v_balance <> 320 THEN
        RAISE EXCEPTION 'FAILED: Expected wallet balance 320 Xu after debit, got %', v_balance;
    END IF;

    -- Verify Ledger Invariant: SUM(amount_credits) == balance_credits
    SELECT COALESCE(SUM(amount_credits), 0) INTO v_ledger_sum
    FROM billing.wallet_transactions
    WHERE tenant_id = v_test_tenant_id;

    IF v_ledger_sum <> 320 THEN
        RAISE EXCEPTION 'FAILED: Ledger sum (%) does not match wallet balance (320)!', v_ledger_sum;
    END IF;

    -- Verify Insufficient Funds Guard (> 320 Xu)
    BEGIN
        PERFORM billing.debit_tenant_wallet(
            v_test_tenant_id,
            400,
            'purchase',
            'commerce_order',
            'order-overdraft',
            'Should fail overdraft'
        );
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        v_err_caught := TRUE;
    END;

    IF NOT v_err_caught THEN
        RAISE EXCEPTION 'FAILED: Overdraft debit (> balance_credits) did not raise SQLSTATE P0001!';
    END IF;

    RAISE NOTICE ' [PASS] Tenant Xu Wallet credit, debit, ledger sum (320 Xu), and overdraft guard verified.';

    RAISE NOTICE '>>> [TEST 6] Verifying Active Payment Gateways Catalog...';
    SELECT count(*) INTO v_gateway_count FROM billing.get_active_gateways();
    IF v_gateway_count < 5 THEN
        RAISE EXCEPTION 'FAILED: Expected at least 5 active seeded gateways, found %', v_gateway_count;
    END IF;
    RAISE NOTICE ' [PASS] billing.get_active_gateways() returned % active payment channels.', v_gateway_count;

    RAISE NOTICE '>>> [TEST 7] Verifying Payment Intent Creation (Bank Transfer & Instant Internal Wallet)...';
    -- 7a. Create Bank Transfer Intent for 100 Xu (100,000 VND)
    v_bank_intent := billing.create_payment_intent(
        _gateway_id => 'bank_vietqr',
        _target_type => 'wallet_topup',
        _target_id => v_test_tenant_id::text,
        _amount_credits => 100,
        _tenant_id => v_test_tenant_id,
        _buyer_email => 'buyer@example.com'
    );

    v_bank_intent_id := (v_bank_intent->>'id')::UUID;
    v_bank_transfer_code := v_bank_intent->>'transfer_code';

    IF (v_bank_intent->>'status') <> 'pending'
       OR (v_bank_intent->>'pay_amount')::NUMERIC <> 100000
       OR v_bank_transfer_code !~ '^TQ[A-Z0-9]{6}$' THEN
        RAISE EXCEPTION 'FAILED: Invalid bank_vietqr payment intent payload: %', v_bank_intent;
    END IF;

    -- 7b. Create Instant Internal Wallet Intent for 50 Xu (Deducts from 320 Xu -> 270 Xu immediately)
    v_wallet_intent := billing.create_payment_intent(
        _gateway_id => 'internal_wallet',
        _target_type => 'commerce_order',
        _target_id => 'order-instant-002',
        _amount_credits => 50,
        _tenant_id => v_test_tenant_id,
        _buyer_email => 'buyer@example.com'
    );

    IF (v_wallet_intent->>'status') <> 'succeeded' THEN
        RAISE EXCEPTION 'FAILED: internal_wallet intent should settle immediately to succeeded, got %', v_wallet_intent;
    END IF;

    SELECT balance_credits INTO v_balance FROM billing.wallets WHERE tenant_id = v_test_tenant_id;
    IF v_balance <> 270 THEN
        RAISE EXCEPTION 'FAILED: Expected wallet balance 270 Xu after instant wallet payment, got %', v_balance;
    END IF;
    RAISE NOTICE ' [PASS] Payment intents created (Bank Transfer code %, Instant Wallet balance 270 Xu).', v_bank_transfer_code;

    RAISE NOTICE '>>> [TEST 8] Verifying Idempotent Webhook Settlement & Manual Review Queue...';
    -- Elevate role claim in session to simulate service_role webhook settlement
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);

    -- 8a. Settle the 100 Xu bank_vietqr top-up intent (270 Xu + 100 Xu = 370 Xu)
    v_settle_res := billing.settle_payment_intent(
        _intent_id => NULL,
        _transfer_code => v_bank_transfer_code,
        _provider_tx_id => 'SEPAY-TX-99001',
        _actual_pay_amount => 100000,
        _raw_metadata => '{"bank": "MBBank"}'::jsonb,
        _force_approve => FALSE
    );

    IF (v_settle_res->>'settled')::BOOLEAN IS NOT TRUE OR (v_settle_res->>'idempotent')::BOOLEAN IS TRUE THEN
        RAISE EXCEPTION 'FAILED: First settlement should return settled=true, idempotent=false: %', v_settle_res;
    END IF;

    -- 8b. Re-invoke with identical transfer_code & provider_tx_id (Idempotency Check)
    v_settle_idem := billing.settle_payment_intent(
        _intent_id => NULL,
        _transfer_code => v_bank_transfer_code,
        _provider_tx_id => 'SEPAY-TX-99001',
        _actual_pay_amount => 100000,
        _raw_metadata => '{"bank": "MBBank"}'::jsonb,
        _force_approve => FALSE
    );

    IF (v_settle_idem->>'settled')::BOOLEAN IS NOT TRUE OR (v_settle_idem->>'idempotent')::BOOLEAN IS NOT TRUE THEN
        RAISE EXCEPTION 'FAILED: Duplicate settlement should return settled=true, idempotent=true: %', v_settle_idem;
    END IF;

    SELECT balance_credits INTO v_balance FROM billing.wallets WHERE tenant_id = v_test_tenant_id;
    IF v_balance <> 370 THEN
        RAISE EXCEPTION 'FAILED: Idempotency check failed! Expected 370 Xu, got %', v_balance;
    END IF;

    -- 8c. Create an intent, expire it, and verify late transfer goes to manual_review
    v_late_intent := billing.create_payment_intent(
        _gateway_id => 'momo_ewallet',
        _target_type => 'wallet_topup',
        _target_id => v_test_tenant_id::text,
        _amount_credits => 30,
        _tenant_id => v_test_tenant_id,
        _buyer_email => 'late@example.com'
    );
    v_late_intent_id := (v_late_intent->>'id')::UUID;
    v_late_transfer_code := v_late_intent->>'transfer_code';

    UPDATE billing.payment_intents
    SET expires_at = timezone('utc'::text, now()) - INTERVAL '5 minutes'
    WHERE id = v_late_intent_id;

    v_settle_late := billing.settle_payment_intent(
        _intent_id => NULL,
        _transfer_code => v_late_transfer_code,
        _provider_tx_id => 'MOMO-TX-LATE-01',
        _actual_pay_amount => 30000,
        _raw_metadata => '{"channel": "momo"}'::jsonb,
        _force_approve => FALSE
    );

    IF (v_settle_late->>'settled')::BOOLEAN IS TRUE
       OR (v_settle_late->>'reason') <> 'expired_held_for_manual_review' THEN
        RAISE EXCEPTION 'FAILED: Late transfer should be held in manual_review, got: %', v_settle_late;
    END IF;

    IF (SELECT status FROM billing.payment_intents WHERE id = v_late_intent_id) <> 'manual_review' THEN
        RAISE EXCEPTION 'FAILED: Intent status in DB should be manual_review!';
    END IF;

    -- 8d. Force approve the manual_review intent (370 Xu + 30 Xu = 400 Xu)
    v_settle_force := billing.settle_payment_intent(
        _intent_id => v_late_intent_id,
        _transfer_code => NULL,
        _provider_tx_id => NULL,
        _actual_pay_amount => NULL,
        _raw_metadata => '{"approved_by": "platform_admin"}'::jsonb,
        _force_approve => TRUE
    );

    IF (v_settle_force->>'settled')::BOOLEAN IS NOT TRUE THEN
        RAISE EXCEPTION 'FAILED: Force approve on manual_review intent failed: %', v_settle_force;
    END IF;

    SELECT balance_credits INTO v_balance FROM billing.wallets WHERE tenant_id = v_test_tenant_id;
    IF v_balance <> 400 THEN
        RAISE EXCEPTION 'FAILED: Expected 400 Xu after force-approving manual_review intent, got %', v_balance;
    END IF;

    RAISE NOTICE ' [PASS] Idempotent settlement, manual_review queue, and force-approval verified (Final Balance: 400 Xu).';
END $$;

ROLLBACK;
