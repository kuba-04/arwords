-- Migration: Initial Schema Creation
-- Description: Creates the initial database schema for the Arabic Words application
-- Tables: UserProfiles, Words, WordForms, Dialects, WordFormDialects
-- Author: Database Administrator
-- Date: 2025-05-10

-- Enable UUID extension if not already enabled
create extension if not exists "uuid-ossp";

-- Create ENUM type for frequency tags
create type frequency_tag as enum (
    'VERY_FREQUENT',
    'FREQUENT',
    'COMMON',
    'UNCOMMON',
    'RARE',
    'NOT_DEFINED'
);

-- Create UserProfiles table
create table user_profiles (
    user_id uuid primary key references auth.users(id),
    has_offline_dictionary_access boolean not null default false,
    subscription_valid_until timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Enable RLS on UserProfiles
alter table user_profiles enable row level security;

-- RLS Policies for UserProfiles
-- Allow authenticated users to view their own profile
create policy "Users can view own profile"
    on user_profiles
    for select
    to authenticated
    using (auth.uid() = user_id);

-- Allow authenticated users to update their own profile
create policy "Users can update own profile"
    on user_profiles
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Create Words table
create table words (
    id uuid primary key default uuid_generate_v4(),
    english_term varchar(30) not null,
    primary_arabic_script varchar(30) not null,
    part_of_speech varchar(30) not null,
    english_definition text,
    general_frequency_tag frequency_tag not null default 'NOT_DEFINED',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    -- Add unique constraints
    constraint unique_english_term_pos unique (english_term, part_of_speech),
    constraint unique_primary_arabic unique (primary_arabic_script),
    -- Validate part_of_speech values
    constraint valid_part_of_speech check (
        part_of_speech in (
            'Noun', 'Verb', 'Adjective', 'Adverb',
            'Pronoun', 'Preposition', 'Conjunction', 'Interjection'
        )
    )
);

-- Enable RLS on Words
alter table words enable row level security;

-- RLS Policies for Words
-- Allow public read access for authenticated users
create policy "Authenticated users can view words"
    on words
    for select
    to authenticated
    using (true);

-- Allow admin/editor roles to modify words
create policy "Admin/editors can modify words"
    on words
    for all
    to authenticated
    using (current_setting('app.current_role') in ('admin', 'editor'))
    with check (current_setting('app.current_role') in ('admin', 'editor'));

-- Create WordForms table
create table word_forms (
    id uuid primary key default uuid_generate_v4(),
    word_id uuid not null references words(id) on delete restrict,
    arabic_script_variant varchar(30),
    transliteration varchar(30) not null,
    conjugation_details text not null,
    audio_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Enable RLS on WordForms
alter table word_forms enable row level security;

-- RLS Policies for WordForms
-- Allow public read access for authenticated users
create policy "Authenticated users can view word forms"
    on word_forms
    for select
    to authenticated
    using (true);

-- Allow admin/editor roles to modify word forms
create policy "Admin/editors can modify word forms"
    on word_forms
    for all
    to authenticated
    using (current_setting('app.current_role') in ('admin', 'editor'))
    with check (current_setting('app.current_role') in ('admin', 'editor'));

-- Create Dialects table
create table dialects (
    id uuid primary key default uuid_generate_v4(),
    name varchar(30) not null unique,
    country_code varchar(10) not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Enable RLS on Dialects
alter table dialects enable row level security;

-- RLS Policies for Dialects
-- Allow public read access for authenticated users
create policy "Authenticated users can view dialects"
    on dialects
    for select
    to authenticated
    using (true);

-- Allow admin/editor roles to modify dialects
create policy "Admin/editors can modify dialects"
    on dialects
    for all
    to authenticated
    using (current_setting('app.current_role') in ('admin', 'editor'))
    with check (current_setting('app.current_role') in ('admin', 'editor'));

-- Create WordFormDialects junction table
create table word_form_dialects (
    word_form_id uuid not null references word_forms(id) on delete restrict,
    dialect_id uuid not null references dialects(id) on delete restrict,
    primary key (word_form_id, dialect_id)
);

-- Enable RLS on WordFormDialects
alter table word_form_dialects enable row level security;

-- RLS Policies for WordFormDialects
-- Allow public read access for authenticated users
create policy "Authenticated users can view word form dialects"
    on word_form_dialects
    for select
    to authenticated
    using (true);

-- Allow admin/editor roles to modify word form dialects
create policy "Admin/editors can modify word form dialects"
    on word_form_dialects
    for all
    to authenticated
    using (current_setting('app.current_role') in ('admin', 'editor'))
    with check (current_setting('app.current_role') in ('admin', 'editor'));

-- Create indexes for performance optimization
create index idx_words_english_term on words(english_term);
create index idx_words_frequency_tag on words(general_frequency_tag);
create index idx_word_forms_transliteration on word_forms(transliteration);
create index idx_word_forms_word_id on word_forms(word_id);
create index idx_word_form_dialects_word_form_id on word_form_dialects(word_form_id);
create index idx_word_form_dialects_dialect_id on word_form_dialects(dialect_id);

-- Create trigger function for updating timestamps
create or replace function update_updated_at_column()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

-- Create triggers for updating timestamps
create trigger update_user_profiles_updated_at
    before update on user_profiles
    for each row
    execute function update_updated_at_column();

create trigger update_words_updated_at
    before update on words
    for each row
    execute function update_updated_at_column();

create trigger update_word_forms_updated_at
    before update on word_forms
    for each row
    execute function update_updated_at_column();

create trigger update_dialects_updated_at
    before update on dialects
    for each row
    execute function update_updated_at_column(); 