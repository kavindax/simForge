-- SimForge database schema
-- Run this in the Supabase SQL Editor (Dashboard → SQL → New query)
-- Safe to re-run on an existing database (migrations run before indexes/policies).

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Profiles (extends auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID REFERENCES auth.users PRIMARY KEY,
  username TEXT UNIQUE,
  full_name TEXT,
  avatar_url TEXT,
  github_username TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Simulations (fresh installs get full column set)
CREATE TABLE IF NOT EXISTS public.simulations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  icon TEXT DEFAULT '🔬',
  category TEXT DEFAULT 'custom',
  code TEXT NOT NULL,
  author_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  forked_from UUID REFERENCES public.simulations(id) ON DELETE SET NULL,
  is_public BOOLEAN DEFAULT TRUE,
  is_preset BOOLEAN DEFAULT FALSE,
  preset_key TEXT,
  concepts JSONB DEFAULT '[]'::jsonb,
  objectives JSONB DEFAULT '[]'::jsonb,
  param_docs JSONB DEFAULT '[]'::jsonb,
  views INTEGER DEFAULT 0,
  likes INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Upgrade existing databases: add columns BEFORE indexes/policies that reference them
ALTER TABLE public.simulations ADD COLUMN IF NOT EXISTS forked_from UUID REFERENCES public.simulations(id) ON DELETE SET NULL;
ALTER TABLE public.simulations ADD COLUMN IF NOT EXISTS is_preset BOOLEAN DEFAULT FALSE;
ALTER TABLE public.simulations ADD COLUMN IF NOT EXISTS preset_key TEXT;
ALTER TABLE public.simulations ADD COLUMN IF NOT EXISTS concepts JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.simulations ADD COLUMN IF NOT EXISTS objectives JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.simulations ADD COLUMN IF NOT EXISTS param_docs JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.simulations ALTER COLUMN author_id DROP NOT NULL;

-- Indexes (after columns exist)
CREATE INDEX IF NOT EXISTS idx_simulations_slug ON public.simulations(slug);
CREATE INDEX IF NOT EXISTS idx_simulations_author ON public.simulations(author_id);
CREATE INDEX IF NOT EXISTS idx_simulations_category ON public.simulations(category);
CREATE INDEX IF NOT EXISTS idx_simulations_created ON public.simulations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_simulations_public ON public.simulations(is_public) WHERE is_public = TRUE;
CREATE INDEX IF NOT EXISTS idx_simulations_preset ON public.simulations(is_preset) WHERE is_preset = TRUE;
CREATE INDEX IF NOT EXISTS idx_simulations_preset_key ON public.simulations(preset_key) WHERE preset_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_simulations_preset_key_unique ON public.simulations(preset_key) WHERE preset_key IS NOT NULL;

-- Likes
CREATE TABLE IF NOT EXISTS public.likes (
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  simulation_id UUID REFERENCES public.simulations(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, simulation_id)
);

CREATE INDEX IF NOT EXISTS idx_likes_simulation ON public.likes(simulation_id);

-- Row Level Security
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.simulations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.likes ENABLE ROW LEVEL SECURITY;

-- Profiles policies
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
CREATE POLICY "Public profiles are viewable by everyone"
  ON public.profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Simulations policies
DROP POLICY IF EXISTS "Public simulations are viewable by everyone" ON public.simulations;
CREATE POLICY "Public simulations are viewable by everyone"
  ON public.simulations FOR SELECT
  USING (is_preset = true OR is_public = true OR author_id = auth.uid());

DROP POLICY IF EXISTS "Users can create simulations" ON public.simulations;
CREATE POLICY "Users can create simulations"
  ON public.simulations FOR INSERT
  WITH CHECK (auth.uid() = author_id);

DROP POLICY IF EXISTS "Users can update own simulations" ON public.simulations;
CREATE POLICY "Users can update own simulations"
  ON public.simulations FOR UPDATE
  USING (auth.uid() = author_id);

DROP POLICY IF EXISTS "Users can delete own simulations" ON public.simulations;
CREATE POLICY "Users can delete own simulations"
  ON public.simulations FOR DELETE
  USING (auth.uid() = author_id);

-- Likes policies
DROP POLICY IF EXISTS "Likes are viewable by everyone" ON public.likes;
CREATE POLICY "Likes are viewable by everyone"
  ON public.likes FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can create likes" ON public.likes;
CREATE POLICY "Users can create likes"
  ON public.likes FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own likes" ON public.likes;
CREATE POLICY "Users can delete own likes"
  ON public.likes FOR DELETE USING (auth.uid() = user_id);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  base_username TEXT;
  final_username TEXT;
BEGIN
  -- Parse base username from user_name, name, or email
  base_username := COALESCE(
    NEW.raw_user_meta_data->>'user_name',
    NEW.raw_user_meta_data->>'name',
    split_part(NEW.email, '@', 1)
  );
  
  -- Clean username (replace spaces/special chars)
  base_username := regexp_replace(lower(base_username), '[^a-z0-9_]', '', 'g');
  
  -- Ensure username is not empty
  IF base_username = '' OR base_username IS NULL THEN
    base_username := 'user';
  END IF;
  
  final_username := base_username;
  
  -- Resolve potential unique constraint collisions by appending a short slice of the UUID
  IF EXISTS (SELECT 1 FROM public.profiles WHERE username = final_username) THEN
    final_username := substring(final_username, 1, 15) || '_' || substring(NEW.id::text, 1, 5);
  END IF;

  INSERT INTO public.profiles (id, username, full_name, avatar_url, github_username)
  VALUES (
    NEW.id,
    final_username,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', final_username),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', NEW.raw_user_meta_data->>'picture'),
    NEW.raw_user_meta_data->>'user_name'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- View counter (callable by anyone with anon key)
CREATE OR REPLACE FUNCTION public.increment_views(sim_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE public.simulations SET views = views + 1 WHERE id = sim_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.increment_likes(sim_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE public.simulations SET likes = likes + 1 WHERE id = sim_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.decrement_likes(sim_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE public.simulations SET likes = GREATEST(0, likes - 1) WHERE id = sim_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute on RPC functions to anon and authenticated roles
GRANT EXECUTE ON FUNCTION public.increment_views(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_likes(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_likes(UUID) TO anon, authenticated;
