import { createClient, SupabaseClient } from '@supabase/supabase-js';

// Lazy initialization to avoid build-time errors when env vars aren't set
let _supabase: SupabaseClient | null = null;

function getSupabase(): SupabaseClient {
  if (!_supabase) {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

    if (!supabaseUrl || !supabaseAnonKey) {
      throw new Error(
        'Missing Supabase environment variables. Please set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in your .env.local file.'
      );
    }

    _supabase = createClient(supabaseUrl, supabaseAnonKey);
  }
  return _supabase;
}

// Export a proxy that lazily initializes the client
export const supabase = new Proxy({} as SupabaseClient, {
  get(_, prop) {
    const client = getSupabase();
    return (client as unknown as Record<string, unknown>)[prop as string];
  },
});

// Type definitions for our database
export interface Score {
  team: string;
  score: number;
  updated_at: string;
}

export interface ScoreAction {
  id: string;
  team: string;
  delta: number;
  prev_score: number;
  new_score: number;
  client_id: string;
  action_type: 'increment' | 'decrement' | 'reset' | 'reset_all' | 'undo';
  reverts_action_id: string | null;
  undone: boolean;
  undone_at: string | null;
  created_at: string;
}

export interface RpcResponse {
  success: boolean;
  error?: string;
  team?: string;
  prev_score?: number;
  new_score?: number;
  action_id?: string;
  teams_reset?: number;
  reverted_action_id?: string;
  undo_action_id?: string;
}
