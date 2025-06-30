-- Migration: Disable Row Level Security
-- Description: Disables RLS on all tables in the schema
-- Author: Database Administrator
-- Date: 2025-05-10

-- Disable RLS on UserProfiles table
alter table public.user_profiles disable row level security;

-- Disable RLS on Words table
alter table public.words disable row level security;

-- Disable RLS on WordForms table
alter table public.word_forms disable row level security;

-- Disable RLS on Dialects table
alter table public.dialects disable row level security;

-- Disable RLS on WordFormDialects table
alter table public.word_form_dialects disable row level security; 