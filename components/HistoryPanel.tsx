'use client';

import { useState } from 'react';
import type { ScoreAction } from '@/lib/supabaseClient';

interface HistoryPanelProps {
  actions: ScoreAction[];
  currentClientId: string;
}

// Format timestamp to relative time
function formatTime(timestamp: string): string {
  const date = new Date(timestamp);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffSecs = Math.floor(diffMs / 1000);

  if (diffSecs < 60) return `${diffSecs}s ago`;
  if (diffSecs < 3600) return `${Math.floor(diffSecs / 60)}m ago`;
  if (diffSecs < 86400) return `${Math.floor(diffSecs / 3600)}h ago`;
  return date.toLocaleDateString();
}

// Format action type to human-readable string
function formatActionType(action: ScoreAction): string {
  switch (action.action_type) {
    case 'increment':
      return `+${action.delta}`;
    case 'decrement':
      return `${action.delta}`;
    case 'reset':
      return `reset`;
    case 'reset_all':
      return `reset all`;
    case 'undo':
      return `undo`;
    default:
      return action.action_type;
  }
}

// Team color for badges
const teamBadgeColors: Record<string, string> = {
  blue: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300',
  green: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300',
  yellow: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300',
  red: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300',
};

export default function HistoryPanel({ actions, currentClientId }: HistoryPanelProps) {
  const [isExpanded, setIsExpanded] = useState(false);

  // On mobile, show collapsed by default
  const displayActions = isExpanded ? actions : actions.slice(0, 5);

  return (
    <div className="bg-gray-100 dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700">
      {/* Header */}
      <div className="px-4 py-3 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between">
        <h3 className="font-semibold text-gray-900 dark:text-gray-100">
          History
        </h3>
        <button
          onClick={() => setIsExpanded(!isExpanded)}
          className="text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200"
        >
          {isExpanded ? 'Show less' : `Show all (${actions.length})`}
        </button>
      </div>

      {/* Action List */}
      <div className="divide-y divide-gray-100 dark:divide-gray-700 max-h-80 overflow-y-auto">
        {displayActions.length === 0 ? (
          <div className="px-4 py-8 text-center text-gray-500 dark:text-gray-400 text-sm">
            No actions yet
          </div>
        ) : (
          displayActions.map((action) => {
            const isOwnAction = action.client_id === currentClientId;
            const badgeColor = teamBadgeColors[action.team] || teamBadgeColors.blue;

            return (
              <div
                key={action.id}
                className={`px-4 py-3 flex items-center gap-3 ${
                  action.undone ? 'opacity-50' : ''
                } ${isOwnAction ? 'bg-black-50 dark:bg-gray-750' : ''}`}
              >
                {/* Team Badge */}
                <span
                  className={`px-2 py-0.5 rounded text-xs font-medium capitalize ${badgeColor}`}
                >
                  {action.team}
                </span>

                {/* Action Info */}
                <div className="flex-1 min-w-0">
                  <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
                    {formatActionType(action)}
                  </span>
                  <span className="text-sm text-gray-500 dark:text-gray-400 ml-2">
                    {action.prev_score} → {action.new_score}
                  </span>
                  {action.undone && (
                    <span className="text-xs text-red-500 ml-2">(undone)</span>
                  )}
                </div>

                {/* Timestamp & Client Indicator */}
                <div className="text-right flex-shrink-0">
                  <div className="text-xs text-gray-400 dark:text-gray-500">
                    {formatTime(action.created_at)}
                  </div>
                  {isOwnAction && (
                    <div className="text-xs text-blue-500">you</div>
                  )}
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
