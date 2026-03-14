/**
 * FIMS API — Route Overview
 * =========================
 * This file documents the full API surface of the FIMS backend.
 * All routes are prefixed with /api and protected by JWT middleware.
 * Rate limiting is applied globally (100 req/15min); auth routes are 
 * stricter (10 req/15min).
 *
 * Auth header: Authorization: Bearer <token>
 * Factory isolation: every authenticated request is scoped to
 * req.user.factoryId — enforced at the middleware level.
 */

const express = require('express');
const router = express.Router();

// ── Auth ──────────────────────────────────────────────────────
// POST   /api/auth/signup          — register user (requires admin approval)
// POST   /api/auth/login           — returns JWT
// GET    /api/auth/me              — get current user from token
// POST   /api/auth/logout          — invalidate session
// GET    /api/auth/pending-users   — [admin] list unapproved signups
// PUT    /api/auth/approve/:id     — [admin] approve user
// PUT    /api/auth/reject/:id      — [admin] reject user

// ── Dashboard ─────────────────────────────────────────────────
// GET    /api/dashboard/stats           — KPI summary (stock value, low items, pending POs)
// GET    /api/dashboard/recent-activity — last 20 transactions

// ── Item Master ───────────────────────────────────────────────
// GET    /api/item-master               — list all items (with filters: type, category, search)
// GET    /api/item-master/purchasable   — items with is_purchasable=true (for PO forms)
// GET    /api/item-master/:id           — single item
// POST   /api/item-master               — [admin/manager] create item
// PUT    /api/item-master/:id           — [admin/manager] update item
// DELETE /api/item-master/:id           — [admin] soft delete

// ── Vendors ───────────────────────────────────────────────────
// GET    /api/vendors      — list all vendors
// GET    /api/vendors/:id  — single vendor with contact info
// POST   /api/vendors      — create vendor
// PUT    /api/vendors/:id  — update vendor
// DELETE /api/vendors/:id  — delete vendor

// ── Purchase Orders ───────────────────────────────────────────
// GET    /api/purchase-orders              — list (filter: status, vendor, date range)
// GET    /api/purchase-orders/:id          — detail with line items
// POST   /api/purchase-orders              — create draft PO
// PUT    /api/purchase-orders/:id          — update PO
// POST   /api/purchase-orders/:id/submit   — submit for approval
// POST   /api/purchase-orders/:id/receive  — mark as received (triggers inward)
// POST   /api/purchase-orders/:id/cancel   — cancel (if approved, creates approval request)
// GET    /api/purchase-orders/:id/pdf      — export as structured data for PDF

// ── Material Inward (GRN) ─────────────────────────────────────
// GET    /api/material-inwards       — list all inward records
// GET    /api/material-inwards/:id   — single record with PO linkage
// POST   /api/material-inwards       — create inward (updates stock + cost layer)

// ── Material Issue ────────────────────────────────────────────
// GET    /api/material-issues       — list all issues
// GET    /api/material-issues/:id   — single issue
// POST   /api/material-issues       — issue material (deducts from stock)

// ── Production Completions ────────────────────────────────────
// GET    /api/production-completions       — list completions
// GET    /api/production-completions/:id   — single completion with BOM used
// POST   /api/production-completions       — log production (auto-deducts BOM components)

// ── Dispatches ────────────────────────────────────────────────
// GET    /api/dispatches        — list dispatches
// GET    /api/dispatches/:id    — single dispatch with FIFO cost breakdown
// POST   /api/dispatches        — create dispatch (FIFO costing applied on write)

// ── Inventory ─────────────────────────────────────────────────
// GET    /api/inventory             — current stock for all items
// GET    /api/inventory/low-stock   — items below minimum_stock threshold
// GET    /api/inventory/valuation   — total inventory value (FIFO last cost)
// POST   /api/inventory/corrections — create correction (triggers approval flow)

// ── BOM Management ────────────────────────────────────────────
// GET    /api/bom           — list all BOMs
// GET    /api/bom/:id       — BOM with all line items
// POST   /api/bom           — create BOM
// PUT    /api/bom/:id       — update BOM
// DELETE /api/bom/:id       — delete BOM

// ── Approvals ─────────────────────────────────────────────────
// GET    /api/approvals              — list pending approvals (admin sees all)
// GET    /api/approvals/:id          — single request with details payload
// PUT    /api/approvals/:id/approve  — approve (applies the underlying action)
// PUT    /api/approvals/:id/reject   — reject with reason

// ── Notifications ─────────────────────────────────────────────
// GET    /api/notifications          — user's notifications (unread first)
// PUT    /api/notifications/:id/read — mark as read
// PUT    /api/notifications/read-all — mark all as read

// ── Reports ───────────────────────────────────────────────────
// GET    /api/reports/purchase        — purchase report (date range, vendor filter)
// GET    /api/reports/inventory       — inventory movement report
// GET    /api/reports/production      — production report
// GET    /api/reports/dispatch        — dispatch report with FIFO cost
// GET    /api/reports/vendor-ledger   — per-vendor purchase + payment ledger

// ── Search ────────────────────────────────────────────────────
// GET    /api/search?q=&type=         — fuzzy search across items, POs, vendors
//                                       (powered by PostgreSQL pg_trgm extension)

// ── Cost Layers ───────────────────────────────────────────────
// GET    /api/cost-layers/:itemId     — FIFO batch stack for an item

// ── Users (admin) ─────────────────────────────────────────────
// GET    /api/users         — list all users in factory
// POST   /api/users         — create user
// PUT    /api/users/:id     — update user role/status
// DELETE /api/users/:id     — deactivate user

// ── Settings ──────────────────────────────────────────────────
// GET    /api/settings       — factory settings
// PUT    /api/settings       — update settings (name, logo, GST, approval threshold)

module.exports = router;
