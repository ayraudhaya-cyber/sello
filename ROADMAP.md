# Sello Roadmap

Phased delivery plan for Sello. Each phase has a clear goal and gate. **Do not start a phase until the previous phase is approved**, unless explicitly instructed otherwise.

Related documents:

- [README.md](README.md) — product overview
- [ARCHITECTURE.md](ARCHITECTURE.md) — architecture and conventions

---

## Phase 0 — Documentation

**Status:** Current

**Goal:** Establish product vision and technical direction in writing before any foundation or feature code.

**In scope:**

- [README.md](README.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [ROADMAP.md](ROADMAP.md)

**Out of scope:**

- `lib/` restructuring
- Dependencies beyond the default Flutter template
- UI, auth, Supabase, or business features

**Exit criteria:** Documentation reviewed and approved.

---

## Phase 1 — Foundation

**Goal:** Production-ready project skeleton with shared architecture, design system, routing shells, and auth placeholders — **no business features**.

**In scope:**

- Enterprise folder structure (`core/`, `shared/`, `services/`, `features/mobile/`, `features/hub/`)
- Material 3 theme and design-system tokens (typography, spacing, radius, elevation)
- Shared UI primitives (buttons, cards, inputs, dialogs, snackbars, tables, empty/loading/error states)
- Responsive breakpoints (`AppBreakpoints`) and layout helpers
- Riverpod app bootstrap
- GoRouter configuration with `/login`, `/sello/...`, `/hub/...`
- Navigation shells: `SelloShell` and `HubShell` (adaptive chrome)
- Supabase client initialization (config via env/placeholders as agreed)
- Authentication skeleton (login UI shell + role-based redirect stubs)
- Base models / common utilities as needed for the skeleton
- No real CRUD for customers, products, orders, etc.

**Out of scope:**

- Full auth against live employee/role data (beyond skeleton)
- Sales order workflows
- Hub admin CRUD and analytics
- Database schema changes

**Exit criteria:** App launches, switches layouts by breakpoint, routes into placeholder shells by role (mocked or stubbed as designed), and is ready for real auth wiring.

---

## Phase 2 — Auth & session

**Goal:** Real authentication and secure, role-based entry into the correct experience.

**In scope:**

- Supabase Auth sign-in / sign-out
- Session restore on cold start
- Employee + role resolution from existing tables
- GoRouter redirects enforcing Sello vs Hub access
- Basic profile / session handling in both shells
- Error handling for invalid credentials and missing role assignments

**Out of scope:**

- Full feature modules (orders, inventory admin, reports)
- Schema migrations

**Exit criteria:** Owner/Manager land in Hub; Sales Representative lands in Sello; unauthorized cross-navigation is blocked.

---

## Phase 3 — Sello (mobile) core

**Goal:** Field-sales MVP inside the Sello experience.

**In scope:**

- Customers (list, detail, create/edit as required for field use)
- Products browse
- Inventory check
- Order create, line items, submit
- Customer signature capture
- Mobile/tablet-optimized flows using the shared design system

**Out of scope:**

- Hub administration screens
- Advanced analytics
- Industry-specific customizations

**Exit criteria:** A sales rep can complete a typical order capture journey on phone and tablet.

---

## Phase 4 — Sello Hub core

**Goal:** Operational business console for Owners and Managers.

**In scope:**

- Business dashboard (core KPIs / overview)
- Product management
- Inventory management
- Customer management
- Employee management
- Business settings
- Desktop-first layouts (tables, sidebars, multi-column where appropriate)

**Out of scope:**

- Deep analytics / advanced reporting (Phase 5)
- Changing database schema without approval

**Exit criteria:** Owners/Managers can administer catalog, inventory, customers, and employees from Hub.

---

## Phase 5 — Insights & reports

**Goal:** Sales insights and reporting surfaces in Sello Hub.

**In scope:**

- Analytics views
- Reports (sales, inventory, and related operational reports as prioritized)
- Hub navigation entries for insights/reports

**Out of scope:**

- Rebuilding mobile order flows
- Unrelated net-new product lines

**Exit criteria:** Managers/Owners can answer key operational questions from Hub without exporting raw data manually (exact report set defined at phase kickoff).

---

## Phase 6 — Hardening

**Goal:** Production readiness across supported platforms.

**In scope:**

- QA pass across Android phone, Android tablet, and Windows
- Performance and stability fixes
- Packaging / release configuration for supported targets
- macOS readiness (build and adaptive checks) when prioritized
- Resilience patterns (e.g. offline/retry) **only if** product requirements call for them
- Security review of auth, RLS assumptions, and client config handling

**Out of scope:**

- Large new feature areas not already delivered
- Database redesign

**Exit criteria:** Release candidate suitable for commercial pilot or production rollout on agreed platforms.

---

## Cross-cutting constraints (all phases)

- Single Flutter project; single Supabase backend; one auth system.
- Share business logic; diverge only in presentation.
- Do not modify the database structure unless instructed.
- Remain industry-agnostic — no hardcoding for a specific business type.
- Prefer intentional responsive layouts over stretched single layouts.

---

## Approval gates

| After phase | Wait for |
|-------------|----------|
| 0 Documentation | Approval to begin Phase 1 foundation |
| 1 Foundation | Approval before Phase 2 auth |
| 2+ Features | Prioritize and approve each feature phase explicitly |

**Next step after Phase 0:** wait for approval, then implement Phase 1 foundation only — still no business features until that foundation is accepted.
