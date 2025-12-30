'use client';

interface TeamCardProps {
  team: string;
  score: number;
  incrementAmount: number;
  onIncrement: () => void;
  onDecrement: () => void;
  onReset: () => void;
  disabled?: boolean;
}

// Team color configurations
const teamColors: Record<string, { bg: string; accent: string; text: string; button: string }> = {
  blue: {
    bg: 'bg-blue-50 dark:bg-blue-950',
    accent: 'border-blue-500',
    text: 'text-blue-600 dark:text-blue-400',
    button: 'bg-blue-500 hover:bg-blue-600 active:bg-blue-700',
  },
  green: {
    bg: 'bg-green-50 dark:bg-green-950',
    accent: 'border-green-500',
    text: 'text-green-600 dark:text-green-400',
    button: 'bg-green-500 hover:bg-green-600 active:bg-green-700',
  },
  yellow: {
    bg: 'bg-yellow-50 dark:bg-yellow-950',
    accent: 'border-yellow-500',
    text: 'text-yellow-600 dark:text-yellow-400',
    button: 'bg-yellow-500 hover:bg-yellow-600 active:bg-yellow-700',
  },
  red: {
    bg: 'bg-red-50 dark:bg-red-950',
    accent: 'border-red-500',
    text: 'text-red-600 dark:text-red-400',
    button: 'bg-red-500 hover:bg-red-600 active:bg-red-700',
  },
};

export default function TeamCard({
  team,
  score,
  incrementAmount,
  onIncrement,
  onDecrement,
  onReset,
  disabled,
}: TeamCardProps) {
  const colors = teamColors[team] || teamColors.blue;

  return (
    <div
      className={`${colors.bg} ${colors.accent} border-l-4 rounded-lg p-4 shadow-sm`}
    >
      {/* Team Name */}
      <h2 className={`text-lg font-semibold capitalize ${colors.text}`}>
        {team}
      </h2>

      {/* Score Display */}
      <div className="text-5xl font-bold text-center my-4 tabular-nums">
        {score}
      </div>

      {/* Control Buttons */}
      <div className="flex gap-1.5 justify-center">
        <button
          onClick={onDecrement}
          disabled={disabled || score === 0}
          className={`flex-1 min-w-0 px-2 py-2 rounded-lg text-white text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${colors.button}`}
          aria-label={`Decrement ${team} score`}
        >
          -{incrementAmount}
        </button>
        <button
          onClick={onIncrement}
          disabled={disabled}
          className={`flex-1 min-w-0 px-2 py-2 rounded-lg text-white text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${colors.button}`}
          aria-label={`Increment ${team} score`}
        >
          +{incrementAmount}
        </button>
        <button
          onClick={onReset}
          disabled={disabled || score === 0}
          className="flex-1 min-w-0 px-2 py-2 rounded-lg bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300 text-sm font-medium transition-colors hover:bg-gray-300 dark:hover:bg-gray-600 disabled:opacity-50 disabled:cursor-not-allowed"
          aria-label={`Reset ${team} score`}
        >
          R
        </button>
      </div>
    </div>
  );
}
