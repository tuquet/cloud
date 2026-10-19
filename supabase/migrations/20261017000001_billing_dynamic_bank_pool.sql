-- ============================================================================
-- SUPABASE MIGRATION: DYNAMIC BANK RECEIVING ACCOUNT POOL & ROTATION ENGINE
-- Version: 1.3.0
-- Architecture: Dedicated Schema 'billing' with Zero-Downtime Account Rotation
-- ============================================================================

-- 1. Create Bank Receiving Accounts Pool Table
CREATE TABLE IF NOT EXISTS billing.bank_receiving_accounts (
    id TEXT PRIMARY KEY,
    bank_bin VARCHAR(16) NOT NULL,
    bank_name VARCHAR(64) NOT NULL,
    account_no VARCHAR(64) NOT NULL,
    account_name VARCHAR(128) NOT NULL,
    qr_template VARCHAR(32) NOT NULL DEFAULT 'compact2',
    daily_limit_vnd NUMERIC(18, 2) NOT NULL DEFAULT 300000000.00,
    current_daily_total NUMERIC(18, 2) NOT NULL DEFAULT 0.00,
    daily_reset_at TIMESTAMPTZ NOT NULL DEFAULT (date_trunc('day', timezone('utc'::text, now())) + INTERVAL '1 day'),
    priority INT NOT NULL DEFAULT 10,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    status VARCHAR(32) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'cooling', 'suspended', 'maintenance')),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE billing.bank_receiving_accounts IS '[Plugin: subscriptions] Dynamic receiving account pool supporting MMO multi-bank rotation and daily limit guards';

-- 2. Indexes for fast lookup of eligible active accounts
CREATE INDEX IF NOT EXISTS idx_billing_bank_accounts_active ON billing.bank_receiving_accounts (is_active, status, priority ASC);

-- 3. RLS for bank_receiving_accounts
ALTER TABLE billing.bank_receiving_accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bank_accounts_select_policy" ON billing.bank_receiving_accounts;
CREATE POLICY "bank_accounts_select_policy" ON billing.bank_receiving_accounts
    FOR SELECT TO authenticated, anon
    USING (is_active = TRUE AND status = 'active');

DROP POLICY IF EXISTS "bank_accounts_admin_full_policy" ON billing.bank_receiving_accounts;
CREATE POLICY "bank_accounts_admin_full_policy" ON billing.bank_receiving_accounts
    FOR ALL TO authenticated
    USING (public.is_platform_admin())
    WITH CHECK (public.is_platform_admin());

-- 4. Stored Procedure: Select Next Best Receiving Account (Round-Robin / Least Loaded under Daily Limit)
CREATE OR REPLACE FUNCTION billing.get_next_receiving_account(
    _amount_vnd NUMERIC DEFAULT 0
)
RETURNS billing.bank_receiving_accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_account billing.bank_receiving_accounts%ROWTYPE;
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
BEGIN
    -- 1. Reset daily limits if new UTC calendar day
    UPDATE billing.bank_receiving_accounts
    SET current_daily_total = 0.00,
        daily_reset_at = date_trunc('day', v_now) + INTERVAL '1 day'
    WHERE daily_reset_at <= v_now;

    -- 2. Pick the active account with highest priority and remaining quota
    SELECT * INTO v_account
    FROM billing.bank_receiving_accounts bra
    WHERE bra.is_active = TRUE
      AND bra.status = 'active'
      AND (bra.current_daily_total + COALESCE(_amount_vnd, 0) <= bra.daily_limit_vnd)
    ORDER BY bra.priority ASC, (bra.current_daily_total / NULLIF(bra.daily_limit_vnd, 0)) ASC, bra.created_at ASC
    LIMIT 1;

    -- 3. Fallback: If all active accounts exceeded limit, pick the one with lowest load or highest priority
    IF v_account.id IS NULL THEN
        SELECT * INTO v_account
        FROM billing.bank_receiving_accounts bra
        WHERE bra.is_active = TRUE
          AND bra.status IN ('active', 'cooling')
        ORDER BY bra.priority ASC, bra.current_daily_total ASC
        LIMIT 1;
    END IF;

    RETURN v_account;
END;
$$;

-- 5. Upgrade billing.create_payment_intent to use Dynamic Account Pool for bank_transfer (if subscriptions plugin installed)
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_type t 
        JOIN pg_namespace n ON n.oid = t.typnamespace 
        WHERE n.nspname = 'billing' AND t.typname = 'payment_target_type'
    ) AND EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'billing' AND table_name = 'payment_gateways'
    ) THEN
        EXECUTE $fn$
CREATE OR REPLACE FUNCTION billing.create_payment_intent(
    _gateway_id TEXT,
    _target_type billing.payment_target_type,
    _target_id TEXT,
    _amount_credits BIGINT,
    _tenant_id UUID DEFAULT NULL,
    _buyer_email TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $body$
DECLARE
    v_gateway billing.payment_gateways%ROWTYPE;
    v_bank_acc billing.bank_receiving_accounts%ROWTYPE;
    v_pay_amount NUMERIC(18, 2);
    v_transfer_code TEXT;
    v_checkout_payload JSONB;
    v_status billing.payment_intent_status := 'pending';
    v_paid_at TIMESTAMPTZ := NULL;
    v_intent billing.payment_intents%ROWTYPE;
    v_new_balance BIGINT;
    v_bank_bin TEXT;
    v_account_no TEXT;
    v_account_name TEXT;
    v_qr_template TEXT;
BEGIN
    IF _amount_credits IS NULL OR _amount_credits <= 0 THEN
        RAISE EXCEPTION 'Payment amount_credits must be strictly positive (got %)', _amount_credits
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_gateway
    FROM billing.payment_gateways
    WHERE id = _gateway_id AND is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment gateway % is not found or inactive', _gateway_id
            USING ERRCODE = '22023';
    END IF;

    -- Compute fiat/crypto amount from integer Xu credits
    IF v_gateway.currency = 'VND' THEN
        v_pay_amount := ROUND(_amount_credits * v_gateway.rate_per_credit, 0);
    ELSE
        v_pay_amount := ROUND(_amount_credits * v_gateway.rate_per_credit, 2);
    END IF;

    -- Generate deterministic 8-char alphanumeric memo code: TQ + 6 uppercase hex/alphanumeric chars
    LOOP
        v_transfer_code := 'TQ' || UPPER(SUBSTR(MD5(gen_random_uuid()::text || clock_timestamp()::text), 1, 6));
        EXIT WHEN NOT EXISTS (SELECT 1 FROM billing.payment_intents WHERE transfer_code = v_transfer_code);
    END LOOP;

    -- Build channel-specific checkout payload with dynamic bank rotation
    IF v_gateway.channel = 'bank_transfer' THEN
        -- Dynamic account selection from pool
        v_bank_acc := billing.get_next_receiving_account(v_pay_amount);

        IF v_bank_acc.id IS NOT NULL THEN
            v_bank_bin := v_bank_acc.bank_bin;
            v_account_no := v_bank_acc.account_no;
            v_account_name := v_bank_acc.account_name;
            v_qr_template := v_bank_acc.qr_template;
        ELSE
            -- Static fallback if bank pool table is unseeded
            v_bank_bin := COALESCE(v_gateway.public_config->>'bank_bin', '970422');
            v_account_no := COALESCE(v_gateway.public_config->>'account_no', '0000123456789');
            v_account_name := COALESCE(v_gateway.public_config->>'account_name', 'TUQUET PLATFORM');
            v_qr_template := COALESCE(v_gateway.public_config->>'qr_template', 'compact2');
        END IF;

        v_checkout_payload := v_gateway.public_config || jsonb_build_object(
            'bank_bin', v_bank_bin,
            'account_no', v_account_no,
            'account_name', v_account_name,
            'receiving_account_id', v_bank_acc.id,
            'transfer_code', v_transfer_code,
            'pay_amount', v_pay_amount,
            'pay_currency', v_gateway.currency,
            'qr_image_url', format(
                'https://img.vietqr.io/image/%s-%s-%s.png?amount=%s&addInfo=%s',
                v_bank_bin,
                v_account_no,
                v_qr_template,
                v_pay_amount::bigint,
                v_transfer_code
            )
        );
    ELSIF v_gateway.channel = 'e_wallet' THEN
        v_checkout_payload := v_gateway.public_config || jsonb_build_object(
            'transfer_code', v_transfer_code,
            'pay_amount', v_pay_amount,
            'pay_currency', v_gateway.currency
        );
    ELSIF v_gateway.channel = 'card_intl' THEN
        v_checkout_payload := v_gateway.public_config || jsonb_build_object(
            'transfer_code', v_transfer_code,
            'pay_amount', v_pay_amount,
            'pay_currency', v_gateway.currency,
            'client_secret', 'mock_stripe_sec_' || lower(v_transfer_code)
        );
    ELSIF v_gateway.channel = 'crypto' THEN
        v_checkout_payload := v_gateway.public_config || jsonb_build_object(
            'transfer_code', v_transfer_code,
            'pay_amount', v_pay_amount,
            'pay_currency', v_gateway.currency,
            'deposit_memo', v_transfer_code
        );
    ELSIF v_gateway.channel = 'internal_wallet' THEN
        IF _tenant_id IS NULL THEN
            RAISE EXCEPTION 'Internal wallet payment requires an authenticated tenant_id'
                USING ERRCODE = '22023';
        END IF;

        -- Atomic immediate debit from Xu balance
        v_new_balance := billing.debit_tenant_wallet(
            _tenant_id,
            _amount_credits,
            'purchase',
            _target_type::text,
            _target_id,
            'Thanh toan tuc thi qua Vi Xu Noi Bo (' || v_transfer_code || ')'
        );

        v_status := 'succeeded';
        v_paid_at := timezone('utc'::text, now());
        v_checkout_payload := jsonb_build_object(
            'instant_paid', true,
            'balance_after_credits', v_new_balance,
            'transfer_code', v_transfer_code
        );
    END IF;

    -- Record immutable payment intent
    INSERT INTO billing.payment_intents (
        tenant_id,
        gateway_id,
        target_type,
        target_id,
        amount_credits,
        pay_currency,
        pay_amount,
        transfer_code,
        status,
        checkout_payload,
        buyer_email,
        paid_at,
        created_by
    )
    VALUES (
        _tenant_id,
        _gateway_id,
        _target_type,
        _target_id,
        _amount_credits,
        v_gateway.currency,
        v_pay_amount,
        v_transfer_code,
        v_status,
        v_checkout_payload,
        _buyer_email,
        v_paid_at,
        auth.uid()
    )
    RETURNING * INTO v_intent;

    RETURN to_jsonb(v_intent);
END;
$body$;
        $fn$;
    END IF;
END $$;

-- 6. Seed initial pool accounts
INSERT INTO billing.bank_receiving_accounts (id, bank_bin, bank_name, account_no, account_name, qr_template, daily_limit_vnd, priority, is_active, status)
VALUES
    ('mbbank_primary', '970422', 'MBBank', '0000123456789', 'TUQUET PLATFORM', 'compact2', 300000000.00, 1, TRUE, 'active'),
    ('vpbank_secondary', '970432', 'VPBank', '9888777666', 'TUQUET MEDIA CORP', 'compact2', 500000000.00, 2, TRUE, 'active'),
    ('techcombank_backup', '970407', 'Techcombank', '19033445566778', 'NGUYEN DINH TU', 'compact2', 150000000.00, 3, TRUE, 'active')
ON CONFLICT (id) DO UPDATE SET
    bank_name = EXCLUDED.bank_name,
    account_no = EXCLUDED.account_no,
    account_name = EXCLUDED.account_name,
    daily_limit_vnd = EXCLUDED.daily_limit_vnd;
