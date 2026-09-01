# Sello

Sello is a modern B2B Sales Order Management platform for wholesalers and distributors.

It is designed as a **commercial SaaS** product that stays **generic across industries**. The same platform can serve hardware distributors, electrical suppliers, food wholesalers, cosmetic distributors, beverage suppliers, stationery suppliers, and similar businesses — without hardcoding for any one vertical.

---

## Two experiences, one application

Sello ships as a **single Flutter application** with two distinct user experiences. Both share the same backend, authentication system, database, models, repositories, services, and business logic. Only the presentation layer differs.

### Sello

Used by **Sales Representatives**. Optimized for phones and tablets, and built for fast, touch-friendly field sales.

Primary responsibilities:

- Manage customers
- Browse products
- Check inventory
- Create orders
- Capture customer signatures
- Submit orders

### Sello Hub

Used by **Owners** and **Managers**. Optimized primarily for desktop and laptop, while remaining fully responsive on tablets and mobile.

Primary responsibilities:

- Business dashboard
- Sales insights
- Inventory management
- Product management
- Customer management
- Employee management
- Reports
- Business settings

Sello Hub is intended to feel like an independent business management application — not the sales app with extra screens. Navigation, layout, and information density are designed separately for each experience.

---

## User roles

| Role | Opens after login |
|------|-------------------|
| Sales Representative | **Sello** |
| Owner | **Sello Hub** |
| Manager | **Sello Hub** |

---

## Tech stack

| Layer | Choice |
|-------|--------|
| Client | Flutter (latest stable) |
| UI | Material 3 |
| State / DI | Riverpod |
| Routing | GoRouter |
| Backend | Supabase |
| Database | PostgreSQL |
| Architecture | Clean Architecture + feature-first |
| Layout | Responsive / adaptive (single codebase) |

### Platforms

- Android phones
- Android tablets
- Windows desktop
- Future macOS support

Do not create separate applications. All platforms use adaptive layouts from one codebase.

---

## Project status

**Phase 1 foundation in progress / complete:** design system, responsive shells, routing, and auth stub are in place. Business modules are not implemented yet.

See:

- [ARCHITECTURE.md](ARCHITECTURE.md) — folder structure, module boundaries, routing, auth, responsive strategy, theme, Clean Architecture, Riverpod
- [ROADMAP.md](ROADMAP.md) — phased delivery plan

---

## Intended repository map

```
lib/
  core/           # Theme, breakpoints, router, errors, constants
  shared/         # Shared widgets, models, utilities
  services/       # Supabase client and cross-cutting services
  features/
    mobile/       # Sello (sales) presentation
    hub/          # Sello Hub presentation
```

Domain, data, and application layers are shared so Hub and mobile never duplicate business logic. Details live in [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Getting started

Build and run instructions, including dart-define Supabase config, live in [BUILD.md](BUILD.md).

### Prerequisites

- Flutter SDK (stable) — this project targets Dart `^3.12.2`
- A Supabase project URL and anon (publishable) key

### Run locally

```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

Choose an Android emulator/device, Chrome, or another target as needed. Copy `.env.example` to `.env` first and fill in real values. Never commit `.env`.

---

## Design principles

- **One codebase, dual UX** — share everything except presentation and navigation chrome
- **No duplicated business logic** between Sello and Sello Hub
- **Clean Architecture** — keep widgets free of business rules
- **Intentional responsive layouts** — never stretch a phone layout to desktop
- **Premium Material 3 UI** — modern, minimal, consistent design system
- **Industry-agnostic** — never hardcode for a specific business type
- **Existing database only** — do not change schema unless explicitly instructed

---

## Documentation

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | Product overview and developer entry point |
| [BUILD.md](BUILD.md) | Local run and private-testing build commands |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Technical architecture and conventions |
| [ROADMAP.md](ROADMAP.md) | Delivery phases and scope gates |
