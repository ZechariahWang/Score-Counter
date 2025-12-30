'use client';

import { useEffect, useState, useCallback, useRef } from 'react';
import { supabase, type Score, type ScoreAction, type RpcResponse } from '@/lib/supabaseClient';
import { getClientId } from '@/lib/clientId';
import TeamCard from '@/components/TeamCard';
import HistoryPanel from '@/components/HistoryPanel';
import Toast from '@/components/Toast';

const TEAM_ORDER = ['blue', 'green', 'yellow', 'red'];
const INCREMENT_OPTIONS = [1, 5, 10, 25];

export default function Home() {
  const [scores, setScores] = useState<Record<string, number>>({});
  const [actions, setActions] = useState<ScoreAction[]>([]);
  const [toast, setToast] = useState<{ message: string; type: 'error' | 'success' } | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [incrementAmount, setIncrementAmount] = useState(1);
  const clientIdRef = useRef<string>('');

  // Initialize client ID on mount
  useEffect(() => {
    clientIdRef.current = getClientId();
  }, []);

  // Show toast message
  const showToast = useCallback((message: string, type: 'error' | 'success') => {
    setToast({ message, type });
  }, []);

  // Fetch initial data
  useEffect(() => {
    async function fetchInitialData() {
      try {
        // Fetch scores
        const { data: scoresData, error: scoresError } = await supabase
          .from('scores')
          .select('*');

        if (scoresError) throw scoresError;

        const scoresMap: Record<string, number> = {};
        scoresData?.forEach((s: Score) => {
          scoresMap[s.team] = s.score;
        });
        setScores(scoresMap);

        // Fetch recent actions
        const { data: actionsData, error: actionsError } = await supabase
          .from('score_actions')
          .select('*')
          .order('created_at', { ascending: false })
          .limit(20);

        if (actionsError) throw actionsError;
        setActions(actionsData || []);
      } catch (error) {
        console.error('Error fetching initial data:', error);
        showToast('Failed to load data', 'error');
      } finally {
        setIsLoading(false);
      }
    }

    fetchInitialData();
  }, [showToast]);

  // Subscribe to realtime updates
  useEffect(() => {
    // Subscribe to scores changes
    const scoresChannel = supabase
      .channel('scores-changes')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'scores' },
        (payload) => {
          // Update scores from realtime event (server is source of truth)
          const newData = payload.new as Score | null;
          if (newData && newData.team && typeof newData.score === 'number') {
            setScores((prev) => ({
              ...prev,
              [newData.team]: newData.score,
            }));
          }
        }
      )
      .subscribe();

    // Subscribe to actions changes for history
    const actionsChannel = supabase
      .channel('actions-changes')
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'score_actions' },
        (payload) => {
          // Add new action to the top of the list
          if (payload.new) {
            setActions((prev) => [payload.new as ScoreAction, ...prev].slice(0, 20));
          }
        }
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'score_actions' },
        (payload) => {
          // Update action (e.g., when marked as undone)
          if (payload.new) {
            setActions((prev) =>
              prev.map((a) =>
                a.id === (payload.new as ScoreAction).id ? (payload.new as ScoreAction) : a
              )
            );
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(scoresChannel);
      supabase.removeChannel(actionsChannel);
    };
  }, []);

  // RPC call helper with error handling
  const callRpc = useCallback(
    async (funcName: string, params: Record<string, string | number>) => {
      const { data, error } = await supabase.rpc(funcName, params);

      if (error) {
        showToast(error.message, 'error');
        return null;
      }

      const response = data as RpcResponse;
      if (!response.success) {
        showToast(response.error || 'Operation failed', 'error');
        return null;
      }

      return response;
    },
    [showToast]
  );

  // Action handlers
  const handleIncrement = useCallback(
    async (team: string) => {
      await callRpc('increment_team', { p_team: team, p_client_id: clientIdRef.current, p_amount: incrementAmount });
    },
    [callRpc, incrementAmount]
  );

  const handleDecrement = useCallback(
    async (team: string) => {
      await callRpc('decrement_team', { p_team: team, p_client_id: clientIdRef.current, p_amount: incrementAmount });
    },
    [callRpc, incrementAmount]
  );

  const handleResetTeam = useCallback(
    async (team: string) => {
      await callRpc('reset_team', { p_team: team, p_client_id: clientIdRef.current });
    },
    [callRpc]
  );

  const handleResetAll = useCallback(async () => {
    await callRpc('reset_all', { p_client_id: clientIdRef.current });
  }, [callRpc]);

  const handleUndo = useCallback(async () => {
    const result = await callRpc('undo_last_action', { p_client_id: clientIdRef.current });
    if (result) {
      showToast('Action undone', 'success');
    }
  }, [callRpc, showToast]);

  // Check if user has any undoable actions (within 60 seconds)
  const hasUndoableAction = actions.some(
    (a) =>
      a.client_id === clientIdRef.current &&
      !a.undone &&
      a.action_type !== 'undo' &&
      new Date().getTime() - new Date(a.created_at).getTime() < 60000
  );

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-gray-500 dark:text-gray-400">Loading...</div>
      </div>
    );
  }

  return (
    <main className="min-h-screen bg-gray-50 dark:bg-gray-900 py-6 px-4">
      <div className="max-w-lg mx-auto space-y-6">
        {/* Header */}
        <header className="text-center">
          <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">
            Team Scores
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
            Realtime scoreboard
          </p>
        </header>

        {/* Increment Amount Selector */}
        <div className="flex items-center justify-center gap-2">
          <span className="text-sm text-gray-600 dark:text-gray-400">Step:</span>
          <div className="flex gap-1">
            {INCREMENT_OPTIONS.map((amount) => (
              <button
                key={amount}
                onClick={() => setIncrementAmount(amount)}
                className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                  incrementAmount === amount
                    ? 'bg-gray-800 dark:bg-gray-200 text-white dark:text-gray-900'
                    : 'bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300 hover:bg-gray-300 dark:hover:bg-gray-600'
                }`}
              >
                {amount}
              </button>
            ))}
          </div>
        </div>

        {/* Team Cards Grid */}
        <div className="grid grid-cols-2 gap-4">
          {TEAM_ORDER.map((team) => (
            <TeamCard
              key={team}
              team={team}
              score={scores[team] ?? 0}
              incrementAmount={incrementAmount}
              onIncrement={() => handleIncrement(team)}
              onDecrement={() => handleDecrement(team)}
              onReset={() => handleResetTeam(team)}
            />
          ))}
        </div>

        {/* Global Controls */}
        <div className="flex gap-3 justify-center">
          <button
            onClick={handleResetAll}
            className="px-4 py-2 bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300 rounded-lg font-medium hover:bg-gray-300 dark:hover:bg-gray-600 transition-colors"
          >
            Reset All
          </button>
          <button
            onClick={handleUndo}
            disabled={!hasUndoableAction}
            className="px-4 py-2 bg-amber-500 text-white rounded-lg font-medium hover:bg-amber-600 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Undo
          </button>
        </div>

        {/* History Panel */}
        <HistoryPanel actions={actions} currentClientId={clientIdRef.current} />
      </div>

      {/* Toast Notification */}
      {toast && (
        <Toast
          message={toast.message}
          type={toast.type}
          onClose={() => setToast(null)}
        />
      )}
    </main>
  );
}
