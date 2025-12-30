-- ============================================================================
-- REALTIME TEAM SCORES - Supabase Schema
-- ============================================================================
-- This schema creates:
-- 1. scores table - stores current score for each team
-- 2. score_actions table - logs every score change for history/undo
-- 3. RPC functions with rate limiting for all mutations
-- 4. RLS policies to prevent direct table manipulation
-- ============================================================================

-- ============================================================================
-- CONFIGURATION CONSTANTS (adjust as needed)
-- ============================================================================
-- Rate limit: 5 actions per 10 seconds per client_id
-- Undo window: 60 seconds

-- ============================================================================
-- DROP EXISTING OBJECTS (for clean re-runs)
-- ============================================================================
DROP FUNCTION IF EXISTS increment_team(text, text);
DROP FUNCTION IF EXISTS increment_team(text, text, integer);
DROP FUNCTION IF EXISTS decrement_team(text, text);
DROP FUNCTION IF EXISTS decrement_team(text, text, integer);
DROP FUNCTION IF EXISTS reset_team(text, text);
DROP FUNCTION IF EXISTS reset_all(text);
DROP FUNCTION IF EXISTS undo_last_action(text);
DROP FUNCTION IF EXISTS check_rate_limit(text);
DROP TABLE IF EXISTS score_actions;
DROP TABLE IF EXISTS scores;

-- ============================================================================
-- TABLES
-- ============================================================================

-- Scores table: stores current score for each team
CREATE TABLE scores (
    team TEXT PRIMARY KEY,
    score INTEGER NOT NULL DEFAULT 0 CHECK (score >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Score actions table: logs every score change
CREATE TABLE score_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team TEXT NOT NULL REFERENCES scores(team),
    delta INTEGER NOT NULL,
    prev_score INTEGER NOT NULL,
    new_score INTEGER NOT NULL,
    client_id TEXT NOT NULL,
    action_type TEXT NOT NULL, -- 'increment', 'decrement', 'reset', 'reset_all', 'undo'
    reverts_action_id UUID REFERENCES score_actions(id), -- for undo actions
    undone BOOLEAN NOT NULL DEFAULT FALSE,
    undone_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for rate limiting queries
CREATE INDEX idx_score_actions_client_created ON score_actions(client_id, created_at DESC);

-- Index for undo queries (finding last action by client)
CREATE INDEX idx_score_actions_client_undo ON score_actions(client_id, created_at DESC)
    WHERE undone = FALSE AND action_type != 'undo';

-- ============================================================================
-- SEED DATA: Initialize four teams
-- ============================================================================
INSERT INTO scores (team, score) VALUES
    ('blue', 0),
    ('green', 0),
    ('yellow', 0),
    ('red', 0);

-- ============================================================================
-- ENABLE ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE score_actions ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

-- Scores: Allow public SELECT only
CREATE POLICY "Allow public read on scores" ON scores
    FOR SELECT TO anon, authenticated
    USING (true);

-- Score actions: Allow public SELECT only
CREATE POLICY "Allow public read on score_actions" ON score_actions
    FOR SELECT TO anon, authenticated
    USING (true);

-- No INSERT/UPDATE/DELETE policies = mutations blocked except via SECURITY DEFINER functions

-- ============================================================================
-- HELPER FUNCTION: Rate Limit Check
-- ============================================================================
-- Returns TRUE if client is rate-limited (too many actions), FALSE if allowed
CREATE OR REPLACE FUNCTION check_rate_limit(p_client_id TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    action_count INTEGER;
    rate_limit_max INTEGER := 5;         -- Max actions allowed
    rate_limit_window INTERVAL := '10 seconds'; -- Time window
BEGIN
    -- Count recent actions by this client
    SELECT COUNT(*) INTO action_count
    FROM score_actions
    WHERE client_id = p_client_id
      AND created_at > NOW() - rate_limit_window;

    RETURN action_count >= rate_limit_max;
END;
$$;

-- ============================================================================
-- RPC FUNCTION: Increment Team Score (with configurable amount)
-- ============================================================================
CREATE OR REPLACE FUNCTION increment_team(p_team TEXT, p_client_id TEXT, p_amount INTEGER DEFAULT 1)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_prev_score INTEGER;
    v_new_score INTEGER;
    v_action_id UUID;
    v_amount INTEGER;
BEGIN
    -- Validate and clamp amount (1-100)
    v_amount := GREATEST(1, LEAST(p_amount, 100));

    -- Check rate limit
    IF check_rate_limit(p_client_id) THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Rate limited. Please wait a few seconds.'
        );
    END IF;

    -- Lock the row and get current score
    SELECT score INTO v_prev_score
    FROM scores
    WHERE team = p_team
    FOR UPDATE;

    IF v_prev_score IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Team not found'
        );
    END IF;

    v_new_score := v_prev_score + v_amount;

    -- Update score
    UPDATE scores
    SET score = v_new_score, updated_at = NOW()
    WHERE team = p_team;

    -- Log action
    INSERT INTO score_actions (team, delta, prev_score, new_score, client_id, action_type)
    VALUES (p_team, v_amount, v_prev_score, v_new_score, p_client_id, 'increment')
    RETURNING id INTO v_action_id;

    RETURN json_build_object(
        'success', true,
        'team', p_team,
        'prev_score', v_prev_score,
        'new_score', v_new_score,
        'action_id', v_action_id
    );
END;
$$;

-- ============================================================================
-- RPC FUNCTION: Decrement Team Score (with configurable amount, floor at 0)
-- ============================================================================
CREATE OR REPLACE FUNCTION decrement_team(p_team TEXT, p_client_id TEXT, p_amount INTEGER DEFAULT 1)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_prev_score INTEGER;
    v_new_score INTEGER;
    v_action_id UUID;
    v_amount INTEGER;
    v_actual_delta INTEGER;
BEGIN
    -- Validate and clamp amount (1-100)
    v_amount := GREATEST(1, LEAST(p_amount, 100));

    -- Check rate limit
    IF check_rate_limit(p_client_id) THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Rate limited. Please wait a few seconds.'
        );
    END IF;

    -- Lock the row and get current score
    SELECT score INTO v_prev_score
    FROM scores
    WHERE team = p_team
    FOR UPDATE;

    IF v_prev_score IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Team not found'
        );
    END IF;

    -- Floor at 0
    v_new_score := GREATEST(v_prev_score - v_amount, 0);
    v_actual_delta := v_prev_score - v_new_score;

    -- Only update if there's a change
    IF v_actual_delta = 0 THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Score is already at 0'
        );
    END IF;

    -- Update score
    UPDATE scores
    SET score = v_new_score, updated_at = NOW()
    WHERE team = p_team;

    -- Log action with actual delta (may be less than requested if score hit 0)
    INSERT INTO score_actions (team, delta, prev_score, new_score, client_id, action_type)
    VALUES (p_team, -v_actual_delta, v_prev_score, v_new_score, p_client_id, 'decrement')
    RETURNING id INTO v_action_id;

    RETURN json_build_object(
        'success', true,
        'team', p_team,
        'prev_score', v_prev_score,
        'new_score', v_new_score,
        'action_id', v_action_id
    );
END;
$$;

-- ============================================================================
-- RPC FUNCTION: Reset Team Score to 0
-- ============================================================================
CREATE OR REPLACE FUNCTION reset_team(p_team TEXT, p_client_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_prev_score INTEGER;
    v_action_id UUID;
BEGIN
    -- Check rate limit
    IF check_rate_limit(p_client_id) THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Rate limited. Please wait a few seconds.'
        );
    END IF;

    -- Lock the row and get current score
    SELECT score INTO v_prev_score
    FROM scores
    WHERE team = p_team
    FOR UPDATE;

    IF v_prev_score IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Team not found'
        );
    END IF;

    -- Only update if there's a change
    IF v_prev_score = 0 THEN
        RETURN json_build_object(
            'success', true,
            'team', p_team,
            'message', 'Score is already 0'
        );
    END IF;

    -- Update score
    UPDATE scores
    SET score = 0, updated_at = NOW()
    WHERE team = p_team;

    -- Log action
    INSERT INTO score_actions (team, delta, prev_score, new_score, client_id, action_type)
    VALUES (p_team, -v_prev_score, v_prev_score, 0, p_client_id, 'reset')
    RETURNING id INTO v_action_id;

    RETURN json_build_object(
        'success', true,
        'team', p_team,
        'prev_score', v_prev_score,
        'new_score', 0,
        'action_id', v_action_id
    );
END;
$$;

-- ============================================================================
-- RPC FUNCTION: Reset All Teams to 0
-- ============================================================================
CREATE OR REPLACE FUNCTION reset_all(p_client_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_team RECORD;
    v_actions_created INTEGER := 0;
BEGIN
    -- Check rate limit
    IF check_rate_limit(p_client_id) THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Rate limited. Please wait a few seconds.'
        );
    END IF;

    -- Loop through all teams with non-zero scores
    FOR v_team IN
        SELECT team, score
        FROM scores
        WHERE score > 0
        FOR UPDATE
    LOOP
        -- Update score
        UPDATE scores
        SET score = 0, updated_at = NOW()
        WHERE team = v_team.team;

        -- Log action for each team
        INSERT INTO score_actions (team, delta, prev_score, new_score, client_id, action_type)
        VALUES (v_team.team, -v_team.score, v_team.score, 0, p_client_id, 'reset_all');

        v_actions_created := v_actions_created + 1;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'teams_reset', v_actions_created
    );
END;
$$;

-- ============================================================================
-- RPC FUNCTION: Undo Last Action (by this client, within 60 seconds)
-- ============================================================================
CREATE OR REPLACE FUNCTION undo_last_action(p_client_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_action RECORD;
    v_current_score INTEGER;
    v_new_score INTEGER;
    v_undo_window INTERVAL := '60 seconds';
    v_undo_action_id UUID;
BEGIN
    -- Check rate limit
    IF check_rate_limit(p_client_id) THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Rate limited. Please wait a few seconds.'
        );
    END IF;

    -- Find the most recent undoable action by this client
    SELECT id, team, delta, prev_score, new_score, created_at
    INTO v_action
    FROM score_actions
    WHERE client_id = p_client_id
      AND undone = FALSE
      AND action_type != 'undo'
      AND created_at > NOW() - v_undo_window
    ORDER BY created_at DESC
    LIMIT 1
    FOR UPDATE;

    IF v_action IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'No undoable action found (must be within 60 seconds)'
        );
    END IF;

    -- Lock the team score row
    SELECT score INTO v_current_score
    FROM scores
    WHERE team = v_action.team
    FOR UPDATE;

    -- Calculate new score (apply inverse delta, floor at 0)
    v_new_score := GREATEST(v_current_score - v_action.delta, 0);

    -- Update the score
    UPDATE scores
    SET score = v_new_score, updated_at = NOW()
    WHERE team = v_action.team;

    -- Mark original action as undone
    UPDATE score_actions
    SET undone = TRUE, undone_at = NOW()
    WHERE id = v_action.id;

    -- Log the undo action
    INSERT INTO score_actions (team, delta, prev_score, new_score, client_id, action_type, reverts_action_id)
    VALUES (v_action.team, -v_action.delta, v_current_score, v_new_score, p_client_id, 'undo', v_action.id)
    RETURNING id INTO v_undo_action_id;

    RETURN json_build_object(
        'success', true,
        'team', v_action.team,
        'prev_score', v_current_score,
        'new_score', v_new_score,
        'reverted_action_id', v_action.id,
        'undo_action_id', v_undo_action_id
    );
END;
$$;

-- ============================================================================
-- GRANT EXECUTE PERMISSIONS TO ANON ROLE
-- ============================================================================
GRANT EXECUTE ON FUNCTION increment_team(text, text, integer) TO anon;
GRANT EXECUTE ON FUNCTION decrement_team(text, text, integer) TO anon;
GRANT EXECUTE ON FUNCTION reset_team(text, text) TO anon;
GRANT EXECUTE ON FUNCTION reset_all(text) TO anon;
GRANT EXECUTE ON FUNCTION undo_last_action(text) TO anon;

-- ============================================================================
-- ENABLE REALTIME (run these in Supabase Dashboard or via API)
-- ============================================================================
-- Note: Realtime must be enabled via Supabase Dashboard:
-- 1. Go to Database > Replication
-- 2. Enable replication for 'scores' table
-- 3. Enable replication for 'score_actions' table
--
-- Or use the following (requires supabase_admin role):
-- ALTER PUBLICATION supabase_realtime ADD TABLE scores;
-- ALTER PUBLICATION supabase_realtime ADD TABLE score_actions;
