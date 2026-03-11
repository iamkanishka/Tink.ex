# Changelog

All notable changes to Tink are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Tink uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [0.1.1] - 2026-03-11

Three days of fixes, refactoring, cache integration, static analysis cleanup,
and project scaffolding on top of the empty 0.1.0 skeleton.

---

### March 9 — Initial SDK Implementation

All 35 source files written from scratch, implementing the full Tink API surface.

**Core infrastructure**

- `Tink.Application` — OTP application, Finch pool supervision, Cachex child spec
- `Tink.Client` — HTTP client struct, token attachment, cacheable-pattern detection
- `Tink.Config` — runtime config reader with typed accessors
- `Tink.Auth` / `Tink.AuthToken` — OAuth 2.0 client credentials and authorization code flows
- `Tink.Error` — unified error struct (`status`, `code`, `message`, `request_id`)
- `Tink.HTTPBehaviour` — behaviour contract for HTTP adapters
- `Tink.HTTPAdapter` — Finch-backed implementation with request/response encoding
- `Tink.Retry` — exponential backoff with jitter for 429 / 503 / network errors
- `Tink.RateLimiter` — per-key rate limiting via Hammer
- `Tink.Cache` — Cachex wrapper with TTL helpers and user-scoped invalidation
- `Tink.Helpers` — shared URL building and query encoding utilities
- `Tink.Connector` — provider connection utilities
- `Tink.WebhookHandler` — event dispatch and handler registration
- `Tink.WebhookVerifier` — HMAC signature verification

**Domain modules**

- `Tink.Accounts`, `Tink.Users`, `Tink.Categories`, `Tink.Statistics`
- `Tink.Transactions`, `Tink.TransactionsOneTimeAccess`, `Tink.TransactionsContinuousAccess`
- `Tink.AccountCheck`, `Tink.BalanceCheck`, `Tink.BusinessAccountCheck`
- `Tink.IncomeCheck`, `Tink.ExpenseCheck`
- `Tink.RiskInsights`, `Tink.RiskCategorisation`
- `Tink.Investments`, `Tink.Loans`
- `Tink.Budgets`, `Tink.CashFlow`, `Tink.FinancialCalendar`
- `Tink.Providers`, `Tink.Connectivity`, `Tink.Link`

---

### March 10 — Bug Fixes, Security, and Structural Refactoring

#### Fixed — Critical Bugs

- **`link.ex`** — `add_test_params/2`: `params` variable was unbound, causing a compile error
- **`statistics.ex`** — Duplicate `defmodule Tink.Statistics` block (lines 367–end) caused a compile conflict; removed
- **`balance_check.ex`** — `build_consent_update_link/2`: URL was missing the `https://` scheme, producing a malformed link
- **`connector.ex`** — String interpolation bug: literal `"demo-scenario_str"` was never interpolated; corrected to `"demo-#{scenario_str}"`
- **`client.ex`** — `do_delete/3` had two contradictory success match clauses; unified to consistently return `{:ok, body}` or `{:ok, %{}}`, matching all other HTTP verb helpers
- **`users.ex`** — `delete_credential/2` `@spec` declared return type as `:ok`; corrected to `{:ok, map()} | {:error, Error.t()}`

#### Fixed — Security

- **`webhook_verifier.ex`** — Replaced non-constant-time `secure_compare/2` with `:crypto.hash_equals/2` to eliminate a timing side-channel vulnerability in webhook signature verification

#### Fixed — Correctness

- **`config.ex`** — Rate limit config key mismatch: code read from nested `:rate_limit` but docs specified flat `:enable_rate_limiting`; aligned to flat key throughout
- **`webhook_handler.ex`** — `validate_payload/1` was defined but never called; added to the `with` pipeline so invalid payloads are rejected before dispatch
- **`webhook_handler.ex`** — Test webhooks from the Tink console were being dispatched as `:unknown` events; added `check_not_test_webhook/1` guard to intercept and acknowledge them without dispatch
- **`cache.ex`** — Dead `pattern` variable in `invalidate_user/1`; prefix was bare `user_id` which could match unintended keys — corrected to `"#{user_id}:"` to scope invalidation precisely

#### Changed — Design

- **`webhook_handler.ex` + `application.ex`** — Replaced `Application.put_env` handler registry with an ETS `:bag` table (`:tink_webhook_handlers`) created at application start; concurrent-safe, survives config reloads, supports multiple handlers per event type

#### Changed — Structure

- **`account_check.ex`, `balance_check.ex`** — Replaced duplicate auth, user, and credential functions (copied verbatim from `Tink.Users` / `Tink.Accounts`) with `defdelegate` — single source of truth, eliminates maintenance divergence risk
- **`transactions.ex`** — Replaced duplicate `list_accounts` implementation with `defdelegate list_accounts(client, opts \\ []), to: Tink.Accounts`
- **`providers.ex`** — Removed unused `Cache` alias; replaced private `build_url` / `build_query_params` helpers with `Helpers.build_url`; added explicit `Cache.fetch/3` for cacheable reads
- **`client.ex`** — Rewrote `cacheable?/1` using module-level `@cacheable_patterns` and `@non_cacheable_patterns` compile-time constants; fixed `detect_resource_type/1` ordering so specific patterns are matched before catch-all ones
- **`retry.ex`** — `default_retry?/1` now delegates to `should_retry?/1` instead of duplicating logic; `log_no_retry/2` gated on `Config.debug_mode?()` to match `log_retry/2` symmetrically
- **`users.ex`** — Removed redundant `Cache.invalidate_user/1` call in `refresh_credential/2` — invalidation already handled by the underlying credential update path

---

### March 11 — Cache Integration, Dialyzer, Best Practices, Project Config

#### Added — Cache Integration

Explicit `Cache.fetch/3` added to all cacheable read operations across seven
domain modules. Each module owns its own cache keys and TTLs; `Client.get`
automatic caching is retained only as a fallback. All cache calls pass
`cache: false` to `Client.get` to prevent double-caching. Cache is skipped
when `client.cache` is falsy or `Cache.enabled?()` returns false.

Cache keys follow the pattern `"scope:resource:qualifier"` with `"list"` /
`"item"` disambiguators to prevent key collisions between list and single-item
queries.

| Module | Functions | TTL |
|---|---|---|
| `Tink.Providers` | `list_providers/2`, `get_provider/2` | 1 hour / 2 hours |
| `Tink.Categories` | `list_categories/2`, `get_category/3` | 24 hours |
| `Tink.Accounts` | `list_accounts/2`, `get_account/2` | 5 minutes |
| `Tink.Accounts` | `get_balances/2` | 1 minute |
| `Tink.Statistics` | `get_statistics/2`, `get_category_statistics/3`, `get_account_statistics/3` | 1 hour |
| `Tink.Investments` | `list_accounts/1`, `get_holdings/2` | 5 minutes |
| `Tink.Loans` | `list_accounts/1`, `get_account/2` | 5 minutes |
| `Tink.Budgets` | `get_budget/2`, `list_budgets/2` | 5 minutes |
| `Tink.Budgets` | `update_budget/3` | Invalidates cache on success |

#### Fixed — Dialyzer

- **`account_check.ex:357`** — `is_binary(binary)` guard on a value typed as `map()` can never succeed; removed the unreachable guard and split the PDF-map and plain-map branches
- **`application.ex`** — `@transport_opts` module attribute cannot store the closure returned by `:public_key.pkix_verify_hostname_match_fun/1` (Elixir only escapes static terms); replaced with a compile-time `if @env == :prod do … end` block emitting two `defp transport_opts/0` clauses — eliminates the `ArgumentError` while retaining compile-time branch selection
- **`application.ex`** — `case @env do` with a compile-time `@env` caused dead-branch warnings for non-current environments; replaced with `@pool_count` and `@default_pool_size` compile-time module attributes to eliminate the branching entirely
- **`auth.ex:258`** — Referenced `Tink.health_check/1` which does not exist; replaced with `Client.get(client, "/api/v1/user", cache: false)`
- **`balance_check.ex:68`** — `alias Tink.Helpers` was unused; removed
- **`connectivity.ex:505`** — `{:error, reason}` match clause was unreachable given the success type of the preceding call; removed
- **`http_adapter.ex:229`** — `decode_response(%{body: _body})` fallback unreachable because Finch always returns a binary body; removed dead clause
- **`rate_limiter.ex`** — Full rewrite: bare `Hammer.check_rate/3`, `inspect_bucket/3`, `delete_buckets/1` calls (Hammer v5/v6 API that no longer exists in 7.x) replaced with Hammer 7.2 `use Hammer, backend: :ets, algorithm: :fix_window` named-backend pattern using `Backend.hit/3` and `Backend.get/2`; backend process added to `Tink.Application` supervision tree

#### Changed — Best Practices

- **`client.ex`** — Removed unused `Config` and `HTTPAdapter` aliases
- **`http_adapter.ex`** — Added `@spec` to all 6 `@impl true` behaviour callbacks
- **`application.ex`** — Added `@spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}`
- **`error.ex`** — Replaced `IO.inspect(error)` in `@moduledoc` example with `Logger.error/1`
- **18 domain modules** — Added 52 missing `@spec` annotations to public helper functions
- **`categories.ex`, `accounts.ex`** — Added `"list"` / `"item"` cache key disambiguators to eliminate collision risk between list-query and single-item cache entries

#### Added — Project Scaffolding

- **`mix.exs`** — Corrected app name `:tink` → `:tink`; module prefix `Tink.*` → `Tink.*` throughout; added `:public_key` to `extra_applications`; `groups_for_modules` updated with all actual module names and a new Webhooks group; `extras` expanded to cover all guide paths
- **`.formatter.exs`** — Set `line_length: 120`; added `defdelegate: 2` to `locals_without_parens`
- **`.credo.exs`** — `strict: true`; `MaxLineLength` aligned to 120; per-check rationale comments for all disabled entries; `included` paths tightened for a single-app library
- **`.dialyzer_ignore.exs`** — Documented suppressions for all 5 known benign Dialyzer warnings
- **`README.md`** — Hex badge, feature overview, quick-start snippet, full product table, configuration reference
- **`LICENSE`** — MIT
- **19 documentation guides** across `guides/`, `guides/products/`, and `guides/advanced/`

---

## [0.1.0] - 2025-03-01

Initial release — empty Elixir package published to Hex.pm to reserve the
`tink` package name.