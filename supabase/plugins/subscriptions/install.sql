-- ============================================================================
-- TUQUET-CLOUD PLUGIN: SUBSCRIPTIONS, QUOTA & PAYMENT GATEWAY (INSTALLATION)
-- Plugin ID: subscriptions
-- Version: 1.2.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: billing)
-- ============================================================================

-- 1. Create Dedicated Schema & Grants
CREATE SCHEMA IF NOT EXISTS billing;
GRANT USAGE ON SCHEMA billing TO authenticated, service_role, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA billing GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA billing GRANT ALL ON FUNCTIONS TO authenticated, service_role, anon;

-- 2. Enums in schema billing
DO $$ BEGIN
    CREATE TYPE billing.subscription_status AS ENUM ('free_tier', 'trialing', 'active', 'past_due', 'canceled', 'unpaid');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE billing.wallet_tx_type AS ENUM ('topup', 'purchase', 'refund', 'admin_adjustment', 'bonus');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE billing.payment_channel AS ENUM ('internal_wallet', 'bank_transfer', 'e_wallet', 'card_intl', 'crypto');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE billing.payment_intent_status AS ENUM ('pending', 'processing', 'manual_review', 'succeeded', 'failed', 'expired', 'refunded');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE billing.payment_target_type AS ENUM ('wallet_topup', 'commerce_order', 'subscription_upgrade');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2.1. Core SaaS Subscription & Quota Tables
CREATE TABLE IF NOT EXISTS billing.plans (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    max_members INT NOT NULL DEFAULT 5,
    max_storage_mb BIGINT NOT NULL DEFAULT 500,
    max_monthly_runs INT NOT NULL DEFAULT 1000,
    price_monthly_usd NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE billing.plans IS '[Plugin: subscriptions] SaaS subscription tiers defining resource limits and pricing';

CREATE TABLE IF NOT EXISTS billing.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL UNIQUE REFERENCES public.tenants(id) ON DELETE CASCADE,
    plan_id TEXT NOT NULL REFERENCES billing.plans(id) ON DELETE RESTRICT,
    status billing.subscription_status NOT NULL DEFAULT 'free_tier',
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    current_period_start TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    current_period_end TIMESTAMPTZ NOT NULL DEFAULT (timezone('utc'::text, now()) + INTERVAL '100 years'),
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE billing.subscriptions IS '[Plugin: subscriptions] Active tenant subscription mapping to a billing plan';

CREATE TABLE IF NOT EXISTS billing.usage_meters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    metric_name VARCHAR(64) NOT NULL,
    current_value BIGINT NOT NULL DEFAULT 0,
    reset_at TIMESTAMPTZ NOT NULL DEFAULT (date_trunc('month', timezone('utc'::text, now())) + INTERVAL '1 month'),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_billing_tenant_metric UNIQUE (tenant_id, metric_name)
);

COMMENT ON TABLE billing.usage_meters IS '[Plugin: subscriptions] Generic usage counters tracked per tenant and metric';

-- 2.2. Tenant Xu Prepaid Wallet & Append-Only Transaction Ledger
CREATE TABLE IF NOT EXISTS billing.wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL UNIQUE REFERENCES public.tenants(id) ON DELETE CASCADE,
    balance_credits BIGINT NOT NULL DEFAULT 0 CHECK (balance_credits >= 0),
    total_topped_up_credits BIGINT NOT NULL DEFAULT 0 CHECK (total_topped_up_credits >= 0),
    total_spent_credits BIGINT NOT NULL DEFAULT 0 CHECK (total_spent_credits >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE billing.wallets IS '[Plugin: subscriptions] Tenant prepaid virtual currency wallet measured in integer Xu (credits)';

CREATE TABLE IF NOT EXISTS billing.wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES billing.wallets(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    tx_type billing.wallet_tx_type NOT NULL,
    amount_credits BIGINT NOT NULL CHECK (amount_credits <> 0),
    balance_after_credits BIGINT NOT NULL CHECK (balance_after_credits >= 0),
    reference_type TEXT,
    reference_id TEXT,
    description TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE billing.wallet_transactions IS '[Plugin: subscriptions] Immutable append-only audit ledger of all Tenant Xu balance mutations';

CREATE INDEX IF NOT EXISTS idx_billing_wallet_tx_tenant ON billing.wallet_transactions (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_billing_wallet_tx_created_brin ON billing.wallet_transactions USING brin (created_at);

-- 2.3. Pluggable Multi-Platform Payment Gateways & Isolated Secrets
CREATE TABLE IF NOT EXISTS billing.payment_gateways (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    channel billing.payment_channel NOT NULL,
    driver TEXT NOT NULL,
    currency TEXT NOT NULL DEFAULT 'VND',
    rate_per_credit NUMERIC(18, 6) NOT NULL DEFAULT 1000.000000 CHECK (rate_per_credit > 0),
    public_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE billing.payment_gateways IS '[Plugin: subscriptions] Public registry of extensible payment gateways and Xu conversion rates';

CREATE TABLE IF NOT EXISTS billing.payment_gateway_secrets (
    gateway_id TEXT PRIMARY KEY REFERENCES billing.payment_gateways(id) ON DELETE CASCADE,
    secret_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE billing.payment_gateway_secrets IS '[Plugin: subscriptions] Isolated webhook HMAC secrets and API keys (Service Role & Platform Admin ONLY)';

CREATE TABLE IF NOT EXISTS billing.payment_intents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
    gateway_id TEXT NOT NULL REFERENCES billing.payment_gateways(id) ON DELETE RESTRICT,
    target_type billing.payment_target_type NOT NULL,
    target_id TEXT NOT NULL,
    amount_credits BIGINT NOT NULL CHECK (amount_credits > 0),
    pay_currency TEXT NOT NULL,
    pay_amount NUMERIC(18, 2) NOT NULL CHECK (pay_amount > 0),
    transfer_code TEXT NOT NULL UNIQUE,
    status billing.payment_intent_status NOT NULL DEFAULT 'pending',
    checkout_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    provider_tx_id TEXT,
    buyer_email TEXT,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (timezone('utc'::text, now()) + INTERVAL '30 minutes'),
    paid_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE billing.payment_intents IS '[Plugin: subscriptions] Unified payment intent state machine supporting Tenant and Guest Storefront checkouts';

CREATE UNIQUE INDEX IF NOT EXISTS uq_billing_payment_intents_provider_tx
    ON billing.payment_intents (provider_tx_id)
    WHERE provider_tx_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_billing_payment_intents_tenant_status
    ON billing.payment_intents (tenant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_billing_payment_intents_transfer_code
    ON billing.payment_intents (transfer_code);
CREATE INDEX IF NOT EXISTS idx_billing_payment_intents_created_brin
    ON billing.payment_intents USING brin (created_at);

-- 2.4. Bank Receiving Accounts Pool Table
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

CREATE INDEX IF NOT EXISTS idx_billing_bank_accounts_active ON billing.bank_receiving_accounts (is_active, status, priority ASC);

-- 3. Seed Default Plans & Pluggable Payment Gateways
INSERT INTO billing.plans (id, name, description, max_members, max_storage_mb, max_monthly_runs, price_monthly_usd)
VALUES 
    ('free', 'Free Starter', 'Entry plan for individual developers and small tests', 2, 500, 1000, 0.00),
    ('pro', 'Team Pro', 'Advanced automation capabilities with team collaboration', 10, 10240, 50000, 29.00),
    ('enterprise', 'Enterprise Fleet', 'Dedicated workers, custom quotas, and SLAs', 100, 102400, 1000000, 199.00)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    max_members = EXCLUDED.max_members,
    max_storage_mb = EXCLUDED.max_storage_mb,
    max_monthly_runs = EXCLUDED.max_monthly_runs;

INSERT INTO billing.payment_gateways (id, name, channel, driver, currency, rate_per_credit, public_config, is_active, sort_order)
VALUES
    (
        'internal_wallet',
        'Vi Xu Noi Bo (Thanh toan tuc thi)',
        'internal_wallet',
        'ledger',
        'CREDITS',
        1.000000,
        '{"unit": "Xu", "instant": true}'::jsonb,
        TRUE,
        1
    ),
    (
        'bank_vietqr',
        'Chuyen khoan Ngan hang 24/7 (VietQR / Napas247)',
        'bank_transfer',
        'sepay',
        'VND',
        1000.000000,
        '{"bank_bin": "970422", "bank_name": "MBBank", "account_no": "0000123456789", "account_name": "TUQUET PLATFORM", "qr_template": "compact2"}'::jsonb,
        TRUE,
        2
    ),
    (
        'momo_ewallet',
        'Vi Dien Tu MoMo (QR / Chuyen khoan SĐT)',
        'e_wallet',
        'momo_ipn',
        'VND',
        1000.000000,
        '{"wallet_provider": "MoMo", "wallet_phone": "0900000000", "account_name": "TUQUET PLATFORM"}'::jsonb,
        TRUE,
        3
    ),
    (
        'stripe_card',
        'The Quoc Te Visa / Mastercard / Apple Pay (Stripe)',
        'card_intl',
        'stripe',
        'USD',
        0.040000,
        '{"provider": "Stripe", "supported_cards": ["visa", "mastercard", "amex", "apple_pay"]}'::jsonb,
        TRUE,
        4
    ),
    (
        'crypto_usdt',
        'Tien Ma Hoa USDT (TRC20 / BEP20 / Binance Pay)',
        'crypto',
        'trc20',
        'USDT',
        0.040000,
        '{"network": "TRC20", "token": "USDT", "wallet_address": "T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb"}'::jsonb,
        TRUE,
        5
    )
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    channel = EXCLUDED.channel,
    driver = EXCLUDED.driver,
    currency = EXCLUDED.currency,
    rate_per_credit = EXCLUDED.rate_per_credit,
    public_config = EXCLUDED.public_config,
    sort_order = EXCLUDED.sort_order;

INSERT INTO billing.payment_gateway_secrets (gateway_id, secret_config)
VALUES
    ('bank_vietqr', '{"webhook_secret": "test-sepay-hmac-secret-placeholder"}'::jsonb),
    ('momo_ewallet', '{"webhook_secret": "test-momo-hmac-secret-placeholder"}'::jsonb),
    ('stripe_card', '{"webhook_secret": "whsec_test_stripe_placeholder"}'::jsonb),
    ('crypto_usdt', '{"webhook_secret": "test-crypto-hmac-secret-placeholder"}'::jsonb)
ON CONFLICT (gateway_id) DO NOTHING;

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

-- 4. Generic Quota Checking & Usage Recording Functions
CREATE OR REPLACE FUNCTION billing.check_tenant_quota(
    _tenant_id UUID, 
    _metric_name TEXT, 
    _increment BIGINT DEFAULT 1
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_plan_id TEXT;
    v_max_members INT;
    v_max_storage_mb BIGINT;
    v_max_monthly_runs INT;
    v_current_count BIGINT;
BEGIN
    SELECT s.plan_id INTO v_plan_id
    FROM billing.subscriptions s
    WHERE s.tenant_id = _tenant_id AND s.status IN ('free_tier', 'trialing', 'active')
    LIMIT 1;

    IF v_plan_id IS NULL THEN v_plan_id := 'free'; END IF;

    SELECT max_members, max_storage_mb, max_monthly_runs 
    INTO v_max_members, v_max_storage_mb, v_max_monthly_runs
    FROM billing.plans WHERE id = v_plan_id;

    IF _metric_name = 'members' THEN
        SELECT COUNT(*) INTO v_current_count FROM public.tenant_members WHERE tenant_id = _tenant_id AND status = 'active';
        RETURN (v_current_count + _increment) <= v_max_members;
    ELSIF _metric_name = 'monthly_runs' THEN
        SELECT 
            CASE 
                WHEN timezone('utc'::text, now()) >= reset_at THEN 0 
                ELSE COALESCE(current_value, 0) 
            END INTO v_current_count 
        FROM billing.usage_meters 
        WHERE tenant_id = _tenant_id AND metric_name = 'monthly_runs';

        IF v_current_count IS NULL THEN v_current_count := 0; END IF;
        RETURN (v_current_count + _increment) <= v_max_monthly_runs;
    ELSIF _metric_name = 'storage_mb' THEN
        SELECT COALESCE(current_value, 0) INTO v_current_count FROM billing.usage_meters WHERE tenant_id = _tenant_id AND metric_name = 'storage_mb';
        IF v_current_count IS NULL THEN v_current_count := 0; END IF;
        RETURN (v_current_count + _increment) <= v_max_storage_mb;
    END IF;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION billing.record_usage(
    _tenant_id UUID,
    _metric_name TEXT,
    _increment BIGINT DEFAULT 1
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_new_val BIGINT;
BEGIN
    INSERT INTO billing.usage_meters (tenant_id, metric_name, current_value, reset_at, updated_at)
    VALUES (
        _tenant_id,
        _metric_name,
        _increment,
        (date_trunc('month', timezone('utc'::text, now())) + INTERVAL '1 month'),
        timezone('utc'::text, now())
    )
    ON CONFLICT (tenant_id, metric_name) DO UPDATE SET
        current_value = CASE 
            WHEN timezone('utc'::text, now()) >= billing.usage_meters.reset_at THEN EXCLUDED.current_value
            ELSE billing.usage_meters.current_value + EXCLUDED.current_value
        END,
        reset_at = CASE 
            WHEN timezone('utc'::text, now()) >= billing.usage_meters.reset_at THEN (date_trunc('month', timezone('utc'::text, now())) + INTERVAL '1 month')
            ELSE billing.usage_meters.reset_at
        END,
        updated_at = timezone('utc'::text, now())
    RETURNING current_value INTO v_new_val;

    RETURN v_new_val;
END;
$$;

-- 4.1. Atomic Tenant Xu Wallet Credit & Debit Functions
CREATE OR REPLACE FUNCTION billing.credit_tenant_wallet(
    _tenant_id UUID,
    _amount_credits BIGINT,
    _tx_type billing.wallet_tx_type DEFAULT 'topup',
    _reference_type TEXT DEFAULT NULL,
    _reference_id TEXT DEFAULT NULL,
    _description TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_wallet_id UUID;
    v_new_balance BIGINT;
BEGIN
    IF _amount_credits IS NULL OR _amount_credits <= 0 THEN
        RAISE EXCEPTION 'Credit amount in Xu must be strictly positive (got %)', _amount_credits
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO billing.wallets (
        tenant_id,
        balance_credits,
        total_topped_up_credits,
        total_spent_credits,
        updated_at
    )
    VALUES (
        _tenant_id,
        _amount_credits,
        CASE WHEN _tx_type IN ('topup', 'bonus', 'admin_adjustment') THEN _amount_credits ELSE 0 END,
        0,
        timezone('utc'::text, now())
    )
    ON CONFLICT (tenant_id) DO UPDATE SET
        balance_credits = billing.wallets.balance_credits + EXCLUDED.balance_credits,
        total_topped_up_credits = billing.wallets.total_topped_up_credits + (
            CASE WHEN _tx_type IN ('topup', 'bonus', 'admin_adjustment') THEN _amount_credits ELSE 0 END
        ),
        updated_at = timezone('utc'::text, now())
    RETURNING id, balance_credits INTO v_wallet_id, v_new_balance;

    INSERT INTO billing.wallet_transactions (
        wallet_id,
        tenant_id,
        tx_type,
        amount_credits,
        balance_after_credits,
        reference_type,
        reference_id,
        description,
        created_by,
        created_at
    )
    VALUES (
        v_wallet_id,
        _tenant_id,
        _tx_type,
        _amount_credits,
        v_new_balance,
        _reference_type,
        _reference_id,
        _description,
        auth.uid(),
        timezone('utc'::text, now())
    );

    RETURN v_new_balance;
END;
$$;

CREATE OR REPLACE FUNCTION billing.debit_tenant_wallet(
    _tenant_id UUID,
    _amount_credits BIGINT,
    _tx_type billing.wallet_tx_type DEFAULT 'purchase',
    _reference_type TEXT DEFAULT NULL,
    _reference_id TEXT DEFAULT NULL,
    _description TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_wallet billing.wallets%ROWTYPE;
    v_new_balance BIGINT;
BEGIN
    IF _amount_credits IS NULL OR _amount_credits <= 0 THEN
        RAISE EXCEPTION 'Debit amount in Xu must be strictly positive (got %)', _amount_credits
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO billing.wallets (tenant_id, balance_credits, total_topped_up_credits, total_spent_credits)
    VALUES (_tenant_id, 0, 0, 0)
    ON CONFLICT (tenant_id) DO NOTHING;

    SELECT * INTO v_wallet
    FROM billing.wallets
    WHERE tenant_id = _tenant_id
    FOR UPDATE;

    IF v_wallet.balance_credits < _amount_credits THEN
        RAISE EXCEPTION 'Insufficient Xu balance: required % Xu, available % Xu', _amount_credits, v_wallet.balance_credits
            USING ERRCODE = 'P0001';
    END IF;

    v_new_balance := v_wallet.balance_credits - _amount_credits;

    UPDATE billing.wallets
    SET balance_credits = v_new_balance,
        total_spent_credits = total_spent_credits + _amount_credits,
        updated_at = timezone('utc'::text, now())
    WHERE id = v_wallet.id;

    INSERT INTO billing.wallet_transactions (
        wallet_id,
        tenant_id,
        tx_type,
        amount_credits,
        balance_after_credits,
        reference_type,
        reference_id,
        description,
        created_by,
        created_at
    )
    VALUES (
        v_wallet.id,
        _tenant_id,
        _tx_type,
        -_amount_credits,
        v_new_balance,
        _reference_type,
        _reference_id,
        _description,
        auth.uid(),
        timezone('utc'::text, now())
    );

    RETURN v_new_balance;
END;
$$;

-- 4.2. Payment Gateways Discovery & Payment Intent Lifecycle RPCs
CREATE OR REPLACE FUNCTION billing.get_active_gateways()
RETURNS TABLE (
    id TEXT,
    name TEXT,
    channel billing.payment_channel,
    driver TEXT,
    currency TEXT,
    rate_per_credit NUMERIC(18, 6),
    public_config JSONB,
    sort_order INT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT
        pg.id,
        pg.name,
        pg.channel,
        pg.driver,
        pg.currency,
        pg.rate_per_credit,
        pg.public_config,
        pg.sort_order
    FROM billing.payment_gateways pg
    WHERE pg.is_active = TRUE
    ORDER BY pg.sort_order ASC, pg.id ASC;
$$;

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
AS $$
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
$$;

CREATE OR REPLACE FUNCTION billing.settle_payment_intent(
    _intent_id UUID DEFAULT NULL,
    _transfer_code TEXT DEFAULT NULL,
    _provider_tx_id TEXT DEFAULT NULL,
    _actual_pay_amount NUMERIC DEFAULT NULL,
    _raw_metadata JSONB DEFAULT '{}'::jsonb,
    _force_approve BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_intent billing.payment_intents%ROWTYPE;
    v_new_balance BIGINT;
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
BEGIN
    -- 1. Authorize caller: Only service_role (Webhook Edge Function), postgres superuser (tests), or Platform Admin
    IF current_setting('request.jwt.claim.role', true) IS DISTINCT FROM 'service_role'
       AND current_user NOT IN ('postgres', 'supabase_admin')
       AND NOT public.is_platform_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only payment webhook service or platform admin can settle intents'
            USING ERRCODE = '42501';
    END IF;

    -- 2. Locate and lock the payment intent atomically
    SELECT * INTO v_intent
    FROM billing.payment_intents pi
    WHERE (_intent_id IS NOT NULL AND pi.id = _intent_id)
       OR (_transfer_code IS NOT NULL AND pi.transfer_code = UPPER(TRIM(_transfer_code)))
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('settled', false, 'reason', 'intent_not_found');
    END IF;

    -- 3. Idempotency guard: If already succeeded, return early without double-crediting
    IF v_intent.status = 'succeeded' THEN
        RETURN jsonb_build_object('settled', true, 'idempotent', true, 'intent_id', v_intent.id);
    END IF;

    IF v_intent.status NOT IN ('pending', 'processing', 'manual_review', 'expired') THEN
        RETURN jsonb_build_object('settled', false, 'reason', 'invalid_intent_state', 'status', v_intent.status);
    END IF;

    -- 4. Late transfer guard: If expired (> 30m) and not force-approved by Admin, hold in manual_review
    IF (v_intent.status = 'expired' OR v_now > v_intent.expires_at) AND NOT _force_approve THEN
        UPDATE billing.payment_intents
        SET status = 'manual_review',
            provider_tx_id = COALESCE(_provider_tx_id, provider_tx_id),
            checkout_payload = checkout_payload || jsonb_build_object(
                'review_reason', 'late_transfer_after_expiry',
                'received_amount', _actual_pay_amount,
                'received_at', v_now,
                'webhook_meta', _raw_metadata
            ),
            updated_at = v_now
        WHERE id = v_intent.id;

        RETURN jsonb_build_object(
            'settled', false,
            'reason', 'expired_held_for_manual_review',
            'intent_id', v_intent.id
        );
    END IF;

    -- 5. Underpaid guard: If paid amount < expected pay_amount and not force-approved, hold in manual_review
    IF _actual_pay_amount IS NOT NULL AND _actual_pay_amount < v_intent.pay_amount AND NOT _force_approve THEN
        UPDATE billing.payment_intents
        SET status = 'manual_review',
            provider_tx_id = COALESCE(_provider_tx_id, provider_tx_id),
            checkout_payload = checkout_payload || jsonb_build_object(
                'review_reason', 'underpaid',
                'expected_amount', v_intent.pay_amount,
                'received_amount', _actual_pay_amount,
                'webhook_meta', _raw_metadata
            ),
            updated_at = v_now
        WHERE id = v_intent.id;

        RETURN jsonb_build_object(
            'settled', false,
            'reason', 'underpaid_held_for_manual_review',
            'intent_id', v_intent.id,
            'expected', v_intent.pay_amount,
            'received', _actual_pay_amount
        );
    END IF;

    -- 6. Mark intent as succeeded
    UPDATE billing.payment_intents
    SET status = 'succeeded',
        provider_tx_id = COALESCE(_provider_tx_id, provider_tx_id),
        paid_at = v_now,
        checkout_payload = CASE
            WHEN _force_approve THEN checkout_payload || jsonb_build_object('force_approved_at', v_now, 'approval_meta', _raw_metadata)
            ELSE checkout_payload
        END,
        updated_at = v_now
    WHERE id = v_intent.id;

    -- 7. Execute target settlement action (wallet_topup | subscription_upgrade | commerce_order)
    IF v_intent.target_type = 'wallet_topup' AND v_intent.tenant_id IS NOT NULL THEN
        v_new_balance := billing.credit_tenant_wallet(
            v_intent.tenant_id,
            v_intent.amount_credits,
            'topup',
            'payment_intent',
            v_intent.id::text,
            'Nap ' || v_intent.amount_credits || ' Xu qua ' || v_intent.gateway_id || ' (' || v_intent.transfer_code || ')'
        );
    ELSIF v_intent.target_type = 'subscription_upgrade' AND v_intent.tenant_id IS NOT NULL THEN
        UPDATE billing.subscriptions
        SET plan_id = v_intent.target_id,
            status = 'active',
            current_period_start = v_now,
            current_period_end = v_now + INTERVAL '30 days',
            updated_at = v_now
        WHERE tenant_id = v_intent.tenant_id;
    END IF;

    -- 8. Emit transactional outbox event for downstream consumers (e.g. commerce.orders fulfillment)
    IF EXISTS (
        SELECT 1 FROM information_schema.routines
        WHERE routine_schema = 'events' AND routine_name = 'emit_event'
    ) AND v_intent.tenant_id IS NOT NULL THEN
        -- Use direct outbox insert to avoid caller tenant membership check when invoked by service_role
        INSERT INTO events.outbox (tenant_id, event_type, payload, status, created_at)
        VALUES (
            v_intent.tenant_id,
            'billing.payment.succeeded',
            jsonb_build_object(
                'intent_id', v_intent.id,
                'target_type', v_intent.target_type,
                'target_id', v_intent.target_id,
                'amount_credits', v_intent.amount_credits,
                'gateway_id', v_intent.gateway_id,
                'transfer_code', v_intent.transfer_code
            ),
            'pending',
            v_now
        );
    END IF;

    RETURN jsonb_build_object(
        'settled', true,
        'idempotent', false,
        'intent_id', v_intent.id,
        'target_type', v_intent.target_type,
        'target_id', v_intent.target_id,
        'amount_credits', v_intent.amount_credits
    );
END;
$$;

-- 5. RLS
ALTER TABLE billing.plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.usage_meters ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.payment_gateways ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.payment_gateway_secrets ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.payment_intents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "plans_select" ON billing.plans;
CREATE POLICY "plans_select" ON billing.plans FOR SELECT TO authenticated USING (is_active = TRUE);

DROP POLICY IF EXISTS "subscriptions_select" ON billing.subscriptions;
CREATE POLICY "subscriptions_select" ON billing.subscriptions FOR SELECT TO authenticated USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "subscriptions_manage" ON billing.subscriptions;
CREATE POLICY "subscriptions_manage" ON billing.subscriptions
    FOR UPDATE TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'subscriptions:manage') OR public.is_tenant_admin(tenant_id))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'subscriptions:manage') OR public.is_tenant_admin(tenant_id));

DROP POLICY IF EXISTS "meters_select" ON billing.usage_meters;
CREATE POLICY "meters_select" ON billing.usage_meters FOR SELECT TO authenticated USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "wallets_select" ON billing.wallets;
CREATE POLICY "wallets_select" ON billing.wallets FOR SELECT TO authenticated USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "wallet_transactions_select" ON billing.wallet_transactions;
CREATE POLICY "wallet_transactions_select" ON billing.wallet_transactions FOR SELECT TO authenticated USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "payment_gateways_select" ON billing.payment_gateways;
CREATE POLICY "payment_gateways_select" ON billing.payment_gateways FOR SELECT TO authenticated, anon USING (is_active = TRUE);

DROP POLICY IF EXISTS "payment_intents_select" ON billing.payment_intents;
CREATE POLICY "payment_intents_select" ON billing.payment_intents FOR SELECT TO authenticated
    USING (tenant_id IS NOT NULL AND public.is_tenant_member(tenant_id));

-- Platform superadmin: full control over plans, subscriptions, wallets, gateways, secrets, and payment intents
DROP POLICY IF EXISTS "plans_platform_admin" ON billing.plans;
CREATE POLICY "plans_platform_admin" ON billing.plans FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "subscriptions_platform_admin" ON billing.subscriptions;
CREATE POLICY "subscriptions_platform_admin" ON billing.subscriptions FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "wallets_platform_admin" ON billing.wallets;
CREATE POLICY "wallets_platform_admin" ON billing.wallets FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "wallet_tx_platform_admin" ON billing.wallet_transactions;
CREATE POLICY "wallet_tx_platform_admin" ON billing.wallet_transactions FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "payment_gateways_platform_admin" ON billing.payment_gateways;
CREATE POLICY "payment_gateways_platform_admin" ON billing.payment_gateways FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "payment_gateway_secrets_platform_admin" ON billing.payment_gateway_secrets;
CREATE POLICY "payment_gateway_secrets_platform_admin" ON billing.payment_gateway_secrets FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "payment_intents_platform_admin" ON billing.payment_intents;
CREATE POLICY "payment_intents_platform_admin" ON billing.payment_intents FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

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

-- 6. Permissions
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('subscriptions:read',   'billing', 'View subscription plans and current tenant status'),
    ('subscriptions:manage', 'billing', 'Upgrade, downgrade, or cancel tenant subscription'),
    ('quota:read',           'billing', 'View usage meters and limits'),
    ('wallets:read',         'billing', 'View tenant Xu wallet balance and transaction ledger'),
    ('wallets:manage',       'billing', 'Top up or spend from tenant Xu wallet'),
    ('payments:read',        'billing', 'View payment gateways and payment intents'),
    ('payments:manage',      'billing', 'Configure payment gateways and approve manual_review intents')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES
        ('subscriptions:read'),
        ('subscriptions:manage'),
        ('quota:read'),
        ('wallets:read'),
        ('wallets:manage'),
        ('payments:read'),
        ('payments:manage')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES ('subscriptions:read'), ('quota:read'), ('wallets:read'), ('payments:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 7. Register Plugin in Master Registry
SELECT public.register_plugin(
    'subscriptions',
    'Subscriptions, Quota & Payment Gateway',
    '1.2.0',
    'billing',
    ARRAY[]::TEXT[],
    'SaaS Subscription Tiers, Usage Metering, Tenant Xu Wallet Ledger, and Multi-Platform Payment Gateway',
    FALSE,
    '{"default_currency": "CREDITS", "unit_label": "Xu"}'::jsonb
);
