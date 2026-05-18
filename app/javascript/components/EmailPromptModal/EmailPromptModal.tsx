import { useState, useCallback } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { apiFetch, csrfToken } from '../../utils/api';
import './EmailPromptModal.scss';

const EmailPromptModal = () => {
  const { emailPrompt, dismissEmailPrompt, setUser, user } = useAuth();
  const [email, setEmail] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const handleSubmit = useCallback(async () => {
    if (!email.trim()) return;
    setError(null);
    setSaving(true);

    try {
      const res = await apiFetch<{ email: string }>('/profile/email', {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken(),
        },
        body: JSON.stringify({ email: email.trim() }),
      });
      if (user) setUser({ ...user, email: res.email });
      dismissEmailPrompt();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update email');
    } finally {
      setSaving(false);
    }
  }, [email, user, setUser, dismissEmailPrompt]);

  if (!emailPrompt) return null;

  return (
    <div className="email-prompt-overlay">
      <div className="email-prompt-modal">
        <h2>Add your email (optional)</h2>
        <p>
          We noticed you signed in without an email address.
          Adding one lets us reach you about account-related updates.
          Feel free to skip if you'd rather not.
        </p>

        {error && <p className="email-prompt-error">{error}</p>}

        <input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@example.com"
          autoFocus
        />

        <div className="email-prompt-actions">
          <button
            className="email-prompt-skip"
            onClick={dismissEmailPrompt}
            type="button"
          >
            Skip
          </button>
          <button
            className="email-prompt-save"
            onClick={handleSubmit}
            disabled={saving || !email.trim()}
            type="button"
          >
            {saving ? 'Saving...' : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
};

export default EmailPromptModal;
