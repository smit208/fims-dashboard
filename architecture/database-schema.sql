-- ============================================================
-- FIMS — Factory Inventory Management System
-- PostgreSQL Database Schema
-- 18 tables covering multi-tenant factory operations
-- ============================================================

-- ── Extensions ───────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm; -- Fuzzy search support

-- ── Multi-tenancy: Factories table ───────────────────────────
CREATE TABLE IF NOT EXISTS factories (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    code        VARCHAR(20) UNIQUE NOT NULL,  -- e.g. "CT-001"
    address     TEXT,
    gstin       VARCHAR(20),
    is_active   BOOLEAN DEFAULT true,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Users ─────────────────────────────────────────────────────
-- Roles: admin | manager | storekeeper | viewer
CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    factory_id    INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    username      VARCHAR(50) NOT NULL,
    email         VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name     VARCHAR(100) NOT NULL,
    role          VARCHAR(20) NOT NULL CHECK (role IN ('admin', 'manager', 'storekeeper', 'viewer')),
    is_active     BOOLEAN DEFAULT false,         -- requires admin approval on signup
    approval_threshold DECIMAL(12,2) DEFAULT 0,  -- max value user can approve
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (factory_id, username),
    UNIQUE (factory_id, email)
);

-- ── Item Master ────────────────────────────────────────────────
-- Single source of truth for all items (buy + make)
CREATE TABLE IF NOT EXISTS item_master (
    id               SERIAL PRIMARY KEY,
    factory_id       INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    item_code        VARCHAR(50),
    item_name        VARCHAR(100) NOT NULL,
    description      TEXT,
    unit             VARCHAR(20) NOT NULL,       -- kg, Nos, ltr, m, etc.
    item_type        VARCHAR(20) NOT NULL CHECK (item_type IN ('buy', 'make')),
    make_type        VARCHAR(30) CHECK (make_type IN ('final', 'semi_assembly', 'sub_component')),
    category         VARCHAR(50),
    hsn_code         VARCHAR(20),                -- for GST compliance
    current_stock    DECIMAL(12,2) DEFAULT 0,
    reserved_stock   DECIMAL(12,2) DEFAULT 0,   -- stock locked for production
    minimum_stock    DECIMAL(12,2) DEFAULT 0,
    unit_price       DECIMAL(12,2) DEFAULT 0,
    can_have_bom     BOOLEAN DEFAULT false,
    is_purchasable   BOOLEAN DEFAULT false,
    is_manufacturable BOOLEAN DEFAULT false,
    is_sellable      BOOLEAN DEFAULT false,
    is_active        BOOLEAN DEFAULT true,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (factory_id, item_code)
);

-- ── Vendor Master ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS vendors (
    id           SERIAL PRIMARY KEY,
    factory_id   INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    vendor_name  VARCHAR(100) NOT NULL,
    vendor_code  VARCHAR(50),
    gstin        VARCHAR(20),
    email        VARCHAR(100),
    phone        VARCHAR(20),
    whatsapp     VARCHAR(20),
    address      TEXT,
    payment_terms VARCHAR(100),
    is_active    BOOLEAN DEFAULT true,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Bill of Materials ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bom (
    id           SERIAL PRIMARY KEY,
    factory_id   INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    item_id      INTEGER REFERENCES item_master(id) ON DELETE CASCADE,
    bom_name     VARCHAR(100) NOT NULL,
    version      VARCHAR(20) DEFAULT '1.0',
    is_active    BOOLEAN DEFAULT true,
    created_by   INTEGER REFERENCES users(id),
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bom_items (
    id          SERIAL PRIMARY KEY,
    bom_id      INTEGER REFERENCES bom(id) ON DELETE CASCADE,
    item_id     INTEGER REFERENCES item_master(id) ON DELETE CASCADE,
    quantity    DECIMAL(12,2) NOT NULL CHECK (quantity > 0),
    unit        VARCHAR(20) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Purchase Orders ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS purchase_orders (
    id              SERIAL PRIMARY KEY,
    factory_id      INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    po_number       VARCHAR(50) UNIQUE NOT NULL,   -- AUTO: PO-2024-001
    vendor_id       INTEGER REFERENCES vendors(id),
    po_date         DATE NOT NULL DEFAULT CURRENT_DATE,
    expected_date   DATE,
    status          VARCHAR(20) DEFAULT 'draft' CHECK (status IN ('draft','pending','approved','received','cancelled','cancel_requested')),
    total_amount    DECIMAL(12,2) DEFAULT 0,
    payment_terms   VARCHAR(100),
    notes           TEXT,
    created_by      INTEGER REFERENCES users(id),
    approved_by     INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS purchase_order_items (
    id            SERIAL PRIMARY KEY,
    po_id         INTEGER REFERENCES purchase_orders(id) ON DELETE CASCADE,
    item_id       INTEGER REFERENCES item_master(id),
    quantity      DECIMAL(12,2) NOT NULL CHECK (quantity > 0),
    unit          VARCHAR(20) NOT NULL,
    unit_price    DECIMAL(12,2) NOT NULL,
    tax_percent   DECIMAL(5,2) DEFAULT 0,          -- GST %
    total_price   DECIMAL(12,2) NOT NULL,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Material Inward (GRN) ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS material_inwards (
    id              SERIAL PRIMARY KEY,
    factory_id      INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    inward_number   VARCHAR(50) UNIQUE NOT NULL,
    po_id           INTEGER REFERENCES purchase_orders(id),
    item_id         INTEGER REFERENCES item_master(id),
    quantity        DECIMAL(12,2) NOT NULL CHECK (quantity > 0),
    unit            VARCHAR(20) NOT NULL,
    unit_cost       DECIMAL(12,2) DEFAULT 0,
    supplier        VARCHAR(100),
    grn_number      VARCHAR(50),
    invoice_number  VARCHAR(50),
    vehicle_number  VARCHAR(50),
    received_by     INTEGER REFERENCES users(id),
    received_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes           TEXT,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── FIFO Cost Layers ───────────────────────────────────────────
-- Tracks cost per batch for exact FIFO costing on dispatch
CREATE TABLE IF NOT EXISTS cost_layers (
    id              SERIAL PRIMARY KEY,
    factory_id      INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    item_id         INTEGER REFERENCES item_master(id) ON DELETE CASCADE,
    inward_id       INTEGER REFERENCES material_inwards(id),
    quantity_in     DECIMAL(12,2) NOT NULL,
    quantity_remaining DECIMAL(12,2) NOT NULL,
    unit_cost       DECIMAL(12,2) NOT NULL,
    layer_date      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Material Issue ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS material_issues (
    id              SERIAL PRIMARY KEY,
    factory_id      INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    issue_number    VARCHAR(50) UNIQUE NOT NULL,
    item_id         INTEGER REFERENCES item_master(id),
    quantity        DECIMAL(12,2) NOT NULL CHECK (quantity > 0),
    unit            VARCHAR(20) NOT NULL,
    issued_to       VARCHAR(100),
    purpose         TEXT,
    issued_by       INTEGER REFERENCES users(id),
    issued_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes           TEXT,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Production Completions ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS production_completions (
    id                SERIAL PRIMARY KEY,
    factory_id        INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    completion_number VARCHAR(50) UNIQUE NOT NULL,
    item_id           INTEGER REFERENCES item_master(id),
    quantity          DECIMAL(12,2) NOT NULL CHECK (quantity > 0),
    unit              VARCHAR(20) NOT NULL,
    bom_id            INTEGER REFERENCES bom(id),
    status            VARCHAR(20) DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'cancelled')),
    completed_by      INTEGER REFERENCES users(id),
    completion_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes             TEXT,
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Dispatches ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dispatches (
    id               SERIAL PRIMARY KEY,
    factory_id       INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    dispatch_number  VARCHAR(50) UNIQUE NOT NULL,
    item_id          INTEGER REFERENCES item_master(id),
    quantity         DECIMAL(12,2) NOT NULL CHECK (quantity > 0),
    unit             VARCHAR(20) NOT NULL,
    customer_name    VARCHAR(100),
    delivery_address TEXT,
    vehicle_number   VARCHAR(50),
    invoice_number   VARCHAR(50),
    total_cost       DECIMAL(12,2) DEFAULT 0,  -- FIFO-calculated on dispatch
    cost_per_unit    DECIMAL(12,2) DEFAULT 0,
    dispatched_by    INTEGER REFERENCES users(id),
    dispatch_date    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes            TEXT,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Inventory Corrections ─────────────────────────────────────
-- Admin-supervised stock corrections with approval workflow
CREATE TABLE IF NOT EXISTS inventory_corrections (
    id                SERIAL PRIMARY KEY,
    factory_id        INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    correction_number VARCHAR(50) UNIQUE NOT NULL,
    item_id           INTEGER REFERENCES item_master(id),
    item_name         VARCHAR(100),
    old_quantity      DECIMAL(12,2),
    new_quantity      DECIMAL(12,2),
    difference        DECIMAL(12,2),
    reason            TEXT,
    status            VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    corrected_by      INTEGER REFERENCES users(id),
    approved_by       INTEGER REFERENCES users(id),
    correction_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Approval Requests ─────────────────────────────────────────
-- Generic approval system for POs, corrections, cancellations
CREATE TABLE IF NOT EXISTS approval_requests (
    id              SERIAL PRIMARY KEY,
    factory_id      INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    request_number  VARCHAR(50) UNIQUE NOT NULL,
    request_type    VARCHAR(50) NOT NULL,     -- 'purchase_order' | 'inventory_correction' | 'cancel_po'
    reference_id    INTEGER,
    requested_by    INTEGER REFERENCES users(id),
    request_date    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status          VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    approved_by     INTEGER REFERENCES users(id),
    approval_date   TIMESTAMP,
    rejection_reason TEXT,
    details         JSONB,                   -- flexible payload per request type
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Transactions (Master Ledger) ──────────────────────────────
-- Central audit log — every stock movement writes here
CREATE TABLE IF NOT EXISTS transactions (
    id               SERIAL PRIMARY KEY,
    factory_id       INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    transaction_id   VARCHAR(50) UNIQUE NOT NULL,
    transaction_type VARCHAR(50) NOT NULL CHECK (transaction_type IN (
        'material_inward', 'material_issue',
        'production_completion', 'dispatch',
        'correction', 'reconciliation'
    )),
    reference_id     INTEGER,
    item_id          INTEGER REFERENCES item_master(id),
    item_name        VARCHAR(100),
    quantity         DECIMAL(12,2),
    unit             VARCHAR(20),
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by       INTEGER REFERENCES users(id),
    status           VARCHAR(20) DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'cancelled')),
    notes            TEXT,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Notifications ─────────────────────────────────────────────
-- Real-time notifications delivered via WebSocket (Socket.IO)
CREATE TABLE IF NOT EXISTS notifications (
    id                SERIAL PRIMARY KEY,
    factory_id        INTEGER REFERENCES factories(id) ON DELETE CASCADE,
    user_id           INTEGER REFERENCES users(id),
    title             VARCHAR(200) NOT NULL,
    description       TEXT,
    notification_type VARCHAR(50),
    status            VARCHAR(20) DEFAULT 'warning' CHECK (status IN ('okay', 'warning', 'critical')),
    is_read           BOOLEAN DEFAULT false,
    reference_type    VARCHAR(50),
    reference_id      INTEGER,
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Schema Migrations Tracker ────────────────────────────────
-- Prevents duplicate migration runs on server restart
CREATE TABLE IF NOT EXISTS schema_migrations (
    key        VARCHAR(255) PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ── Indexes ───────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_item_master_factory    ON item_master(factory_id);
CREATE INDEX IF NOT EXISTS idx_transactions_factory   ON transactions(factory_id);
CREATE INDEX IF NOT EXISTS idx_transactions_type      ON transactions(transaction_type);
CREATE INDEX IF NOT EXISTS idx_transactions_date      ON transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_cost_layers_item       ON cost_layers(item_id, layer_date);
CREATE INDEX IF NOT EXISTS idx_notifications_user     ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_approval_status        ON approval_requests(factory_id, status);
CREATE INDEX IF NOT EXISTS idx_po_factory_status      ON purchase_orders(factory_id, status);
CREATE INDEX IF NOT EXISTS idx_item_master_trgm       ON item_master USING GIN (item_name gin_trgm_ops);

-- ── Table Summary ─────────────────────────────────────────────
-- factories             — multi-tenant root
-- users                 — role-based, factory-scoped
-- item_master           — unified buy/make item catalog
-- vendors               — vendor master with contact info
-- bom                   — bill of materials header
-- bom_items             — BOM line items
-- purchase_orders       — PO with approval workflow
-- purchase_order_items  — PO line items with GST
-- material_inwards      — GRN / goods receipt
-- cost_layers           — FIFO batch costing
-- material_issues       — raw material issue to production
-- production_completions — finished goods entry
-- dispatches            — outward with FIFO cost calculation
-- inventory_corrections — supervised stock adjustment
-- approval_requests     — generic approval queue
-- transactions          — immutable audit ledger
-- notifications         — real-time alert store
-- schema_migrations     — migration run tracker
