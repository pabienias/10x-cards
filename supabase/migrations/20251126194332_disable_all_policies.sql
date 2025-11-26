-- ============================================================================
-- Migration: Disable All RLS Policies
-- ============================================================================
-- Description: Drops all RLS policies created in the initial schema migration
-- Purpose: Disable security policies for development/testing
-- Created: 2025-11-26
--
-- WARNING: This will remove all Row Level Security policies!
-- After running this migration, all tables will be accessible to all roles
-- unless RLS is also disabled on the tables themselves.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Drop RLS Policies for: cards
-- ----------------------------------------------------------------------------

drop policy if exists cards_select_policy on public.cards;
drop policy if exists cards_select_service_policy on public.cards;
drop policy if exists cards_insert_policy on public.cards;
drop policy if exists cards_update_policy on public.cards;

-- ----------------------------------------------------------------------------
-- Drop RLS Policies for: generation_requests
-- ----------------------------------------------------------------------------

drop policy if exists generation_requests_select_policy on public.generation_requests;
drop policy if exists generation_requests_select_service_policy on public.generation_requests;
drop policy if exists generation_requests_insert_policy on public.generation_requests;
drop policy if exists generation_requests_update_policy on public.generation_requests;
drop policy if exists generation_requests_update_service_policy on public.generation_requests;

-- ----------------------------------------------------------------------------
-- Drop RLS Policies for: review_logs
-- ----------------------------------------------------------------------------

drop policy if exists review_logs_select_policy on public.review_logs;
drop policy if exists review_logs_select_service_policy on public.review_logs;
drop policy if exists review_logs_insert_policy on public.review_logs;

-- ----------------------------------------------------------------------------
-- Drop RLS Policies for: token_usage
-- ----------------------------------------------------------------------------

drop policy if exists token_usage_select_policy on public.token_usage;
drop policy if exists token_usage_select_service_policy on public.token_usage;
drop policy if exists token_usage_insert_policy on public.token_usage;
drop policy if exists token_usage_update_policy on public.token_usage;
drop policy if exists token_usage_update_service_policy on public.token_usage;

-- ----------------------------------------------------------------------------
-- Drop RLS Policies for: analytics_events
-- ----------------------------------------------------------------------------

drop policy if exists analytics_events_select_policy on public.analytics_events;
drop policy if exists analytics_events_select_service_policy on public.analytics_events;
drop policy if exists analytics_events_insert_policy on public.analytics_events;
drop policy if exists analytics_events_insert_service_policy on public.analytics_events;
drop policy if exists analytics_events_delete_service_policy on public.analytics_events;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- All RLS policies have been dropped.
--
-- Note: RLS is still ENABLED on the tables. The tables still have:
--   alter table ... enable row level security;
--
-- If you want to completely disable RLS (not recommended for production):
--   alter table public.cards disable row level security;
--   alter table public.generation_requests disable row level security;
--   alter table public.review_logs disable row level security;
--   alter table public.token_usage disable row level security;
--   alter table public.analytics_events disable row level security;
--
-- To re-enable policies, you would need to recreate them using the
-- policy definitions from migration: 20251126143000_create_initial_schema.sql
-- ============================================================================

