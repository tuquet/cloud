# Plugin: Digital Products Store & Auto-Fulfillment (`commerce`)

> **Plugin ID**: `commerce`  
> **Schema**: `commerce`  
> **Version**: `1.0.0`  
> **Dependencies**: `["subscriptions", "runners", "workflows", "storage"]`

## 1. Overview

Provides the Central Platform Digital Store and Automated Fulfillment engine for the ecosystem. Supports both **Authenticated Tenant Checkout** (instant `Xu` wallet deduction or external payment gateways) and **Public Storefront Guest Checkout** (verified via cryptographic `claim_token`).

## 2. Supported Digital Product Categories (`commerce.product_type`)

1. **`serial_stock`**: Text/serial inventory (`uid|pass|2fa`, license keys, vouchers) with row-level `FOR UPDATE SKIP LOCKED` reservation and zero double-selling guarantees.
2. **`resource`**: Automated provisioning of ecosystem assets directly into the buyer's workspace (`buyer_tenant_id`):
   - `proxy_pool`: Claims proxy lines from `commerce.stock_items` and inserts into `runners.proxies`.
   - `automa_workflow`: Clones template workflows into `workflows.workflows`.
   - `plan_upgrade`: Activates or extends SaaS plans in `billing.subscriptions`.
3. **`digital_file`**: Downloadable assets (`media.assets`) with configurable `max_downloads` and `expires_at`.
4. **`wallet_credit`**: Prepaid `Xu` credit packages (with optional `bonus_credits`) automatically credited via `billing.credit_tenant_wallet()`.

## 3. Database Objects (`schema: commerce`)

- **Tables (7, 100% RLS Enabled)**:
  - `commerce.categories`
  - `commerce.products`
  - `commerce.product_variants`
  - `commerce.stock_items` (Strictly isolated to `public.is_platform_admin()`)
  - `commerce.orders`
  - `commerce.order_items`
  - `commerce.order_deliveries`
- **Hardened RPCs (`SECURITY DEFINER SET search_path = ''`)**:
  - `commerce.import_stock_batch(_variant_id, _lines, _batch_code)`
  - `commerce.release_expired_reservations(_variant_id)`
  - `commerce.create_checkout_order(_items, _payment_method, _buyer_tenant_id, _gateway_code, _buyer_email, _idempotency_key)`
  - `commerce.fulfill_order(_order_id)`
  - `commerce.get_guest_order_deliveries(_order_code, _claim_token)`
  - `commerce.on_payment_intent_status_change()` (Trigger on `billing.payment_intents`)
