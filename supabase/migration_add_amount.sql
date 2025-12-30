-- ============================================================================
-- MIGRATION: Add amount parameter to increment/decrement functions
-- ============================================================================
-- Run this in your Supabase SQL Editor to update existing functions
-- ============================================================================

-- Drop old function signatures
DROP FUNCTION IF EXISTS increment_team(text, text);
DROP FUNCTION IF EXISTS decrement_team(text, text);

-- ============================================================================
-- RPC FUNCTION: Increment Team Score (with amount)
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
-- RPC FUNCTION: Decrement Team Score (with amount, floor at 0)
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
-- GRANT EXECUTE PERMISSIONS TO ANON ROLE (new signatures)
-- ============================================================================
GRANT EXECUTE ON FUNCTION increment_team(text, text, integer) TO anon;
GRANT EXECUTE ON FUNCTION decrement_team(text, text, integer) TO anon;
