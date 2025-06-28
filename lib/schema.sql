-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.dialects (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name character varying NOT NULL UNIQUE,
  country_code character varying NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT dialects_pkey PRIMARY KEY (id)
);
CREATE TABLE public.user_profiles (
  user_id uuid NOT NULL,
  has_offline_dictionary_access boolean NOT NULL DEFAULT false,
  subscription_valid_until timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT user_profiles_pkey PRIMARY KEY (user_id),
  CONSTRAINT user_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
CREATE TABLE public.word_form_dialects (
  word_form_id uuid NOT NULL,
  dialect_id uuid NOT NULL,
  CONSTRAINT word_form_dialects_pkey PRIMARY KEY (word_form_id, dialect_id),
  CONSTRAINT word_form_dialects_dialect_id_fkey FOREIGN KEY (dialect_id) REFERENCES public.dialects(id),
  CONSTRAINT word_form_dialects_word_form_id_fkey FOREIGN KEY (word_form_id) REFERENCES public.word_forms(id)
);
CREATE TABLE public.word_forms (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  word_id uuid NOT NULL,
  arabic_script_variant character varying,
  transliteration character varying NOT NULL,
  conjugation_details text NOT NULL,
  audio_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT word_forms_pkey PRIMARY KEY (id),
  CONSTRAINT word_forms_word_id_fkey FOREIGN KEY (word_id) REFERENCES public.words(id)
);
CREATE TABLE public.words (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  english_term character varying NOT NULL,
  primary_arabic_script character varying NOT NULL UNIQUE,
  part_of_speech character varying NOT NULL CHECK (part_of_speech::text = ANY (ARRAY['Noun'::character varying::text, 'Verb'::character varying::text, 'Adjective'::character varying::text, 'Adverb'::character varying::text, 'Pronoun'::character varying::text, 'Preposition'::character varying::text, 'Conjunction'::character varying::text, 'Interjection'::character varying::text])),
  english_definition text,
  general_frequency_tag USER-DEFINED NOT NULL DEFAULT 'NOT_DEFINED'::frequency_tag,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT words_pkey PRIMARY KEY (id)
);
CREATE TABLE public.user_favorite_words (
  user_id uuid NOT NULL,
  word_id uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT user_favorite_words_pkey PRIMARY KEY (user_id, word_id),
  CONSTRAINT user_favorite_words_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT user_favorite_words_word_id_fkey FOREIGN KEY (word_id) REFERENCES public.words(id)
);