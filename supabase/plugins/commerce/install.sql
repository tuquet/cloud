-- ============================================================================
-- TUQUET-CLOUD PLUGIN: DIGITAL PRODUCTS STORE & AUTO-FULFILLMENT (INSTALLATION)
-- Plugin ID: commerce
-- Version: 1.0.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: commerce)
-- Dependencies: ["subscriptions", "workers", "automation", "storage"]
-- ============================================================================

-- 1. Create Dedicated Schema & Grants
CREATE SCHEMA IF NOT EXISTS commerce;
GRANT USAGE ON SCHEMA commerce TO authenticated, service_role, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA commerce GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA commerce GRANT ALL ON FUNCTIONS TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA commerce GRANT ALL ON SEQUENCES TO authenticated, service_role;

-- 2. Enums in schema commerce
DO $$ BEGIN
    CREATE TYPE commerce.product_type AS ENUM (
        'serial_stock',
        'resource',
        'digital_file',
        'wallet_credit'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE commerce.stock_status AS ENUM (
        'available',
        'reserved',
        'sold',
        'defective'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE commerce.order_status AS ENUM (
        'pending_payment',
        'paid',
        'fulfilling',
        'completed',
        'manual_review',
        'failed',
        'cancelled',
        'refunded'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. Tables in schema commerce

-- 3.1. Product Categories
CREATE TABLE IF NOT EXISTS commerce.categories (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    slug VARCHAR(64) NOT NULL UNIQUE,
    name VARCHAR(128) NOT NULL,
    description TEXT,
    icon VARCHAR(64),
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE commerce.categories IS '[Plugin: commerce] Digital store product categories';

-- 3.2. Digital Products
CREATE TABLE IF NOT EXISTS commerce.products (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    category_id UUID REFERENCES commerce.categories(id) ON DELETE SET NULL,
    slug VARCHAR(128) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    short_description TEXT,
    description TEXT,
    product_type commerce.product_type NOT NULL,
    visibility VARCHAR(16) NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'tenant_only', 'hidden')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    thumbnail_url TEXT,
    tags TEXT[] NOT NULL DEFAULT '{}'::text[],
    fulfillment_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE commerce.products IS '[Plugin: commerce] Multi-type digital products catalog (serial_stock, resource, digital_file, wallet_credit)';

CREATE INDEX IF NOT EXISTS idx_commerce_products_category_active
    ON commerce.products (category_id, is_active, sort_order);

-- 3.3. Product Variants & Pricing (in Integer Xu Credits)
CREATE TABLE IF NOT EXISTS commerce.product_variants (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES commerce.products(id) ON DELETE CASCADE,
    sku VARCHAR(64) NOT NULL UNIQUE,
    name VARCHAR(128) NOT NULL,
    price_credits BIGINT NOT NULL CHECK (price_credits >= 0),
    compare_at_credits BIGINT CHECK (compare_at_credits IS NULL OR compare_at_credits >= price_credits),
    stock_mode VARCHAR(16) NOT NULL DEFAULT 'unlimited' CHECK (stock_mode IN ('unlimited', 'serialized', 'finite_counter')),
    available_stock INT NOT NULL DEFAULT 0 CHECK (available_stock >= 0),
    sold_count INT NOT NULL DEFAULT 0 CHECK (sold_count >= 0),
    min_qty INT NOT NULL DEFAULT 1 CHECK (min_qty >= 1),
    max_qty INT NOT NULL DEFAULT 100 CHECK (max_qty >= min_qty),
    fulfillment_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE commerce.product_variants IS '[Plugin: commerce] Purchasable SKUs priced in integer Xu credits with stock tracking';

CREATE INDEX IF NOT EXISTS idx_commerce_variants_product_active
    ON commerce.product_variants (product_id, is_active, sort_order);

-- 3.4. Isolated Serialized Stock Inventory (Accounts, License Keys, Proxy Pool Lines)
CREATE TABLE IF NOT EXISTS commerce.stock_items (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    variant_id UUID NOT NULL REFERENCES commerce.product_variants(id) ON DELETE CASCADE,
    batch_code VARCHAR(64),
    secret_payload TEXT NOT NULL,
    public_hint VARCHAR(128),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    status commerce.stock_status NOT NULL DEFAULT 'available',
    order_item_id UUID,
    sold_to_tenant_id UUID REFERENCES public.tenants(id) ON DELETE SET NULL,
    reserved_until TIMESTAMPTZ,
    sold_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_commerce_stock_variant_secret UNIQUE (variant_id, secret_payload)
);

COMMENT ON TABLE commerce.stock_items IS '[Plugin: commerce] Isolated secret stock lines (uid|pass|2fa, license keys, proxies) locked with FOR UPDATE SKIP LOCKED';

CREATE INDEX IF NOT EXISTS idx_commerce_stock_variant_status
    ON commerce.stock_items (variant_id, status, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_commerce_stock_reserved_until
    ON commerce.stock_items (reserved_until) WHERE status = 'reserved';

-- 3.5. Orders (Tenant & Public Guest Checkout)
CREATE TABLE IF NOT EXISTS commerce.orders (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    order_code VARCHAR(32) NOT NULL UNIQUE,
    buyer_tenant_id UUID REFERENCES public.tenants(id) ON DELETE SET NULL,
    buyer_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    buyer_email VARCHAR(255),
    guest_claim_token_hash VARCHAR(64),
    payment_method VARCHAR(32) NOT NULL CHECK (payment_method IN ('internal_wallet', 'bank_transfer', 'e_wallet', 'card_intl', 'crypto')),
    payment_intent_id UUID REFERENCES billing.payment_intents(id) ON DELETE SET NULL,
    subtotal_credits BIGINT NOT NULL CHECK (subtotal_credits >= 0),
    discount_credits BIGINT NOT NULL DEFAULT 0 CHECK (discount_credits >= 0),
    total_credits BIGINT NOT NULL CHECK (total_credits >= 0),
    status commerce.order_status NOT NULL DEFAULT 'pending_payment',
    notes TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    paid_at TIMESTAMPTZ,
    fulfilled_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE commerce.orders IS '[Plugin: commerce] Digital store orders supporting instant Xu wallet checkout, external gateways, and Guest claim tokens';

CREATE INDEX IF NOT EXISTS idx_commerce_orders_tenant_created
    ON commerce.orders (buyer_tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_commerce_orders_payment_intent
    ON commerce.orders (payment_intent_id) WHERE payment_intent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_commerce_orders_status
    ON commerce.orders (status, created_at DESC);

-- 3.6. Order Items
CREATE TABLE IF NOT EXISTS commerce.order_items (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES commerce.orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES commerce.products(id) ON DELETE RESTRICT,
    variant_id UUID NOT NULL REFERENCES commerce.product_variants(id) ON DELETE RESTRICT,
    product_name VARCHAR(255) NOT NULL,
    variant_name VARCHAR(128) NOT NULL,
    product_type commerce.product_type NOT NULL,
    quantity INT NOT NULL CHECK (quantity >= 1),
    unit_price_credits BIGINT NOT NULL CHECK (unit_price_credits >= 0),
    total_price_credits BIGINT NOT NULL CHECK (total_price_credits >= 0),
    fulfilled_quantity INT NOT NULL DEFAULT 0 CHECK (fulfilled_quantity >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE commerce.order_items IS '[Plugin: commerce] Line items within a digital order';

CREATE INDEX IF NOT EXISTS idx_commerce_order_items_order
    ON commerce.order_items (order_id);

-- 3.7. Order Deliveries (Fulfilled Digital Deliverables)
CREATE TABLE IF NOT EXISTS commerce.order_deliveries (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES commerce.orders(id) ON DELETE CASCADE,
    order_item_id UUID NOT NULL REFERENCES commerce.order_items(id) ON DELETE CASCADE,
    buyer_tenant_id UUID REFERENCES public.tenants(id) ON DELETE SET NULL,
    delivery_type commerce.product_type NOT NULL,
    stock_item_id UUID REFERENCES commerce.stock_items(id) ON DELETE SET NULL,
    delivered_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    download_count INT NOT NULL DEFAULT 0 CHECK (download_count >= 0),
    max_downloads INT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE commerce.order_deliveries IS '[Plugin: commerce] Delivered digital goods (serials, provisioned resource IDs, file download grants, wallet top-ups)';

CREATE INDEX IF NOT EXISTS idx_commerce_deliveries_order
    ON commerce.order_deliveries (order_id);
CREATE INDEX IF NOT EXISTS idx_commerce_deliveries_tenant
    ON commerce.order_deliveries (buyer_tenant_id, created_at DESC);

-- 3.8. Seed Default Store Categories & Sample Digital Products
INSERT INTO commerce.categories (slug, name, description, icon, sort_order, is_active)
VALUES
    ('accounts-keys', 'Tai khoan & License Key', 'Tai khoan so, phoi MMO (uid|pass|2fa) va ma kich hoat phan mem giao tuc thi', 'lucide:key-round', 1, TRUE),
    ('resources', 'Tai nguyen Tuquet', 'Proxy dan cu/datacenter, kich ban Automa mau va goi nang cap he sinh thai', 'lucide:cpu', 2, TRUE),
    ('digital-files', 'Tep so & Cong cu', 'Bo cai dat, tai lieu ky thuat va du lieu tai xuong', 'lucide:file-down', 3, TRUE),
    ('wallet-topup', 'Nap Xu Tra Truoc', 'Goi nap Xu tich luy vao vi Tenant kem uu dai tang them Xu', 'lucide:coins', 4, TRUE)
ON CONFLICT (slug) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    sort_order = EXCLUDED.sort_order;

-- Seed 4 canonical sample digital products (one per product_type)
DO $$
DECLARE
    v_cat_accounts UUID;
    v_cat_specter UUID;
    v_cat_files UUID;
    v_cat_topup UUID;
    v_prod_serial UUID;
    v_prod_resource UUID;
    v_prod_file UUID;
    v_prod_topup UUID;
BEGIN
    SELECT id INTO v_cat_accounts FROM commerce.categories WHERE slug = 'accounts-keys';
    SELECT id INTO v_cat_specter FROM commerce.categories WHERE slug = 'resources';
    SELECT id INTO v_cat_files FROM commerce.categories WHERE slug = 'digital-files';
    SELECT id INTO v_cat_topup FROM commerce.categories WHERE slug = 'wallet-topup';

    -- 1. Serial Stock Product
    INSERT INTO commerce.products (category_id, slug, name, short_description, product_type, visibility, is_active, tags, fulfillment_config, sort_order)
    VALUES (
        v_cat_accounts,
        'via-account-2fa-verified',
        'Tai khoan Via Xac Minh 2FA (Giao Tuc Thi)',
        'Phoi tai khoan dinh dang uid|pass|2fa|email kem bao hanh 24h',
        'serial_stock',
        'public',
        TRUE,
        ARRAY['2fa', 'instant', 'mmo'],
        '{"format": "uid|pass|2fa|email", "warranty_hours": 24}'::jsonb,
        1
    )
    ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name
    RETURNING id INTO v_prod_serial;

    INSERT INTO commerce.product_variants (product_id, sku, name, price_credits, compare_at_credits, stock_mode, min_qty, max_qty, sort_order)
    VALUES (v_prod_serial, 'VIA-2FA-STD', 'Goi Tieu Chuan (1 Tai khoan)', 50, 65, 'serialized', 1, 50, 1)
    ON CONFLICT (sku) DO UPDATE SET price_credits = EXCLUDED.price_credits;

    -- 2. Ecosystem Resource Product
    INSERT INTO commerce.products (category_id, slug, name, short_description, product_type, visibility, is_active, tags, fulfillment_config, sort_order)
    VALUES (
        v_cat_specter,
        'residential-proxy-pack',
        'Proxy Dan Cu Tinh (Cap Thang Vao Workspace)',
        'Tu dong khoi tao va gan Proxy truc tiep vao bang workers.proxies cua Tenant',
        'resource',
        'tenant_only',
        TRUE,
        ARRAY['proxy', 'tuquet', 'workers'],
        '{"resource_subtype": "proxy_pool"}'::jsonb,
        2
    )
    ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name
    RETURNING id INTO v_prod_resource;

    INSERT INTO commerce.product_variants (product_id, sku, name, price_credits, compare_at_credits, stock_mode, min_qty, max_qty, fulfillment_payload, sort_order)
    VALUES (
        v_prod_resource,
        'PROXY-VN-ISP-30D',
        'Proxy VN ISP Tinh (30 Ngay)',
        120,
        150,
        'serialized',
        1,
        20,
        '{"resource_subtype": "proxy_pool", "protocol": "socks5", "country_code": "VN", "is_residential": true}'::jsonb,
        1
    )
    ON CONFLICT (sku) DO UPDATE SET price_credits = EXCLUDED.price_credits;

    -- 3. Digital File Product
    INSERT INTO commerce.products (category_id, slug, name, short_description, product_type, visibility, is_active, tags, fulfillment_config, sort_order)
    VALUES (
        v_cat_files,
        'stealth-fingerprints-pack',
        'Bo Du Lieu Canvas & WebGL Fingerprint Cao Cap',
        'Tap tin ZIP chua 500 mau thong so phan cung thuc te cho trinh duyet antidetect',
        'digital_file',
        'public',
        TRUE,
        ARRAY['dataset', 'fingerprint', 'zip'],
        '{"delivery": "signed_download"}'::jsonb,
        3
    )
    ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name
    RETURNING id INTO v_prod_file;

    INSERT INTO commerce.product_variants (product_id, sku, name, price_credits, compare_at_credits, stock_mode, min_qty, max_qty, fulfillment_payload, sort_order)
    VALUES (
        v_prod_file,
        'FP-PACK-500-ZIP',
        'Ban Day Du 500 Profiles (.zip)',
        200,
        250,
        'unlimited',
        1,
        1,
        '{"bucket_name": "tenant-assets", "file_path": "store/fingerprints-500.zip", "max_downloads": 5, "expire_hours": 168}'::jsonb,
        1
    )
    ON CONFLICT (sku) DO UPDATE SET price_credits = EXCLUDED.price_credits;

    -- 4. Prepaid Wallet Credit Pack
    INSERT INTO commerce.products (category_id, slug, name, short_description, product_type, visibility, is_active, tags, fulfillment_config, sort_order)
    VALUES (
        v_cat_topup,
        'prepaid-xu-credit-bundle',
        'Goi Nap Xu Tra Truoc (Tang Them Xu Thuong)',
        'Nap Xu vao vi Tenant qua VietQR / MoMo / Stripe / USDT de thanh toan tuc thi',
        'wallet_credit',
        'tenant_only',
        TRUE,
        ARRAY['xu', 'topup', 'bonus'],
        '{"instant_credit": true}'::jsonb,
        4
    )
    ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name
    RETURNING id INTO v_prod_topup;

    INSERT INTO commerce.product_variants (product_id, sku, name, price_credits, compare_at_credits, stock_mode, min_qty, max_qty, fulfillment_payload, sort_order)
    VALUES (
        v_prod_topup,
        'XU-PACK-500-BONUS50',
        'Goi 500 Xu (+50 Xu Thuong = 550 Xu)',
        500,
        550,
        'unlimited',
        1,
        10,
        '{"credit_amount": 500, "bonus_credits": 50}'::jsonb,
        1
    )
    ON CONFLICT (sku) DO UPDATE SET price_credits = EXCLUDED.price_credits;
END $$;

-- 4. Atomic Stock Inventory & Order Fulfillment Functions (SECURITY DEFINER)

-- 4.1. Release Expired Stock Reservations (> 15m)
CREATE OR REPLACE FUNCTION commerce.release_expired_reservations(
    _variant_id UUID DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_released_count INT := 0;
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
BEGIN
    WITH expired_rows AS (
        UPDATE commerce.stock_items si
        SET status = 'available',
            order_item_id = NULL,
            reserved_until = NULL,
            updated_at = v_now
        WHERE si.status = 'reserved'
          AND si.reserved_until IS NOT NULL
          AND si.reserved_until < v_now
          AND (_variant_id IS NULL OR si.variant_id = _variant_id)
        RETURNING si.variant_id
    ),
    affected_variants AS (
        SELECT DISTINCT variant_id FROM expired_rows
    )
    UPDATE commerce.product_variants pv
    SET available_stock = (
            SELECT COUNT(*)::int
            FROM commerce.stock_items s
            WHERE s.variant_id = pv.id AND s.status = 'available'
        ),
        updated_at = v_now
    WHERE pv.id IN (SELECT variant_id FROM affected_variants)
      AND pv.stock_mode = 'serialized';

    GET DIAGNOSTICS v_released_count = ROW_COUNT;
    RETURN v_released_count;
END;
$$;

-- 4.2. Bulk Stock Import with Deduplication (Platform Admin Only)
CREATE OR REPLACE FUNCTION commerce.import_stock_batch(
    _variant_id UUID,
    _lines TEXT[],
    _batch_code VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_line TEXT;
    v_trimmed TEXT;
    v_hint TEXT;
    v_input_count INT := 0;
    v_imported_count INT := 0;
    v_inserted INT;
    v_available INT := 0;
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
BEGIN
    IF current_setting('request.jwt.claim.role', true) IS DISTINCT FROM 'service_role'
       AND current_user NOT IN ('postgres', 'supabase_admin')
       AND NOT public.is_platform_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only platform admin can import stock batches'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM commerce.product_variants WHERE id = _variant_id) THEN
        RAISE EXCEPTION 'Product variant % does not exist', _variant_id
            USING ERRCODE = '22023';
    END IF;

    IF _lines IS NOT NULL THEN
        FOREACH v_line IN ARRAY _lines LOOP
            v_trimmed := BTRIM(COALESCE(v_line, ''));
            IF v_trimmed <> '' THEN
                v_input_count := v_input_count + 1;
                v_hint := CASE
                    WHEN LENGTH(v_trimmed) > 8 THEN SUBSTR(v_trimmed, 1, 6) || '***'
                    ELSE '***'
                END;

                INSERT INTO commerce.stock_items (
                    variant_id,
                    batch_code,
                    secret_payload,
                    public_hint,
                    status,
                    created_at,
                    updated_at
                )
                VALUES (
                    _variant_id,
                    COALESCE(_batch_code, 'BATCH-' || TO_CHAR(v_now, 'YYMMDD')),
                    v_trimmed,
                    v_hint,
                    'available',
                    v_now,
                    v_now
                )
                ON CONFLICT (variant_id, secret_payload) DO NOTHING;

                GET DIAGNOSTICS v_inserted = ROW_COUNT;
                v_imported_count := v_imported_count + v_inserted;
            END IF;
        END LOOP;
    END IF;

    SELECT COUNT(*)::int INTO v_available
    FROM commerce.stock_items
    WHERE variant_id = _variant_id AND status = 'available';

    UPDATE commerce.product_variants
    SET stock_mode = 'serialized',
        available_stock = v_available,
        updated_at = v_now
    WHERE id = _variant_id;

    RETURN jsonb_build_object(
        'variant_id', _variant_id,
        'input_count', v_input_count,
        'imported_count', v_imported_count,
        'skipped_duplicates', GREATEST(v_input_count - v_imported_count, 0),
        'available_stock', v_available
    );
END;
$$;

-- 4.3. Atomic Auto-Fulfillment Dispatcher (serial_stock, resource, digital_file, wallet_credit)
CREATE OR REPLACE FUNCTION commerce.fulfill_order(
    _order_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_order commerce.orders%ROWTYPE;
    v_item commerce.order_items%ROWTYPE;
    v_variant commerce.product_variants%ROWTYPE;
    v_stock commerce.stock_items%ROWTYPE;
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_needed INT;
    v_subtype TEXT;
    v_parts TEXT[];
    v_proxy_id UUID;
    v_workflow_id UUID;
    v_template_wf automation.workflows%ROWTYPE;
    v_credit_amount BIGINT;
    v_bonus_credits BIGINT;
    v_total_credited BIGINT;
    v_new_balance BIGINT;
    v_duration_days INT;
    v_plan_id TEXT;
    v_deliveries JSONB := '[]'::jsonb;
    i INT;
BEGIN
    SELECT * INTO v_order
    FROM commerce.orders
    WHERE id = _order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('fulfilled', false, 'reason', 'order_not_found');
    END IF;

    -- Idempotency guard
    IF v_order.status = 'completed' THEN
        SELECT COALESCE(jsonb_agg(to_jsonb(od) ORDER BY od.created_at ASC), '[]'::jsonb)
        INTO v_deliveries
        FROM commerce.order_deliveries od
        WHERE od.order_id = v_order.id;

        RETURN jsonb_build_object(
            'fulfilled', true,
            'idempotent', true,
            'order_id', v_order.id,
            'order_code', v_order.order_code,
            'deliveries', v_deliveries
        );
    END IF;

    UPDATE commerce.orders
    SET status = 'fulfilling',
        paid_at = COALESCE(paid_at, v_now),
        updated_at = v_now
    WHERE id = v_order.id;

    FOR v_item IN
        SELECT * FROM commerce.order_items
        WHERE order_id = v_order.id
        ORDER BY created_at ASC
        FOR UPDATE
    LOOP
        v_needed := v_item.quantity - v_item.fulfilled_quantity;
        IF v_needed <= 0 THEN
            CONTINUE;
        END IF;

        SELECT * INTO v_variant
        FROM commerce.product_variants
        WHERE id = v_item.variant_id
        FOR UPDATE;

        -- CASE 1: Serialized Text / Account / License Key Stock
        IF v_item.product_type = 'serial_stock' THEN
            FOR v_stock IN
                SELECT * FROM commerce.stock_items
                WHERE variant_id = v_item.variant_id
                  AND (
                      (status = 'reserved' AND order_item_id = v_item.id)
                      OR status = 'available'
                  )
                ORDER BY
                    CASE WHEN status = 'reserved' AND order_item_id = v_item.id THEN 0 ELSE 1 END,
                    created_at ASC
                LIMIT v_needed
                FOR UPDATE SKIP LOCKED
            LOOP
                UPDATE commerce.stock_items
                SET status = 'sold',
                    order_item_id = v_item.id,
                    sold_to_tenant_id = v_order.buyer_tenant_id,
                    reserved_until = NULL,
                    sold_at = v_now,
                    updated_at = v_now
                WHERE id = v_stock.id;

                INSERT INTO commerce.order_deliveries (
                    order_id,
                    order_item_id,
                    buyer_tenant_id,
                    delivery_type,
                    stock_item_id,
                    delivered_payload,
                    created_at
                )
                VALUES (
                    v_order.id,
                    v_item.id,
                    v_order.buyer_tenant_id,
                    'serial_stock',
                    v_stock.id,
                    jsonb_build_object(
                        'serial', v_stock.secret_payload,
                        'batch_code', v_stock.batch_code,
                        'sku', v_variant.sku
                    ),
                    v_now
                );

                v_item.fulfilled_quantity := v_item.fulfilled_quantity + 1;
            END LOOP;

            IF v_item.fulfilled_quantity < v_item.quantity THEN
                RAISE EXCEPTION 'Insufficient stock to fulfill order item % (needed %, fulfilled %)',
                    v_item.id, v_item.quantity, v_item.fulfilled_quantity
                    USING ERRCODE = 'P0001';
            END IF;

        -- CASE 2: Ecosystem Resource (Proxy Pool, Automa Workflow, Plan Upgrade)
        ELSIF v_item.product_type = 'resource' THEN
            IF v_order.buyer_tenant_id IS NULL THEN
                RAISE EXCEPTION 'ecosystem resource requires buyer_tenant_id'
                    USING ERRCODE = '22023';
            END IF;

            v_subtype := COALESCE(v_variant.fulfillment_payload->>'resource_subtype', 'proxy_pool');

            IF v_subtype = 'proxy_pool' THEN
                FOR v_stock IN
                    SELECT * FROM commerce.stock_items
                    WHERE variant_id = v_item.variant_id
                      AND (
                          (status = 'reserved' AND order_item_id = v_item.id)
                          OR status = 'available'
                      )
                    ORDER BY
                        CASE WHEN status = 'reserved' AND order_item_id = v_item.id THEN 0 ELSE 1 END,
                        created_at ASC
                    LIMIT v_needed
                    FOR UPDATE SKIP LOCKED
                LOOP
                    -- Parse host:port:username:password
                    v_parts := string_to_array(v_stock.secret_payload, ':');
                    INSERT INTO workers.proxies (
                        tenant_id,
                        host,
                        port,
                        protocol,
                        username,
                        password_hash,
                        country_code,
                        status,
                        is_residential,
                        tags
                    )
                    VALUES (
                        v_order.buyer_tenant_id,
                        COALESCE(v_parts[1], '198.51.100.10'),
                        COALESCE(NULLIF(regexp_replace(COALESCE(v_parts[2], '1080'), '\D', '', 'g'), '')::int, 1080),
                        COALESCE(v_variant.fulfillment_payload->>'protocol', 'socks5'),
                        v_parts[3],
                        v_parts[4],
                        COALESCE(v_variant.fulfillment_payload->>'country_code', 'VN'),
                        'active',
                        COALESCE((v_variant.fulfillment_payload->>'is_residential')::boolean, true),
                        ARRAY['commerce', v_order.order_code]
                    )
                    ON CONFLICT (tenant_id, host, port, protocol, username) DO UPDATE
                        SET status = 'active', updated_at = v_now
                    RETURNING id INTO v_proxy_id;

                    UPDATE commerce.stock_items
                    SET status = 'sold',
                        order_item_id = v_item.id,
                        sold_to_tenant_id = v_order.buyer_tenant_id,
                        reserved_until = NULL,
                        sold_at = v_now,
                        updated_at = v_now
                    WHERE id = v_stock.id;

                    INSERT INTO commerce.order_deliveries (
                        order_id,
                        order_item_id,
                        buyer_tenant_id,
                        delivery_type,
                        stock_item_id,
                        delivered_payload,
                        created_at
                    )
                    VALUES (
                        v_order.id,
                        v_item.id,
                        v_order.buyer_tenant_id,
                        'resource',
                        v_stock.id,
                        jsonb_build_object(
                            'resource_subtype', 'proxy_pool',
                            'proxy_id', v_proxy_id,
                            'endpoint', v_stock.secret_payload
                        ),
                        v_now
                    );

                    v_item.fulfilled_quantity := v_item.fulfilled_quantity + 1;
                END LOOP;

            ELSIF v_subtype = 'workflow_package' THEN
                FOR i IN 1..v_needed LOOP
                    INSERT INTO automation.packages (
                        tenant_id,
                        name,
                        description,
                        icon,
                        version,
                        is_external,
                        status,
                        settings,
                        inputs,
                        outputs,
                        variables,
                        data,
                        created_by
                    )
                    SELECT 
                        v_order.buyer_tenant_id,
                        name,
                        description,
                        icon,
                        version,
                        TRUE,
                        'published',
                        settings,
                        inputs,
                        outputs,
                        variables,
                        data,
                        v_order.buyer_user_id
                    FROM automation.packages
                    WHERE id = public.safe_cast_uuid(v_variant.fulfillment_payload->>'template_package_id')
                    RETURNING id INTO v_workflow_id;

                    INSERT INTO commerce.order_deliveries (
                        order_id,
                        order_item_id,
                        buyer_tenant_id,
                        delivery_type,
                        delivered_payload,
                        created_at
                    )
                    VALUES (
                        v_order.id,
                        v_item.id,
                        v_order.buyer_tenant_id,
                        'resource',
                        jsonb_build_object(
                            'resource_subtype', 'workflow_package',
                            'package_id', v_workflow_id,
                            'package_name', v_item.product_name
                        ),
                        v_now
                    );

                    v_item.fulfilled_quantity := v_item.fulfilled_quantity + 1;
                END LOOP;

            ELSIF v_subtype = 'workflow' THEN
                FOR i IN 1..v_needed LOOP
                    SELECT * INTO v_template_wf
                    FROM automation.workflows
                    WHERE id = public.safe_cast_uuid(v_variant.fulfillment_payload->>'template_workflow_id');

                    INSERT INTO automation.workflows (
                        tenant_id,
                        name,
                        description,
                        version,
                        status,
                        graph_data,
                        settings,
                        created_by
                    )
                    VALUES (
                        v_order.buyer_tenant_id,
                        COALESCE(v_template_wf.name, v_item.product_name),
                        COALESCE(v_template_wf.description, 'Provisioned from Digital Store (' || v_order.order_code || ')'),
                        COALESCE(v_template_wf.version, '1.0.0'),
                        'published',
                        COALESCE(v_template_wf.graph_data, COALESCE(v_variant.fulfillment_payload->'graph_data', '{"nodes": [], "edges": []}'::jsonb)),
                        COALESCE(v_template_wf.settings, '{}'::jsonb),
                        v_order.buyer_user_id
                    )
                    RETURNING id INTO v_workflow_id;

                    INSERT INTO commerce.order_deliveries (
                        order_id,
                        order_item_id,
                        buyer_tenant_id,
                        delivery_type,
                        delivered_payload,
                        created_at
                    )
                    VALUES (
                        v_order.id,
                        v_item.id,
                        v_order.buyer_tenant_id,
                        'resource',
                        jsonb_build_object(
                            'resource_subtype', 'workflow',
                            'workflow_id', v_workflow_id,
                            'workflow_name', COALESCE(v_template_wf.name, v_item.product_name)
                        ),
                        v_now
                    );

                    v_item.fulfilled_quantity := v_item.fulfilled_quantity + 1;
                END LOOP;

            ELSIF v_subtype = 'plan_upgrade' THEN
                v_plan_id := COALESCE(v_variant.fulfillment_payload->>'plan_id', 'pro');
                v_duration_days := COALESCE((v_variant.fulfillment_payload->>'duration_days')::int, 30) * v_needed;

                INSERT INTO billing.subscriptions (
                    tenant_id,
                    plan_id,
                    status,
                    current_period_start,
                    current_period_end,
                    updated_at
                )
                VALUES (
                    v_order.buyer_tenant_id,
                    v_plan_id,
                    'active',
                    v_now,
                    v_now + (v_duration_days || ' days')::interval,
                    v_now
                )
                ON CONFLICT (tenant_id) DO UPDATE SET
                    plan_id = EXCLUDED.plan_id,
                    status = 'active',
                    current_period_end = GREATEST(COALESCE(billing.subscriptions.current_period_end, v_now), v_now) + (v_duration_days || ' days')::interval,
                    updated_at = v_now;

                INSERT INTO commerce.order_deliveries (
                    order_id,
                    order_item_id,
                    buyer_tenant_id,
                    delivery_type,
                    delivered_payload,
                    created_at
                )
                VALUES (
                    v_order.id,
                    v_item.id,
                    v_order.buyer_tenant_id,
                    'resource',
                    jsonb_build_object(
                        'resource_subtype', 'plan_upgrade',
                        'plan_id', v_plan_id,
                        'added_days', v_duration_days
                    ),
                    v_now
                );

                v_item.fulfilled_quantity := v_item.quantity;
            END IF;

        -- CASE 3: Digital File Entitlement
        ELSIF v_item.product_type = 'digital_file' THEN
            INSERT INTO commerce.order_deliveries (
                order_id,
                order_item_id,
                buyer_tenant_id,
                delivery_type,
                delivered_payload,
                max_downloads,
                expires_at,
                created_at
            )
            VALUES (
                v_order.id,
                v_item.id,
                v_order.buyer_tenant_id,
                'digital_file',
                jsonb_build_object(
                    'asset_id', v_variant.fulfillment_payload->>'asset_id',
                    'bucket_name', COALESCE(v_variant.fulfillment_payload->>'bucket_name', 'tenant-assets'),
                    'file_path', v_variant.fulfillment_payload->>'file_path',
                    'sku', v_variant.sku
                ),
                COALESCE((v_variant.fulfillment_payload->>'max_downloads')::int, 5) * v_needed,
                v_now + (COALESCE((v_variant.fulfillment_payload->>'expire_hours')::int, 168) || ' hours')::interval,
                v_now
            );

            v_item.fulfilled_quantity := v_item.quantity;

        -- CASE 4: Prepaid Wallet Credit Top-Up
        ELSIF v_item.product_type = 'wallet_credit' THEN
            IF v_order.buyer_tenant_id IS NULL THEN
                RAISE EXCEPTION 'Wallet credit top-up requires buyer_tenant_id'
                    USING ERRCODE = '22023';
            END IF;

            v_credit_amount := COALESCE((v_variant.fulfillment_payload->>'credit_amount')::bigint, v_variant.price_credits);
            v_bonus_credits := COALESCE((v_variant.fulfillment_payload->>'bonus_credits')::bigint, 0);
            v_total_credited := (v_credit_amount + v_bonus_credits) * v_needed;

            v_new_balance := billing.credit_tenant_wallet(
                v_order.buyer_tenant_id,
                v_total_credited,
                'topup',
                'commerce_order',
                v_order.id::text,
                'Nap goi ' || v_item.variant_name || ' x' || v_needed || ' (' || v_order.order_code || ')'
            );

            INSERT INTO commerce.order_deliveries (
                order_id,
                order_item_id,
                buyer_tenant_id,
                delivery_type,
                delivered_payload,
                created_at
            )
            VALUES (
                v_order.id,
                v_item.id,
                v_order.buyer_tenant_id,
                'wallet_credit',
                jsonb_build_object(
                    'credited_xu', v_total_credited,
                    'base_xu', v_credit_amount * v_needed,
                    'bonus_xu', v_bonus_credits * v_needed,
                    'balance_after_credits', v_new_balance
                ),
                v_now
            );

            v_item.fulfilled_quantity := v_item.quantity;
        END IF;

        -- Update order_item fulfilled_quantity and variant counters
        UPDATE commerce.order_items
        SET fulfilled_quantity = v_item.fulfilled_quantity
        WHERE id = v_item.id;

        UPDATE commerce.product_variants
        SET sold_count = sold_count + v_needed,
            available_stock = CASE
                WHEN stock_mode = 'serialized' THEN (
                    SELECT COUNT(*)::int
                    FROM commerce.stock_items s
                    WHERE s.variant_id = v_variant.id AND s.status = 'available'
                )
                WHEN stock_mode = 'finite_counter' THEN GREATEST(available_stock - v_needed, 0)
                ELSE available_stock
            END,
            updated_at = v_now
        WHERE id = v_variant.id;
    END LOOP;

    UPDATE commerce.orders
    SET status = 'completed',
        fulfilled_at = v_now,
        updated_at = v_now
    WHERE id = v_order.id;

    SELECT COALESCE(jsonb_agg(to_jsonb(od) ORDER BY od.created_at ASC), '[]'::jsonb)
    INTO v_deliveries
    FROM commerce.order_deliveries od
    WHERE od.order_id = v_order.id;

    RETURN jsonb_build_object(
        'fulfilled', true,
        'idempotent', false,
        'order_id', v_order.id,
        'order_code', v_order.order_code,
        'status', 'completed',
        'deliveries', v_deliveries
    );
END;
$$;

-- 4.4. Atomic Checkout Order Creation (Tenant & Guest Checkout + FOR UPDATE SKIP LOCKED Reservation)
CREATE OR REPLACE FUNCTION commerce.create_checkout_order(
    _items JSONB,
    _payment_method VARCHAR,
    _buyer_tenant_id UUID DEFAULT NULL,
    _gateway_code VARCHAR DEFAULT NULL,
    _buyer_email VARCHAR DEFAULT NULL,
    _idempotency_key VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_order_id UUID;
    v_order_code VARCHAR(32);
    v_raw_claim_token TEXT := NULL;
    v_claim_token_hash VARCHAR(64) := NULL;
    v_elem JSONB;
    v_variant_id UUID;
    v_qty INT;
    v_variant commerce.product_variants%ROWTYPE;
    v_product commerce.products%ROWTYPE;
    v_order_item_id UUID;
    v_locked_stock_ids UUID[];
    v_subtotal_credits BIGINT := 0;
    v_total_credits BIGINT := 0;
    v_gateway_id TEXT;
    v_intent_json JSONB;
    v_intent_id UUID;
    v_fulfill_json JSONB := NULL;
    v_final_order commerce.orders%ROWTYPE;
BEGIN
    IF _items IS NULL OR jsonb_typeof(_items) <> 'array' OR jsonb_array_length(_items) = 0 THEN
        RAISE EXCEPTION 'Order items array cannot be empty'
            USING ERRCODE = '22023';
    END IF;

    -- Validate caller authorization
    IF _buyer_tenant_id IS NOT NULL THEN
        IF current_setting('request.jwt.claim.role', true) IS DISTINCT FROM 'service_role'
           AND current_user NOT IN ('postgres', 'supabase_admin')
           AND NOT public.is_platform_admin()
           AND NOT public.is_tenant_member(_buyer_tenant_id) THEN
            RAISE EXCEPTION 'Unauthorized: Caller is not a member of buyer_tenant_id %', _buyer_tenant_id
                USING ERRCODE = '42501';
        END IF;
    ELSE
        -- Guest Checkout rules
        IF _buyer_email IS NULL OR BTRIM(_buyer_email) = '' THEN
            RAISE EXCEPTION 'Guest checkout requires a valid _buyer_email'
                USING ERRCODE = '22023';
        END IF;
        IF _payment_method = 'internal_wallet' THEN
            RAISE EXCEPTION 'Guest checkout cannot use internal_wallet payment method'
                USING ERRCODE = '22023';
        END IF;

        v_raw_claim_token := 'CLM_' || UPPER(SUBSTR(MD5(extensions.gen_random_uuid()::text || clock_timestamp()::text), 1, 24));
        v_claim_token_hash := pg_catalog.encode(extensions.digest(v_raw_claim_token, 'sha256'), 'hex');
    END IF;

    -- Release any expired 15m reservations before locking stock
    PERFORM commerce.release_expired_reservations(NULL);

    -- Generate unique human-friendly order_code: ORD-YYMMDD-XXXXXX
    LOOP
        v_order_code := 'ORD-' || TO_CHAR(v_now, 'YYMMDD') || '-' || UPPER(SUBSTR(MD5(extensions.gen_random_uuid()::text || clock_timestamp()::text), 1, 6));
        EXIT WHEN NOT EXISTS (SELECT 1 FROM commerce.orders WHERE order_code = v_order_code);
    END LOOP;

    -- Create initial order header
    INSERT INTO commerce.orders (
        order_code,
        buyer_tenant_id,
        buyer_user_id,
        buyer_email,
        guest_claim_token_hash,
        payment_method,
        subtotal_credits,
        discount_credits,
        total_credits,
        status,
        metadata,
        created_at,
        updated_at
    )
    VALUES (
        v_order_code,
        _buyer_tenant_id,
        auth.uid(),
        _buyer_email,
        v_claim_token_hash,
        _payment_method,
        0,
        0,
        0,
        'pending_payment',
        CASE
            WHEN _idempotency_key IS NOT NULL THEN jsonb_build_object('idempotency_key', _idempotency_key)
            ELSE '{}'::jsonb
        END,
        v_now,
        v_now
    )
    RETURNING id INTO v_order_id;

    -- Process each requested item and lock inventory
    FOR v_elem IN SELECT * FROM jsonb_array_elements(_items) LOOP
        v_variant_id := public.safe_cast_uuid(v_elem->>'variant_id');
        v_qty := COALESCE((v_elem->>'quantity')::int, 1);

        IF v_variant_id IS NULL OR v_qty < 1 THEN
            RAISE EXCEPTION 'Invalid variant_id or quantity in checkout items'
                USING ERRCODE = '22023';
        END IF;

        SELECT * INTO v_variant
        FROM commerce.product_variants
        WHERE id = v_variant_id AND is_active = TRUE
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product variant % is not found or inactive', v_variant_id
                USING ERRCODE = '22023';
        END IF;

        IF v_qty < v_variant.min_qty OR v_qty > v_variant.max_qty THEN
            RAISE EXCEPTION 'Quantity % for SKU % violates min/max bounds (%..%)',
                v_qty, v_variant.sku, v_variant.min_qty, v_variant.max_qty
                USING ERRCODE = '22023';
        END IF;

        SELECT * INTO v_product
        FROM commerce.products
        WHERE id = v_variant.product_id AND is_active = TRUE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product for variant % is not active', v_variant.sku
                USING ERRCODE = '22023';
        END IF;

        -- Guest checkout restriction: only public serial_stock or digital_file allowed
        IF _buyer_tenant_id IS NULL THEN
            IF v_product.visibility <> 'public' OR v_product.product_type NOT IN ('serial_stock', 'digital_file') THEN
                RAISE EXCEPTION 'Product % requires an authenticated Tenant workspace', v_product.slug
                    USING ERRCODE = '22023';
            END IF;
        END IF;

        -- Prevent buying wallet_credit with internal_wallet
        IF v_product.product_type = 'wallet_credit' AND _payment_method = 'internal_wallet' THEN
            RAISE EXCEPTION 'Cannot purchase wallet_credit top-up pack using internal_wallet'
                USING ERRCODE = '22023';
        END IF;

        INSERT INTO commerce.order_items (
            order_id,
            product_id,
            variant_id,
            product_name,
            variant_name,
            product_type,
            quantity,
            unit_price_credits,
            total_price_credits,
            fulfilled_quantity,
            created_at
        )
        VALUES (
            v_order_id,
            v_product.id,
            v_variant.id,
            v_product.name,
            v_variant.name,
            v_product.product_type,
            v_qty,
            v_variant.price_credits,
            v_variant.price_credits * v_qty,
            0,
            v_now
        )
        RETURNING id INTO v_order_item_id;

        -- Lock and reserve serialized stock items (FOR UPDATE SKIP LOCKED)
        IF v_variant.stock_mode = 'serialized' THEN
            SELECT ARRAY(
                SELECT si.id
                FROM commerce.stock_items si
                WHERE si.variant_id = v_variant.id
                  AND si.status = 'available'
                ORDER BY si.created_at ASC
                LIMIT v_qty
                FOR UPDATE SKIP LOCKED
            ) INTO v_locked_stock_ids;

            IF COALESCE(array_length(v_locked_stock_ids, 1), 0) < v_qty THEN
                RAISE EXCEPTION 'Out of stock for SKU %: requested %, available %',
                    v_variant.sku, v_qty, COALESCE(array_length(v_locked_stock_ids, 1), 0)
                    USING ERRCODE = 'P0001';
            END IF;

            UPDATE commerce.stock_items
            SET status = 'reserved',
                order_item_id = v_order_item_id,
                reserved_until = v_now + INTERVAL '15 minutes',
                updated_at = v_now
            WHERE id = ANY(v_locked_stock_ids);

            UPDATE commerce.product_variants
            SET available_stock = GREATEST(available_stock - v_qty, 0),
                updated_at = v_now
            WHERE id = v_variant.id;

        ELSIF v_variant.stock_mode = 'finite_counter' THEN
            IF v_variant.available_stock < v_qty THEN
                RAISE EXCEPTION 'Out of stock for SKU %: requested %, available %',
                    v_variant.sku, v_qty, v_variant.available_stock
                    USING ERRCODE = 'P0001';
            END IF;
        END IF;

        v_subtotal_credits := v_subtotal_credits + (v_variant.price_credits * v_qty);
    END LOOP;

    v_total_credits := v_subtotal_credits;

    -- Resolve gateway ID for billing.create_payment_intent
    IF _payment_method = 'internal_wallet' THEN
        v_gateway_id := 'internal_wallet';
    ELSIF _gateway_code IS NOT NULL AND BTRIM(_gateway_code) <> '' THEN
        v_gateway_id := BTRIM(_gateway_code);
    ELSE
        SELECT pg.id INTO v_gateway_id
        FROM billing.payment_gateways pg
        WHERE pg.channel::text = _payment_method AND pg.is_active = TRUE
        ORDER BY pg.sort_order ASC
        LIMIT 1;
    END IF;

    IF v_gateway_id IS NULL THEN
        RAISE EXCEPTION 'No active payment gateway found for payment_method %', _payment_method
            USING ERRCODE = '22023';
    END IF;

    -- Create payment intent in billing schema
    v_intent_json := billing.create_payment_intent(
        v_gateway_id,
        'commerce_order',
        v_order_id::text,
        v_total_credits,
        _buyer_tenant_id,
        _buyer_email
    );
    v_intent_id := public.safe_cast_uuid(v_intent_json->>'id');

    UPDATE commerce.orders
    SET subtotal_credits = v_subtotal_credits,
        total_credits = v_total_credits,
        payment_intent_id = v_intent_id,
        status = CASE
            WHEN (v_intent_json->>'status') = 'succeeded' THEN 'paid'::commerce.order_status
            ELSE 'pending_payment'::commerce.order_status
        END,
        paid_at = CASE
            WHEN (v_intent_json->>'status') = 'succeeded' THEN v_now
            ELSE NULL
        END,
        updated_at = v_now
    WHERE id = v_order_id;

    -- If instant internal_wallet payment succeeded, fulfill order immediately in same ACID tx
    IF (v_intent_json->>'status') = 'succeeded' THEN
        v_fulfill_json := commerce.fulfill_order(v_order_id);
    END IF;

    SELECT * INTO v_final_order FROM commerce.orders WHERE id = v_order_id;

    RETURN jsonb_build_object(
        'order', to_jsonb(v_final_order) - 'guest_claim_token_hash',
        'payment_intent', v_intent_json,
        'claim_token', v_raw_claim_token,
        'fulfillment', v_fulfill_json
    );
END;
$$;

-- 4.5. Guest Checkout Claim Token Lookup & Deliverables Retrieval
CREATE OR REPLACE FUNCTION commerce.get_guest_order_deliveries(
    _order_code VARCHAR,
    _claim_token VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_order commerce.orders%ROWTYPE;
    v_token_hash VARCHAR(64);
    v_items JSONB;
    v_deliveries JSONB;
BEGIN
    IF _order_code IS NULL OR _claim_token IS NULL OR BTRIM(_claim_token) = '' THEN
        RAISE EXCEPTION 'Both _order_code and _claim_token are required'
            USING ERRCODE = '22023';
    END IF;

    v_token_hash := pg_catalog.encode(extensions.digest(BTRIM(_claim_token), 'sha256'), 'hex');

    SELECT * INTO v_order
    FROM commerce.orders o
    WHERE o.order_code = UPPER(BTRIM(_order_code))
      AND o.guest_claim_token_hash = v_token_hash;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid order_code or claim_token'
            USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(jsonb_agg(to_jsonb(oi) ORDER BY oi.created_at ASC), '[]'::jsonb)
    INTO v_items
    FROM commerce.order_items oi
    WHERE oi.order_id = v_order.id;

    SELECT COALESCE(jsonb_agg(to_jsonb(od) ORDER BY od.created_at ASC), '[]'::jsonb)
    INTO v_deliveries
    FROM commerce.order_deliveries od
    WHERE od.order_id = v_order.id;

    RETURN jsonb_build_object(
        'order', to_jsonb(v_order) - 'guest_claim_token_hash',
        'items', v_items,
        'deliveries', v_deliveries
    );
END;
$$;

-- 4.6. Trigger Bridge: Auto-Fulfill Order When billing.payment_intents Settles
CREATE OR REPLACE FUNCTION commerce.on_payment_intent_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_order_id UUID;
BEGIN
    IF NEW.target_type = 'commerce_order' AND NEW.status IS DISTINCT FROM OLD.status THEN
        v_order_id := public.safe_cast_uuid(NEW.target_id);
        IF v_order_id IS NOT NULL THEN
            IF NEW.status = 'succeeded' THEN
                PERFORM commerce.fulfill_order(v_order_id);
            ELSIF NEW.status = 'manual_review' THEN
                UPDATE commerce.orders
                SET status = 'manual_review',
                    updated_at = timezone('utc'::text, now())
                WHERE id = v_order_id
                  AND status NOT IN ('completed', 'refunded');
            ELSIF NEW.status IN ('failed', 'cancelled') THEN
                UPDATE commerce.orders
                SET status = CASE WHEN NEW.status = 'failed' THEN 'failed'::commerce.order_status ELSE 'cancelled'::commerce.order_status END,
                    cancelled_at = timezone('utc'::text, now()),
                    updated_at = timezone('utc'::text, now())
                WHERE id = v_order_id
                  AND status = 'pending_payment';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_commerce_on_payment_intent_settled ON billing.payment_intents;
CREATE TRIGGER trg_commerce_on_payment_intent_settled
    AFTER UPDATE OF status ON billing.payment_intents
    FOR EACH ROW
    EXECUTE FUNCTION commerce.on_payment_intent_status_change();

GRANT EXECUTE ON FUNCTION commerce.release_expired_reservations(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION commerce.import_stock_batch(UUID, TEXT[], VARCHAR) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION commerce.fulfill_order(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION commerce.create_checkout_order(JSONB, VARCHAR, UUID, VARCHAR, VARCHAR, VARCHAR) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION commerce.get_guest_order_deliveries(VARCHAR, VARCHAR) TO authenticated, anon, service_role;

-- 5. Row-Level Security (RLS) on All 7 Tables
ALTER TABLE commerce.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE commerce.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE commerce.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE commerce.stock_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE commerce.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE commerce.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE commerce.order_deliveries ENABLE ROW LEVEL SECURITY;

-- 5.1. Public & Tenant Catalog Read Policies
DROP POLICY IF EXISTS "categories_select_active" ON commerce.categories;
CREATE POLICY "categories_select_active" ON commerce.categories
    FOR SELECT TO authenticated, anon
    USING (is_active = TRUE);

DROP POLICY IF EXISTS "products_select_public" ON commerce.products;
CREATE POLICY "products_select_public" ON commerce.products
    FOR SELECT TO anon
    USING (is_active = TRUE AND visibility = 'public');

DROP POLICY IF EXISTS "products_select_authenticated" ON commerce.products;
CREATE POLICY "products_select_authenticated" ON commerce.products
    FOR SELECT TO authenticated
    USING (is_active = TRUE AND visibility IN ('public', 'tenant_only'));

DROP POLICY IF EXISTS "variants_select_active" ON commerce.product_variants;
CREATE POLICY "variants_select_active" ON commerce.product_variants
    FOR SELECT TO authenticated, anon
    USING (is_active = TRUE);

-- 5.2. Tenant Orders & Deliveries Read Policies
DROP POLICY IF EXISTS "orders_select_tenant" ON commerce.orders;
CREATE POLICY "orders_select_tenant" ON commerce.orders
    FOR SELECT TO authenticated
    USING (
        (buyer_tenant_id IS NOT NULL AND public.is_tenant_member(buyer_tenant_id))
        OR buyer_user_id = (SELECT auth.uid())
    );

DROP POLICY IF EXISTS "order_items_select_tenant" ON commerce.order_items;
CREATE POLICY "order_items_select_tenant" ON commerce.order_items
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM commerce.orders o
            WHERE o.id = commerce.order_items.order_id
              AND (
                  (o.buyer_tenant_id IS NOT NULL AND public.is_tenant_member(o.buyer_tenant_id))
                  OR o.buyer_user_id = (SELECT auth.uid())
              )
        )
    );

DROP POLICY IF EXISTS "order_deliveries_select_tenant" ON commerce.order_deliveries;
CREATE POLICY "order_deliveries_select_tenant" ON commerce.order_deliveries
    FOR SELECT TO authenticated
    USING (
        (buyer_tenant_id IS NOT NULL AND public.is_tenant_member(buyer_tenant_id))
        OR EXISTS (
            SELECT 1 FROM commerce.orders o
            WHERE o.id = commerce.order_deliveries.order_id
              AND o.buyer_user_id = (SELECT auth.uid())
        )
    );

-- 5.3. Platform Superadmin Full Control Policies (Including Strict Isolation on stock_items)
DROP POLICY IF EXISTS "categories_platform_admin" ON commerce.categories;
CREATE POLICY "categories_platform_admin" ON commerce.categories
    FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "products_platform_admin" ON commerce.products;
CREATE POLICY "products_platform_admin" ON commerce.products
    FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "variants_platform_admin" ON commerce.product_variants;
CREATE POLICY "variants_platform_admin" ON commerce.product_variants
    FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "stock_items_platform_admin" ON commerce.stock_items;
CREATE POLICY "stock_items_platform_admin" ON commerce.stock_items
    FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "orders_platform_admin" ON commerce.orders;
CREATE POLICY "orders_platform_admin" ON commerce.orders
    FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "order_items_platform_admin" ON commerce.order_items;
CREATE POLICY "order_items_platform_admin" ON commerce.order_items
    FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "order_deliveries_platform_admin" ON commerce.order_deliveries;
CREATE POLICY "order_deliveries_platform_admin" ON commerce.order_deliveries
    FOR ALL TO authenticated
    USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

-- 6. Register RBAC Permissions in Base Core Dictionary
INSERT INTO public.permissions (id, module, description)
VALUES
    ('commerce:read',     'commerce', 'View digital store catalog, tenant orders, and fulfilled deliverables'),
    ('commerce:purchase', 'commerce', 'Create digital product orders and pay via tenant wallet or payment gateways'),
    ('commerce:manage',   'commerce', 'Manage store categories, products, variants, serialized stock, and orders')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES ('commerce:read'), ('commerce:purchase')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES ('commerce:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 7. Register Plugin in Master Registry
SELECT public.register_plugin(
    'commerce',
    'Digital Products Store & Auto-Fulfillment',
    '1.0.0',
    'commerce',
    ARRAY['subscriptions', 'workers', 'automation', 'storage']::TEXT[],
    'Multi-category digital products catalog, zero-double-selling serialized stock inventory, order state machine, and atomic auto-fulfillment',
    FALSE,
    '{"guest_checkout_enabled": true, "reservation_ttl_minutes": 15}'::jsonb
);
