/*
 * Migration: Add initial dummy data for testing
 * Description: Populates the database with sample data for development and testing purposes
 * Tables affected: dialects, auth.users, user_profiles, words, word_forms, word_form_dialects
 * Author: System
 * Date: 2025-05-12
 */

-- Enable UUID generation if not already enabled
create extension if not exists "uuid-ossp";

-- Create test users using Supabase's auth.users() function
do $$
declare
    user1_id uuid;
    user2_id uuid;
begin
    -- Create first test user
    user1_id := (select id from auth.users where email = 'test1@example.com');
    if user1_id is null then
        user1_id := gen_random_uuid();
        insert into auth.users (id, email, email_confirmed_at, encrypted_password, raw_app_meta_data, raw_user_meta_data)
        values (
            user1_id,
            'test1@example.com',
            now(),
            crypt('password123', gen_salt('bf')),
            '{"provider":"email","providers":["email"]}',
            '{}'
        );
    end if;

    -- Create second test user
    user2_id := (select id from auth.users where email = 'test2@example.com');
    if user2_id is null then
        user2_id := gen_random_uuid();
        insert into auth.users (id, email, email_confirmed_at, encrypted_password, raw_app_meta_data, raw_user_meta_data)
        values (
            user2_id,
            'test2@example.com',
            now(),
            crypt('password123', gen_salt('bf')),
            '{"provider":"email","providers":["email"]}',
            '{}'
        );
    end if;
end $$;

-- Seed dialects with common Arabic variants
insert into public.dialects (id, name, country_code, created_at, updated_at)
values
    (uuid_generate_v4(), 'egyptian arabic', 'eg', now(), now()),
    (uuid_generate_v4(), 'levantine arabic', 'lb', now(), now()),
    (uuid_generate_v4(), 'gulf arabic', 'sa', now(), now());

-- Create user profiles for test users
insert into public.user_profiles (user_id, has_offline_dictionary_access, subscription_valid_until, created_at, updated_at)
select 
    id as user_id,
    case when email = 'test1@example.com' then true else false end as has_offline_dictionary_access,
    case when email = 'test1@example.com' then now() + interval '1 year' else null end as subscription_valid_until,
    now() as created_at,
    now() as updated_at
from auth.users
where email in ('test1@example.com', 'test2@example.com')
on conflict (user_id) do nothing;

-- Seed basic Arabic vocabulary words
insert into public.words (id, english_term, english_definition, primary_arabic_script, part_of_speech, general_frequency_tag, created_at, updated_at)
values
    (uuid_generate_v4(), 'hello', 'a greeting', 'مرحبا', 'Interjection', 'VERY_FREQUENT', now(), now()),
    (uuid_generate_v4(), 'book', 'a written or printed work', 'كتاب', 'Noun', 'COMMON', now(), now()),
    (uuid_generate_v4(), 'to write', 'to form letters or words on a surface', 'كتب', 'Verb', 'FREQUENT', now(), now())
returning id, english_term;

-- Add word forms with proper transliterations
with inserted_words as (
    select id, english_term 
    from public.words 
    where english_term in ('hello', 'book', 'to write')
)
insert into public.word_forms (id, word_id, transliteration, arabic_script_variant, conjugation_details, audio_url, created_at, updated_at)
select 
    uuid_generate_v4(),
    w.id,
    case 
        when w.english_term = 'hello' then 'marhaba'
        when w.english_term = 'book' then 'kitab'
        when w.english_term = 'to write' then 'kataba'
    end,
    case 
        when w.english_term = 'hello' then 'مرحبا'
        when w.english_term = 'book' then 'كتاب'
        when w.english_term = 'to write' then 'كَتَبَ'
    end,
    '{}'::jsonb,
    null,
    now(),
    now()
from inserted_words w;

-- Associate word forms with dialects
with word_forms_data as (
    select wf.id as word_form_id, d.id as dialect_id
    from public.word_forms wf
    cross join public.dialects d
    limit 5
)
insert into public.word_form_dialects (word_form_id, dialect_id)
select word_form_id, dialect_id
from word_forms_data
on conflict do nothing; 