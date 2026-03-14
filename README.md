# FIMS — Factory Inventory Management System

A full-stack ERP-lite application built for small manufacturing units. Manages the complete production cycle — from raw material procurement to finished goods dispatch — with a multi-tenant architecture that isolates data per factory.

> **Migration Note:** This repository was published in March 2025. The project has been in active development since late 2024 and is deployed in production at a manufacturing unit. This public version includes the engineering architecture (schema, Docker setup, API structure) for portfolio purposes. The full production codebase is maintained privately.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   React Frontend                     │
│  Vite · React Router v7 · Recharts · Framer Motion  │
│  Socket.IO client (real-time notifications)          │
└────────────────────┬────────────────────────────────┘
                     │ HTTP + WebSocket
┌────────────────────▼────────────────────────────────┐
│                 Express Backend                      │
│  Node.js · JWT Auth · Rate Limiting · Socket.IO      │
│  23 route modules · Multi-tenant middleware          │
└────────────────────┬────────────────────────────────┘
                     │ pg driver
┌────────────────────▼────────────────────────────────┐
│              PostgreSQL (18 tables)                  │
│  FIFO cost layers · Approval queue · Audit ledger   │
│  pg_trgm fuzzy search · Schema migrations tracker   │
└─────────────────────────────────────────────────────┘
```

## Key Design Decisions

**Multi-tenancy**
Every table has a `factory_id` foreign key. The auth middleware extracts `factoryId` from the JWT and appends it to every query — no data bleeds between factories at the ORM or application level.

**FIFO Costing**
A dedicated `cost_layers` table tracks purchase batches by quantity received and unit cost. On dispatch, the system walks oldest layers first, consuming quantities and calculating weighted cost. This gives accurate COGS without external accounting software.

**Approval Workflow**
A generic `approval_requests` table handles PO approvals, inventory corrections, and PO cancellations through the same flow. Each request carries a `details JSONB` field with type-specific payload, and the approved action executes atomically on approval.

**BOM Auto-Deduction**
When a production completion is logged, the system fetches the linked BOM, calculates required quantities for each component, and deducts from stock in a single transaction — preventing partial deductions if any item is short.

**Real-time Notifications**
Socket.IO with JWT middleware handles WebSocket auth. Each connected user joins a `factory-{id}` room — low stock alerts and approval notifications are emitted room-scoped so users only receive their factory's events.

## Database Schema

18 tables — see [`schema/schema.sql`](schema/schema.sql) for the full annotated schema.

| Table | Purpose |
|---|---|
| `factories` | Multi-tenant root — one row per company |
| `users` | Role-based access (admin / manager / storekeeper / viewer) |
| `item_master` | Unified catalog for buy and make items |
| `vendors` | Vendor master with GST and contact details |
| `bom` + `bom_items` | Bill of Materials with version support |
| `purchase_orders` + `_items` | PO with line items, tax, and approval state |
| `material_inwards` | Goods Receipt Notes linked to POs |
| `cost_layers` | FIFO batch stack — quantity remaining per purchase batch |
| `material_issues` | Raw material issue to production floor |
| `production_completions` | Finished goods entry with auto BOM deduction |
| `dispatches` | Outward with FIFO-calculated cost per unit |
| `inventory_corrections` | Admin-approved stock adjustments |
| `approval_requests` | Generic approval queue (PO / correction / cancel) |
| `transactions` | Immutable audit ledger for every stock movement |
| `notifications` | Real-time alert store read by Socket.IO |
| `schema_migrations` | Tracks applied migrations — prevents duplicate runs |

## API Surface

23 REST API modules — see [`api/routes.js`](api/routes.js) for the full endpoint map.

Core modules: `auth` · `item-master` · `vendors` · `purchase-orders` · `material-inwards` · `material-issues` · `production-completions` · `dispatches` · `inventory` · `bom` · `approvals` · `cost-layers` · `reports` · `search` · `notifications`

## Running Locally

**With Docker (recommended)**
```bash
cp .env.example .env   # fill in DB_PASSWORD and JWT_SECRET
docker-compose up --build
```
Opens at `http://localhost:5173`

**Without Docker**
```bash
# 1. Postgres
psql -U postgres -c "CREATE DATABASE fims_db;"
psql -U postgres -d fims_db -f schema/schema.sql

# 2. Backend
cd server
cp ../.env.example .env   # edit with your values
npm install
npm run dev               # http://localhost:5000

# 3. Frontend
cd ..
npm install
npm run dev               # http://localhost:5173
```

## Tech Stack

| Layer | Stack |
|---|---|
| Frontend | React 18, Vite, React Router v7 |
| UI | Custom CSS, Framer Motion, GSAP, Recharts |
| Backend | Node.js, Express, Socket.IO |
| Auth | JWT (jsonwebtoken), bcrypt |
| Database | PostgreSQL 15, `pg` driver |
| Search | PostgreSQL `pg_trgm` extension |
| Export | `xlsx` (Excel), structured PDF data |
| Deployment | Render (backend), Vercel (frontend), Neon (DB) |

## Project Structure

```
├── server/
│   ├── index.js          # Express + Socket.IO setup, migration runner
│   ├── routes/           # 23 API route modules
│   ├── middleware/        # JWT auth, rate limiting
│   ├── database/
│   │   ├── db.js         # pg Pool connection
│   │   └── migrations/   # incremental SQL migrations
│   └── services/         # FIFO engine, notification service
├── src/
│   ├── pages/            # 20+ React page components
│   ├── components/       # Shared UI (modals, tables, forms)
│   ├── services/         # Axios API layer
│   └── hooks/            # useSocket, useAuth
├── portfolio/
│   ├── schema/schema.sql # Full 18-table annotated schema
│   ├── api/routes.js     # API surface documentation
│   ├── Dockerfile        # Multi-stage build
│   └── docker-compose.yml
└── .env.example
```

## License

This project is shared for portfolio and educational viewing only. Commercial use, redistribution, or derivative products are not permitted without written permission.
