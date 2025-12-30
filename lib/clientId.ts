const CLIENT_ID_KEY = 'realtime-scores-client-id';

// Generate a unique client ID for rate limiting and undo tracking
function generateClientId(): string {
  return `client_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`;
}

// Get or create a persistent client ID stored in localStorage
export function getClientId(): string {
  if (typeof window === 'undefined') {
    // Server-side: return a placeholder (won't be used for mutations)
    return 'server';
  }

  let clientId = localStorage.getItem(CLIENT_ID_KEY);

  if (!clientId) {
    clientId = generateClientId();
    localStorage.setItem(CLIENT_ID_KEY, clientId);
  }

  return clientId;
}
