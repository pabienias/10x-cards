-- ============================================================================
-- Migration: Initial Database Schema for 10xCards
-- ============================================================================
-- Purpose: Create complete database schema including:
--   - Tables: cards, generation_requests, review_logs, token_usage, analytics_events
--   - Indexes: Optimized for common query patterns with partial indexes
--   - RLS Policies: User-scoped access control with service_role exceptions
--   - Functions: Auto-update triggers and maintenance utilities
--   - Triggers: Automated updated_at and soft-delete validation
--
-- Affected Tables: All application tables (new)
-- Dependencies: Requires auth.users (managed by Supabase)
--
-- Special Considerations:
--   - Soft-delete pattern implemented for cards table
--   - Composite foreign key in review_logs ensures user data integrity
--   - Token usage table uses composite primary key for efficient UPSERT
--   - Analytics events have 90-day retention policy
--   - All timestamps use timestamptz (UTC) for timezone consistency
--
-- Author: AI Architect + Piotrek
-- Date: 2025-11-26
-- Version: 1.0
-- ============================================================================

-- ============================================================================
-- SECTION 1: TABLES WITHOUT FOREIGN KEYS TO OTHER APPLICATION TABLES
-- ============================================================================
-- These tables are created first as they are referenced by other tables
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: generation_requests
-- ----------------------------------------------------------------------------
-- Purpose: Telemetry and history of AI flashcard generation requests
-- Dependencies: auth.users (Supabase managed)
-- Notes: Tracks model used, status, timing, and acceptance metrics
-- ----------------------------------------------------------------------------

create table public.generation_requests (
  -- primary key
  id uuid primary key default gen_random_uuid(),
  
  -- foreign keys
  user_id uuid not null references auth.users(id) on delete cascade,
  
  -- generation metadata
  model text not null,
  status text not null check (status in ('success', 'partial', 'cancelled', 'error')),
  
  -- timing metrics
  started_at timestamptz not null default now(),
  computation_time_ms integer check (computation_time_ms >= 0),
  
  -- count metrics (after deduplication, max 10 candidates)
  generated_count integer not null default 0 check (generated_count >= 0),
  accepted_unedited_count integer not null default 0 check (accepted_unedited_count >= 0),
  accepted_edited_count integer not null default 0 check (accepted_edited_count >= 0),
  
  -- error tracking
  error_code text
);

-- add table comment
comment on table public.generation_requests is 'Historia i telemetria żądań generacji fiszek przez AI';

-- add column comments
comment on column public.generation_requests.model is 'Identyfikator modelu AI użytego do generacji';
comment on column public.generation_requests.status is 'Status generacji: success, partial, cancelled, error';
comment on column public.generation_requests.computation_time_ms is 'Całkowity czas obliczeń w milisekundach';
comment on column public.generation_requests.generated_count is 'Liczba wygenerowanych kandydatów (po deduplikacji, max 10)';
comment on column public.generation_requests.accepted_unedited_count is 'Liczba zaakceptowanych fiszek bez edycji';
comment on column public.generation_requests.accepted_edited_count is 'Liczba zaakceptowanych fiszek po edycji';

-- ----------------------------------------------------------------------------
-- Table: token_usage
-- ----------------------------------------------------------------------------
-- Purpose: Daily token usage tracking per user (500k tokens/day limit)
-- Dependencies: auth.users (Supabase managed)
-- Notes: Composite primary key (user_id, date_utc) enables efficient UPSERT
-- ----------------------------------------------------------------------------

create table public.token_usage (
  -- composite primary key (enables UPSERT per user per day)
  user_id uuid not null references auth.users(id) on delete cascade,
  date_utc date not null,
  
  -- usage metrics
  tokens_used_total bigint not null default 0 check (tokens_used_total >= 0),
  
  -- define composite primary key
  primary key (user_id, date_utc)
);

-- add table comment
comment on table public.token_usage is 'Zliczanie wykorzystania tokenów AI per użytkownik per dzień UTC';

-- add column comments
comment on column public.token_usage.date_utc is 'Data UTC (bez czasu)';
comment on column public.token_usage.tokens_used_total is 'Suma tokenów (prompt + completion) zużytych danego dnia';

-- ============================================================================
-- SECTION 2: TABLES WITH FOREIGN KEYS TO APPLICATION TABLES
-- ============================================================================
-- These tables depend on tables created in Section 1
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: cards
-- ----------------------------------------------------------------------------
-- Purpose: Main flashcard storage (AI-generated and manual)
-- Dependencies: auth.users, generation_requests
-- Notes: 
--   - Implements soft-delete pattern (deleted_at column)
--   - Origin field determines required fields (ai vs manual)
--   - Unique constraint on (id, user_id) required for review_logs FK
-- ----------------------------------------------------------------------------

create table public.cards (
  -- primary key
  id uuid primary key default gen_random_uuid(),
  
  -- foreign keys
  user_id uuid not null references auth.users(id) on delete cascade,
  generation_request_id uuid references public.generation_requests(id),
  
  -- card metadata
  origin text not null check (origin in ('ai', 'manual')),
  source_language text,
  
  -- card content (with length constraints per PRD)
  front_text text not null check (length(front_text) > 0 and length(front_text) <= 200),
  back_text text not null check (length(back_text) > 0 and length(back_text) <= 500),
  
  -- timestamps
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  
  -- soft-delete marker (null = active, not null = deleted)
  deleted_at timestamptz,
  
  -- constraint: ensure consistency between origin and related fields
  constraint cards_ai_fields_check check (
    (origin = 'ai' and source_language is not null and generation_request_id is not null and accepted_at is not null)
    or
    (origin = 'manual' and source_language is null and generation_request_id is null and accepted_at is null)
  ),
  
  -- unique constraint required for composite FK in review_logs
  unique (id, user_id)
);

-- add table comment
comment on table public.cards is 'Fiszki użytkowników - zarówno wygenerowane przez AI jak i utworzone manualnie';

-- add column comments
comment on column public.cards.origin is 'Źródło fiszki: ai (generowana) lub manual (ręczna)';
comment on column public.cards.front_text is 'Przód fiszki (pytanie), max 200 znaków';
comment on column public.cards.back_text is 'Tył fiszki (odpowiedź), max 500 znaków';
comment on column public.cards.source_language is 'Język źródłowy (wymagany dla AI, NULL dla manual)';
comment on column public.cards.generation_request_id is 'FK do generation_requests (tylko dla origin=ai)';
comment on column public.cards.accepted_at is 'Timestamp akceptacji fiszki AI (tylko dla origin=ai)';
comment on column public.cards.deleted_at is 'Soft-delete: NULL = aktywna, NOT NULL = usunięta';

-- ============================================================================
-- SECTION 3: DEPENDENT TABLES
-- ============================================================================
-- These tables have foreign keys to tables created in previous sections
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: review_logs
-- ----------------------------------------------------------------------------
-- Purpose: History of flashcard reviews during SRS learning sessions
-- Dependencies: auth.users, cards
-- Notes:
--   - Composite FK (card_id, user_id) ensures users can only review own cards
--   - ON DELETE RESTRICT enforces soft-delete pattern (can't delete cards with history)
--   - SRS fields (interval, ease) are NULL in MVP, ready for future implementation
--   - Append-only table (no updates after creation)
-- ----------------------------------------------------------------------------

create table public.review_logs (
  -- primary key
  id uuid primary key default gen_random_uuid(),
  
  -- foreign keys
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id uuid not null,
  
  -- review metadata
  rating text not null check (rating in ('again', 'hard', 'good', 'easy')),
  reviewed_at timestamptz not null default now(),
  
  -- srs state tracking (null in mvp, ready for future srs implementation)
  interval_days_before integer check (interval_days_before >= 0),
  interval_days_after integer check (interval_days_after >= 0),
  ease_before numeric(5,2) check (ease_before >= 1.0),
  ease_after numeric(5,2) check (ease_after >= 1.0),
  
  -- composite foreign key ensures user can only review own cards
  -- on delete restrict enforces soft-delete (cannot physically delete cards with review history)
  foreign key (card_id, user_id) references public.cards(id, user_id) on delete restrict
);

-- add table comment
comment on table public.review_logs is 'Historia ocen fiszek podczas sesji nauki (spaced repetition)';

-- add column comments
comment on column public.review_logs.rating is 'Ocena trudności: again, hard, good, easy';
comment on column public.review_logs.interval_days_before is 'Interwał w dniach przed oceną (NULL w MVP)';
comment on column public.review_logs.interval_days_after is 'Interwał w dniach po ocenie (NULL w MVP)';
comment on column public.review_logs.ease_before is 'Współczynnik łatwości przed oceną (NULL w MVP)';
comment on column public.review_logs.ease_after is 'Współczynnik łatwości po ocenie (NULL w MVP)';

-- ----------------------------------------------------------------------------
-- Table: analytics_events
-- ----------------------------------------------------------------------------
-- Purpose: Product analytics events (90-day retention)
-- Dependencies: auth.users, cards, generation_requests
-- Notes:
--   - ON DELETE SET NULL preserves events even after entity deletion (audit trail)
--   - JSONB properties_json allows flexible event metadata
--   - Retention policy handled by cleanup function (scheduled daily)
-- ----------------------------------------------------------------------------

create table public.analytics_events (
  -- primary key
  id uuid primary key default gen_random_uuid(),
  
  -- foreign keys
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id uuid references public.cards(id) on delete set null,
  generation_request_id uuid references public.generation_requests(id) on delete set null,
  
  -- event metadata
  event_name text not null check (event_name in ('card_accepted', 'card_rejected')),
  occurred_at timestamptz not null default now(),
  
  -- flexible event properties (jsonb for efficient querying)
  properties_json jsonb
);

-- add table comment
comment on table public.analytics_events is 'Zdarzenia analityczne dla metryk produktowych (retencja 90 dni)';

-- add column comments
comment on column public.analytics_events.event_name is 'Typ zdarzenia: card_accepted, card_rejected';
comment on column public.analytics_events.properties_json is 'Dodatkowe właściwości zdarzenia w formacie JSON';

-- ============================================================================
-- SECTION 4: INDEXES
-- ============================================================================
-- Performance optimization indexes for common query patterns
-- Partial indexes used where applicable to reduce index size
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Indexes for: cards
-- ----------------------------------------------------------------------------

-- main index for user's card list with pagination (keyset pagination support)
create index idx_cards_user_date_active 
  on public.cards (user_id, coalesce(accepted_at, created_at) desc, id desc) 
  where deleted_at is null;

-- quick filtering of active cards per user (counting, simple lists)
create index idx_cards_user_active 
  on public.cards (user_id) 
  where deleted_at is null;

-- find cards from specific generation request (stats and generation details)
create index idx_cards_generation_request 
  on public.cards (generation_request_id) 
  where deleted_at is null and origin = 'ai';

-- optimize queries for soft-deleted cards (audit, analysis, potential admin restore)
create index idx_cards_deleted_at 
  on public.cards (deleted_at) 
  where deleted_at is not null;

-- ----------------------------------------------------------------------------
-- Indexes for: generation_requests
-- ----------------------------------------------------------------------------

-- user's generation history sorted chronologically (dashboard, user stats)
create index idx_generation_requests_user_started 
  on public.generation_requests (user_id, started_at desc);

-- analyze generation statuses (monitoring errors, partial results, success rate)
create index idx_generation_requests_status 
  on public.generation_requests (status, started_at desc);

-- ----------------------------------------------------------------------------
-- Indexes for: review_logs
-- ----------------------------------------------------------------------------

-- user's review history sorted chronologically (learning stats, activity timeline)
create index idx_review_logs_user_reviewed 
  on public.review_logs (user_id, reviewed_at desc);

-- review history for specific card (card details, progress tracking)
create index idx_review_logs_card 
  on public.review_logs (card_id, reviewed_at desc);

-- analyze ratings (how many again/hard/good/easy, identify difficult cards)
create index idx_review_logs_rating 
  on public.review_logs (rating, reviewed_at desc);

-- ----------------------------------------------------------------------------
-- Indexes for: token_usage
-- ----------------------------------------------------------------------------

-- note: composite primary key (user_id, date_utc) automatically creates an index
-- additional index may not be needed, but included for explicit query optimization

-- check daily limit and user's token usage history
create index idx_token_usage_user_date 
  on public.token_usage (user_id, date_utc desc);

-- ----------------------------------------------------------------------------
-- Indexes for: analytics_events
-- ----------------------------------------------------------------------------

-- filter user events by type and date (user stats, acceptance/rejection analysis)
create index idx_analytics_events_user_name_occurred 
  on public.analytics_events (user_id, event_name, occurred_at desc);

-- retention task - quickly delete events older than 90 days
create index idx_analytics_events_occurred 
  on public.analytics_events (occurred_at);

-- analyze events related to specific card (card timeline, audit)
create index idx_analytics_events_card 
  on public.analytics_events (card_id, occurred_at desc) 
  where card_id is not null;

-- analyze events related to specific generation request (success rate per request)
create index idx_analytics_events_generation 
  on public.analytics_events (generation_request_id, occurred_at desc) 
  where generation_request_id is not null;

-- optional: gin index for jsonb properties (add only if needed for filtering/searching)
-- create index idx_analytics_events_properties 
--   on public.analytics_events using gin (properties_json);

-- ============================================================================
-- SECTION 5: FUNCTIONS
-- ============================================================================
-- Helper functions for triggers and maintenance tasks
-- Must be created before triggers that reference them
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Function: update_updated_at_column
-- ----------------------------------------------------------------------------
-- Purpose: Automatically set updated_at to current timestamp on row update
-- Used by: cards_updated_at_trigger (and potentially other tables in future)
-- Notes: Generic function, can be reused for any table with updated_at column
-- ----------------------------------------------------------------------------

create or replace function public.update_updated_at_column()
returns trigger
language plpgsql
as $$
begin
  -- set updated_at to current timestamp
  new.updated_at = now();
  return new;
end;
$$;

-- add function comment
comment on function public.update_updated_at_column is 'Automatycznie aktualizuje kolumnę updated_at przy każdej modyfikacji rekordu';

-- ----------------------------------------------------------------------------
-- Function: validate_card_soft_delete
-- ----------------------------------------------------------------------------
-- Purpose: Enforce soft-delete business rules for cards table
-- Used by: cards_soft_delete_trigger
-- Rules:
--   1. Cannot restore soft-deleted cards (create new card instead)
--   2. Cannot modify other fields during soft-delete operation
-- Notes: Ensures data integrity and prevents accidental data corruption
-- ----------------------------------------------------------------------------

create or replace function public.validate_card_soft_delete()
returns trigger
language plpgsql
as $$
begin
  -- rule 1: prevent restoring soft-deleted cards
  -- rationale: restoring could cause integrity issues with review_logs FK
  -- better to create a new card if user wants to "restore" content
  if old.deleted_at is not null and new.deleted_at is null then
    raise exception 'Cannot restore soft-deleted cards. Create a new card instead.';
  end if;
  
  -- rule 2: prevent modifying fields during soft-delete operation
  -- rationale: soft-delete should be atomic operation on deleted_at only
  -- concurrent changes to content fields could cause inconsistencies
  if new.deleted_at is not null and old.deleted_at is null then
    -- check if any field other than deleted_at and updated_at was changed
    if (
      old.origin is distinct from new.origin or
      old.front_text is distinct from new.front_text or
      old.back_text is distinct from new.back_text or
      old.source_language is distinct from new.source_language or
      old.generation_request_id is distinct from new.generation_request_id or
      old.accepted_at is distinct from new.accepted_at or
      old.created_at is distinct from new.created_at
    ) then
      raise exception 'Cannot modify card fields during soft-delete operation';
    end if;
  end if;
  
  -- validation passed, return modified row
  return new;
end;
$$;

-- add function comment
comment on function public.validate_card_soft_delete is 'Waliduje operacje soft-delete: blokuje przywracanie i edycję podczas usuwania';

-- ----------------------------------------------------------------------------
-- Function: cleanup_old_analytics_events
-- ----------------------------------------------------------------------------
-- Purpose: Delete analytics events older than 90 days (retention policy)
-- Schedule: Daily at 2:00 UTC (via external cron or pg_cron)
-- Notes: 
--   - SECURITY DEFINER allows execution with creator's privileges (bypasses RLS)
--   - Required for DELETE operation despite RLS policies
--   - Monitor execution time - may need batching for large datasets
-- ----------------------------------------------------------------------------

create or replace function public.cleanup_old_analytics_events()
returns void
language plpgsql
security definer
as $$
begin
  -- delete events older than 90 days (retention policy per PRD)
  delete from public.analytics_events
  where occurred_at < now() - interval '90 days';
  
  -- note: execution time should be monitored
  -- if > 5s with large datasets, consider:
  --   1. table partitioning by occurred_at (monthly/quarterly)
  --   2. batched deletion (delete in chunks with limit)
  --   3. drop partition instead of delete (if partitioned)
end;
$$;

-- add function comment
comment on function public.cleanup_old_analytics_events is 'Usuwa zdarzenia analityczne starsze niż 90 dni (polityka retencji)';

-- ============================================================================
-- SECTION 6: TRIGGERS
-- ============================================================================
-- Automated triggers for business logic enforcement
-- Depend on functions created in Section 5
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Trigger: cards_updated_at_trigger
-- ----------------------------------------------------------------------------
-- Purpose: Automatically update updated_at timestamp on any card modification
-- Timing: BEFORE UPDATE (modifies NEW record before write)
-- Notes: Fires for all updates including soft-delete operations
-- ----------------------------------------------------------------------------

create trigger cards_updated_at_trigger
  before update on public.cards
  for each row
  execute function public.update_updated_at_column();

-- ----------------------------------------------------------------------------
-- Trigger: cards_soft_delete_trigger
-- ----------------------------------------------------------------------------
-- Purpose: Validate soft-delete operations (no restore, no concurrent edits)
-- Timing: BEFORE UPDATE (validates before write, can raise exception)
-- Notes: Fires before cards_updated_at_trigger (alphabetical order)
-- ----------------------------------------------------------------------------

create trigger cards_soft_delete_trigger
  before update on public.cards
  for each row
  execute function public.validate_card_soft_delete();

-- ============================================================================
-- SECTION 7: ROW LEVEL SECURITY (RLS)
-- ============================================================================
-- Security policies to ensure users can only access their own data
-- Service role has unrestricted access for system operations
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Enable RLS on all application tables
-- ----------------------------------------------------------------------------
-- CRITICAL: RLS must be enabled before creating policies
-- Even for tables intended for public access, RLS should be enabled with
-- appropriate policies returning true
-- ----------------------------------------------------------------------------

alter table public.cards enable row level security;
alter table public.generation_requests enable row level security;
alter table public.review_logs enable row level security;
alter table public.token_usage enable row level security;
alter table public.analytics_events enable row level security;

-- ----------------------------------------------------------------------------
-- RLS Policies for: cards
-- ----------------------------------------------------------------------------
-- Security model:
--   - authenticated users: can only access their own active cards
--   - service_role: full access including soft-deleted (for admin/audit)
--   - no physical DELETE for authenticated (soft-delete only via UPDATE)
-- ----------------------------------------------------------------------------

-- policy: authenticated users can select their own active cards
create policy cards_select_policy
  on public.cards
  for select
  to authenticated
  using (user_id = auth.uid() and deleted_at is null);

-- policy: service_role can select all cards including soft-deleted
create policy cards_select_service_policy
  on public.cards
  for select
  to service_role
  using (true);

-- policy: authenticated users can insert cards with their own user_id
create policy cards_insert_policy
  on public.cards
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- policy: authenticated users can update their own active cards
-- note: soft-delete uses update (setting deleted_at)
create policy cards_update_policy
  on public.cards
  for update
  to authenticated
  using (user_id = auth.uid() and deleted_at is null)
  with check (user_id = auth.uid());

-- note: no delete policy for authenticated users - only soft-delete via update
-- physical delete only available to service_role (implicit through lack of policy)

-- ----------------------------------------------------------------------------
-- RLS Policies for: generation_requests
-- ----------------------------------------------------------------------------
-- Security model:
--   - authenticated users: can only access their own generation requests
--   - service_role: full access for monitoring and analytics
-- ----------------------------------------------------------------------------

-- policy: authenticated users can select their own generation requests
create policy generation_requests_select_policy
  on public.generation_requests
  for select
  to authenticated
  using (user_id = auth.uid());

-- policy: service_role can select all generation requests
create policy generation_requests_select_service_policy
  on public.generation_requests
  for select
  to service_role
  using (true);

-- policy: authenticated users can insert their own generation requests
create policy generation_requests_insert_policy
  on public.generation_requests
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- policy: authenticated users can update their own generation requests
-- use case: updating counters after card acceptance
create policy generation_requests_update_policy
  on public.generation_requests
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- policy: service_role can update all generation requests
-- use case: corrections, migrations, system operations
create policy generation_requests_update_service_policy
  on public.generation_requests
  for update
  to service_role
  using (true);

-- ----------------------------------------------------------------------------
-- RLS Policies for: review_logs
-- ----------------------------------------------------------------------------
-- Security model:
--   - authenticated users: can only access their own review logs
--   - append-only for authenticated (no update/delete after creation)
--   - service_role: full access for analytics and research
-- ----------------------------------------------------------------------------

-- policy: authenticated users can select their own review logs
create policy review_logs_select_policy
  on public.review_logs
  for select
  to authenticated
  using (user_id = auth.uid());

-- policy: service_role can select all review logs
create policy review_logs_select_service_policy
  on public.review_logs
  for select
  to service_role
  using (true);

-- policy: authenticated users can insert their own review logs
-- note: composite fk additionally enforces card_id matches user_id
create policy review_logs_insert_policy
  on public.review_logs
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- note: no update/delete policies for authenticated users
-- review logs are immutable after creation (append-only)
-- only service_role can modify (corrections, cleanup) via lack of policies

-- ----------------------------------------------------------------------------
-- RLS Policies for: token_usage
-- ----------------------------------------------------------------------------
-- Security model:
--   - authenticated users: can access their own token usage
--   - can insert/update for UPSERT operations
--   - service_role: full access for billing and limit monitoring
-- ----------------------------------------------------------------------------

-- policy: authenticated users can select their own token usage
create policy token_usage_select_policy
  on public.token_usage
  for select
  to authenticated
  using (user_id = auth.uid());

-- policy: service_role can select all token usage records
create policy token_usage_select_service_policy
  on public.token_usage
  for select
  to service_role
  using (true);

-- policy: authenticated users can insert their own token usage records
-- use case: part of upsert operation for daily token tracking
create policy token_usage_insert_policy
  on public.token_usage
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- policy: authenticated users can update their own token usage records
-- use case: part of upsert operation when incrementing daily counter
create policy token_usage_update_policy
  on public.token_usage
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- policy: service_role can update all token usage records
-- use case: corrections, resets, billing adjustments
create policy token_usage_update_service_policy
  on public.token_usage
  for update
  to service_role
  using (true);

-- ----------------------------------------------------------------------------
-- RLS Policies for: analytics_events
-- ----------------------------------------------------------------------------
-- Security model:
--   - authenticated users: can access their own events (if needed for UI)
--   - can insert their own events (emitted from frontend or API)
--   - service_role: full access for analytics, reporting, retention cleanup
-- ----------------------------------------------------------------------------

-- policy: authenticated users can select their own analytics events
-- use case: if users need to see their own activity timeline
create policy analytics_events_select_policy
  on public.analytics_events
  for select
  to authenticated
  using (user_id = auth.uid());

-- policy: service_role can select all analytics events
create policy analytics_events_select_service_policy
  on public.analytics_events
  for select
  to service_role
  using (true);

-- policy: authenticated users can insert their own analytics events
-- use case: events emitted from frontend or api endpoints
create policy analytics_events_insert_policy
  on public.analytics_events
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- policy: service_role can insert all analytics events
-- use case: system events, imports, backend-generated events
create policy analytics_events_insert_service_policy
  on public.analytics_events
  for insert
  to service_role
  with check (true);

-- policy: service_role can delete analytics events
-- use case: retention task (90-day cleanup)
create policy analytics_events_delete_service_policy
  on public.analytics_events
  for delete
  to service_role
  using (true);

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- Next steps:
--   1. Run migration: supabase db push
--   2. Verify tables created: check Supabase Studio
--   3. Test RLS policies: ensure user isolation works correctly
--   4. Setup cron job: schedule cleanup_old_analytics_events() daily at 2:00 UTC
--   5. Generate TypeScript types: supabase gen types typescript
--   6. Monitor indexes: use EXPLAIN ANALYZE for key query patterns
--
-- Rollback strategy:
--   - Drop policies first (reverse order)
--   - Drop triggers and functions
--   - Drop indexes
--   - Drop tables in reverse dependency order:
--     analytics_events, review_logs, cards, token_usage, generation_requests
-- ============================================================================

