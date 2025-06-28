-- migration: create user favorite words table
-- description: creates a table to store users' favorite words, linking auth.users and public.words.
-- affected tables: auth.users, public.words, public.user_favorite_words
-- author: database administrator
-- date: 2025-11-10

-- create the user_favorite_words table
create table public.user_favorite_words (
  user_id uuid not null,
  word_id uuid not null,
  created_at timestamptz not null default now(),
  constraint user_favorite_words_pkey primary key (user_id, word_id),
  constraint user_favorite_words_user_id_fk foreign key (user_id) references auth.users(id) on delete cascade,
  constraint user_favorite_words_word_id_fk foreign key (word_id) references public.words(id) on delete cascade
);

-- enable row level security on the table
alter table public.user_favorite_words enable row level security;

-- create rls policy for select: allow authenticated users to view their own favorite words
create policy "authenticated users can view favorite words"
    on public.user_favorite_words
    for select
    to authenticated
    using (auth.uid() = user_id);

-- create rls policy for insert: allow authenticated users to insert favorite words only for themselves
create policy "authenticated users can insert favorite words"
    on public.user_favorite_words
    for insert
    to authenticated
    with check (auth.uid() = user_id);

-- create rls policy for delete: allow authenticated users to delete their favorite words
create policy "authenticated users can delete favorite words"
    on public.user_favorite_words
    for delete
    to authenticated
    using (auth.uid() = user_id); 