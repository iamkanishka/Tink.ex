# Changelog

All notable changes to this project will be documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.0] - 2026-06-17

### Fixed (static analysis hardening — Dialyzer/Credo, included in this 1.0.0 cut)

**Dialyzer — contract/spec accuracy**
- Tink.AuthToken.summary/1: tightened the return spec from map() to the
  exact fixed-key shape actually returned (expired, expiry, scope_count,
  scopes, auto_refresh, cache).
- Tink.Cache.stats/0: tightened {:error, any()} to {:error, map()},
  matching Cachex.stats/2's own spec (both tuple positions are map()).
- Tink.HTTP.MutualTLS.finch_pools/0: tightened map() to the precise
  %{String.t() => keyword()} shape returned.
- Tink.HTTP.MutualTLS.child_spec/0: fixed an invalid_contract — the
  declared Supervisor.child_spec() return type is the formal
  %{id:, start: {mod, fun, args}, ...} map shape, but this function
  actually returns a {Finch, opts} 2-tuple meant to be dropped directly
  into a children list (Finch expands it into the real child spec at
  start time). Spec corrected to {module(), keyword()} with a doc note
  explaining the distinction.

**Credo — readability and design**
- Fixed alphabetical alias ordering in test/tink/utils_test.exs
  (alias Tink.{Utils, Client} → alias Tink.{Client, Utils}).
- Tink.Utils.do_poll/5 and Tink.Paginator.stream/2 both nested 3 levels
  deep (if/case/cond and fn/case/if respectively), exceeding the
  configured max of 2. Refactored by extracting the innermost branch into
  separate named helper functions (handle_poll_result/6 +
  wait_and_retry/5 for the former; fetch_page/4 + next_token_or_done/1
  for the latter) — behavior is unchanged, verified by the full test suite.
- Tink.Client's core request pipeline used apply(:request, [...]) on a
  module value with a statically-known arity; replaced with the idiomatic
  module.request(...) dot-call syntax, which is both clearer and friendlier
  to Dialyzer.
- Addressed "nested modules could be aliased at the top of the invoking
  module" (Credo.Check.Design.AliasUsage) across lib/: added missing
  aliases for Tink.Config (application.ex, cache.ex, client.ex,
  http.ex — both adapter modules, webhooks.ex), Tink.RateLimiter
  (application.ex), Tink.Statistics (finance.ex's Tink.CashFlow),
  and Plug.Conn (webhooks.ex's Tink.WebhookVerifier); also fixed one
  redundant fully-qualified Tink.Error.from_response/2 call in
  enrichment.ex where Error was already aliased but not used. lib/ is
  now clean of this warning. Note: test/ files still call most public API
  functions by their fully-qualified name (e.g. Tink.Accounts.list/1) by
  design — these files each exercise many unrelated modules, where the
  fully-qualified name makes it immediately clear which module's behavior
  is under test; this was left as-is rather than mass-aliased.

**Incidental fixes found while addressing the above**
- Tink.Client's hardcoded User-Agent header ("tink-elixir/0.2.0") was
  stale after the version bump to 1.0.0. Replaced with a tink_version/0
  helper that reads Application.spec(:tink, :vsn) at runtime, so it can
  never go stale again.

### Fixed (post-review hardening, included in this 1.0.0 cut)

**Auth (breaking change for these two functions)**
- Tink.Auth.create_authorization/2 and Tink.Auth.delegate_authorization/2
  now send application/x-www-form-urlencoded bodies with snake_case keys
  (user_id, external_user_id, scope, id_hint), matching the real Tink
  API. Previously these sent JSON with camelCase keys, which Tink's
  authorization-grant endpoints reject.
- delegate_authorization/2 now supports the required :actor_client_id
  parameter (previously missing entirely, making delegated grants
  impossible) and an optional :client_id override.

**Application supervision tree (startup-crashing bugs)**
- Fixed Tink.Application's Cachex child spec, which used the :limit
  start option and %Cachex.Limit{} struct removed in Cachex v4. Cache size
  limiting is now configured via the :hooks option with
  Cachex.Limit.Scheduled, per Cachex's v4 migration guide. This previously
  crashed the supervisor on startup whenever cache: [enabled: true].
- Fixed a typo'd Hammer ETS backend option (cleanup_rate_ms →
  cleanup_interval_ms).
- Added the required config :hammer, backend: {Hammer.Backend.ETS, [...]}
  application config — without it, Hammer.check_rate/3 (used by
  Tink.RateLimiter) has no backend to talk to. The Hammer child is now
  only started when rate limiting is actually enabled.
- Note: these bugs were not caught by the test suite because config/test.exs
  disables both caching and rate limiting, so the corresponding supervisor
  children were never started during mix test.

**Webhook signature verification (breaking dependency fix)**
- Tink.WebhookVerifier.verify/3 (and therefore verify_with_config/2) called
  Plug.Crypto.secure_compare/2 directly, but :plug_crypto was never
  declared as a dependency anywhere in mix.exs. This made the *core*,
  non-Plug-specific signature verification function completely broken
  (UndefinedFunctionError) for any consumer that doesn't separately happen
  to have Phoenix/Plug in their dependency tree — e.g. an Oban worker or a
  plain CLI tool processing webhooks. Replaced with a dependency-free
  constant-time comparison (:crypto.hash_equals/2 on OTP 25+, with a
  manual XOR-accumulator fallback for OTP 23/24, which Elixir 1.14 still
  supports). verify_plug/2 still optionally uses Plug.Conn, which is now
  declared as an optional: true dependency.
- This bug was caught by actually running the test suite (mix test)
  against real dependency sources, not just static review — mix.exs was
  also missing elixirc_paths: ["lib", "test/support"], so mix test
  couldn't even compile beforehand. Both are fixed.

**Mutual TLS (Tink.HTTP.MutualTLS)**
- Fixed cert_pem/key_pem/ca_pem handling: :ssl transport options
  require raw DER-encoded binaries for :cert/:cacerts, and {KeyType,
  der} for :key — not decoded public_key records. The previous
  implementation called :public_key.pem_entry_decode/1, which fully
  decodes the PEM entry into an Erlang record (incompatible with :ssl),
  and hardcoded the key type to :RSAPrivateKey even for EC or PKCS#8
  ("PrivateKeyInfo") keys.

**Documentation accuracy**
- Removed an unverified "(max 1000)" page size claim for
  Tink.Transactions.list/2 (/data/v2/transactions); documented the
  confirmed default (10) and max (100) for the related
  /enrichment/v1/transactions endpoint instead.
- Clarified that requests_per_min: 600 in Tink.RateLimiter's example
  config is a conservative client-side default, not a published Tink limit
  — Tink enforces per-app-ID server-side limits without publishing an exact
  number.

### Known caveats (not changed — unverified)
- Tink.WebhookVerifier implements HMAC-SHA256 hex-digest verification
  against an X-Tink-Signature header. This matches the most common
  industry pattern (and could not be contradicted), but the exact header
  name and encoding could not be independently confirmed against Tink's
  current docs in this review. Verify against your Tink dashboard/docs
  before relying on it in production.

### Added

**Auth**
- Tink.Auth.revoke_all/1 — authorization:revoke scope, POST /api/v1/oauth/revoke-all
- Tink.Auth.inspect_token/1 — inspect current token validity and scopes

**Users**
- Tink.Users.get_user/1 — GET /api/v1/user
- Tink.Users.get_profile/1 — GET /api/v1/user/profile
- Tink.Users.update_user/2 — PUT /api/v1/user
- Tink.Users.update_profile/2 — PUT /api/v1/user/profile

**Credentials (new dedicated module)**
- Tink.Credentials.get_qr/2 — GET /api/v1/credentials/{id}/qr
- Tink.Credentials.create/2 — POST /api/v1/credentials
- Tink.Credentials.authenticate/2 — POST /api/v1/credentials/{id}/authenticate
- Tink.Credentials.submit_supplemental_info/3 — POST /api/v1/credentials/{id}/supplemental-information (MFA/BankID flows)

**Accounts**
- Tink.Accounts.get_parties/2 — accounts.parties:readonly
- Tink.Accounts.update/3 — PATCH /api/v1/accounts/{id}
- Tink.Accounts.stream/2 — lazy Stream over all pages

**Transactions**
- Tink.Transactions.get/2 — GET /api/v1/transactions/{id}
- Tink.Transactions.get_similar/2 — GET /api/v1/transactions/{id}/similar
- Tink.Transactions.search/2 — POST /api/v1/search
- Tink.Transactions.suggest/2 — GET /api/v1/transactions/suggest
- Tink.Transactions.update/3 — PUT /api/v1/transactions/{id}
- Tink.Transactions.categorize_multiple/2 — transactions:categorize
- Tink.Transactions.stream/2 — lazy Stream over all pages
- Tink.Transactions.list_all/2 — eager collect all pages

**Providers**
- Tink.Providers.list_markets/1
- Tink.Providers.list_identifiers/1
- Tink.Providers.get_auth_options/2
- Tink.Providers.get_auth_options_for_market/2

**New: Identities**
- Tink.Identities module — identity:read + identities:readonly

**New: Enrichment sub-modules** (replacing unnamed functions)
- Tink.Enrichment.Categories
- Tink.Enrichment.Transactions — with submit_feedback/2
- Tink.Enrichment.Recurring
- Tink.Enrichment.Merchants — get_brand/2, get_merchant/2
- Tink.Enrichment.OnDemand — enrich/2
- Tink.Enrichment.Sustainability — all 8 endpoints

**New: Payments (entirely new domain)**
- Tink.Payments — create, get, get_transfers, cancel, get_conditions, create_settlement_payment, poll_until_terminal
- Tink.MandatePayments — v1 + v2, poll_until_terminal
- Tink.Mandates — get, revoke
- Tink.BulkPayments — create, get
- Tink.SettlementAccounts — accounts, refunds, withdrawals, transactions (full CRUD)

**Budgets (completed)**
- Tink.Budgets.create_one_off/2
- Tink.Budgets.create_recurring/2
- Tink.Budgets.get_details/2
- Tink.Budgets.get_transactions/2
- Tink.Budgets.list_summaries/1
- Tink.Budgets.list_recommended/1
- Tink.Budgets.archive/2

**New: Finance management modules**
- Tink.SavingsGoals — full CRUD + archive, complete, allocations, deposit, withdraw, reallocate
- Tink.Subscriptions — list, get_transactions, update
- Tink.CostOfLiving — list, get_transactions, update
- Tink.Insights — list, list_archived, archive, take_action

**RiskInsights (completed)**
- Tink.RiskInsights.create/2
- Tink.RiskInsights.delete/2

**AccountCheck**
- Tink.AccountCheck.get_pdf/2

**New: BalanceCheck / BalanceRefresh**
- Tink.BalanceCheck.trigger_refresh/2
- Tink.BalanceCheck.get_refresh_status/2
- Tink.BalanceCheck.poll_until_complete/3

**New: Connectivity**
- Tink.Consents — full v2 consent lifecycle (create, list, get, revoke, authorizations, relay, templates)
- Tink.ProviderConsents — list, extend

**Connector (completed)**
- Tink.Connector.upsert_account/4 — single account upsert
- Tink.Connector.delete_accounts/2 — v2 batch delete
- Tink.Connector.delete_transactions/3
- Tink.Connector.batch_delete_transactions/2
- Tink.Connector.batch_update_transactions/2
- Tink.Connector.upsert_transactions_v2/2
- Tink.Connector.get_operation/2
- Tink.Connector.poll_operation/3

**Webhooks (completed)**
- Tink.Webhooks — create, list, get, update, delete webhook endpoints
- Tink.WebhookHandler — event registry with GenServer dispatcher, known_events/0
- Tink.WebhookVerifier — verify/3, verify_with_config/2, verify_plug/2

**New: Infrastructure modules**
- Tink.ReportJobs — get, poll_until_complete
- Tink.TransactionReports — get
- Tink.Merchants — create, list, get
- Tink.Paginator — stream/2, collect_all/2

**Infrastructure improvements**
- Full-jitter exponential backoff retry on 429/503/network errors
- Telemetry events: [:tink, :request, :start/stop], [:tink, :cache, :hit/miss]
- Tink.Client.expired?/1 for token lifetime checks
- Tink.Client.add_query/2 utility for building query strings

### Fixed
- License: unified to Apache-2.0 throughout (README, mix.exs, LICENSE)
- Tink.Users.create_authorization/2 removed (use Tink.Auth.create_authorization/2)
- Transactions module split collapsed — single Tink.Transactions with pagination options

---

## [0.1.1] - 2024-11-01

Initial published release.
