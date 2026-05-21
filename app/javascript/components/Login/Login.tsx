import { useState, useCallback } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { csrfToken } from '../../utils/api';
import './Login.scss';

type AuthMode = 'signin' | 'signup' | 'forgot';

function fireRedditPixel(customEventName: string, extra: Record<string, unknown> = {}) {
  const rdt = (window as Window & { rdt?: (...args: unknown[]) => void }).rdt;
  if (typeof rdt !== 'function') return;
  rdt('track', 'Custom', {
    customEventName,
    pagePath: window.location.pathname,
    ...extra,
  });
}

function fireOAuthPixelAndSubmit(form: HTMLFormElement, provider: string) {
  const rdt = (window as Window & { rdt?: (...args: unknown[]) => void }).rdt;
  if (typeof rdt === 'function') {
    const normalizedProvider = provider.replace(/[^a-z0-9]+/gi, '_').toLowerCase();
    fireRedditPixel(`OAuthClick_${normalizedProvider}`, {
      oauthProvider: normalizedProvider,
      oauthProviderRaw: provider,
    });
    setTimeout(() => form.submit(), 100);
  } else {
    form.submit();
  }
}

const OAuthButton = ({ provider, label, children }: { provider: string; label: string; children: React.ReactNode }) => {
  const handleClick = useCallback((e: React.MouseEvent<HTMLButtonElement>) => {
    e.preventDefault();
    fireOAuthPixelAndSubmit(e.currentTarget.form!, provider);
  }, [provider]);

  return (
    <form action={`/auth/${provider}`} method="post" className="oauth-form">
      <input type="hidden" name="authenticity_token" value={csrfToken()} />
      <input type="hidden" name="origin" value={window.location.pathname} />
      <button type="submit" className={`oauth-icon-btn oauth-icon-btn--${provider}`} aria-label={label} title={label} onClick={handleClick}>
        {children}
      </button>
    </form>
  );
};

const GuestConversionButton = () => {
  const { startGuest } = useAuth();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleClick = useCallback(async () => {
    setError(null);
    setLoading(true);
    fireRedditPixel('GuestConversion');
    try {
      await startGuest();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not start guest session');
    } finally {
      setLoading(false);
    }
  }, [startGuest]);

  return (
    <div className="guest-cta">
      <button type="button" className="guest-cta__button" onClick={handleClick} disabled={loading}>
        {loading ? 'Starting…' : 'Continue without an account'}
      </button>
      <p className="guest-cta__subtitle">Free trial — no email needed. Sign up later to keep your adventures.</p>
      {error && <p className="feedback-error">{error}</p>}
    </div>
  );
};

const SignInForm = ({ onForgotPassword }: { onForgotPassword: () => void }) => {
  const { login } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      await login(email, password);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      {error && <p className="feedback-error">{error}</p>}
      <div className="form-group">
        <label htmlFor="signin-email">Email:</label>
        <input
          type="email"
          id="signin-email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          placeholder="Enter your email"
          aria-label="Email"
          autoComplete="email"
        />
      </div>
      <div className="form-group">
        <label htmlFor="signin-password">Password:</label>
        <input
          type="password"
          id="signin-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          placeholder="Enter your password"
          aria-label="Password"
          autoComplete="current-password"
        />
      </div>
      <button type="submit" disabled={loading}>
        {loading ? 'Logging in…' : 'Login'}
      </button>
      <p className="auth-secondary-link">
        <button type="button" className="link-button" onClick={onForgotPassword}>
          Forgot password?
        </button>
      </p>
    </form>
  );
};

const SignUpForm = () => {
  const { signup } = useAuth();
  const [email, setEmail] = useState('');
  const [handle, setHandle] = useState('');
  const [password, setPassword] = useState('');
  const [passwordConfirmation, setPasswordConfirmation] = useState('');
  const [errors, setErrors] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrors([]);
    setLoading(true);
    try {
      await signup({ email, handle: handle || undefined, password, passwordConfirmation });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Signup failed';
      setErrors(message.split('\n'));
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      {errors.length > 0 && (
        <ul className="feedback-error feedback-error--list">
          {errors.map((message) => <li key={message}>{message}</li>)}
        </ul>
      )}
      <div className="form-group">
        <label htmlFor="signup-email">Email:</label>
        <input
          type="email"
          id="signup-email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          placeholder="you@example.com"
          autoComplete="email"
        />
      </div>
      <div className="form-group">
        <label htmlFor="signup-handle">Handle (optional):</label>
        <input
          type="text"
          id="signup-handle"
          value={handle}
          onChange={(e) => setHandle(e.target.value)}
          placeholder="A nickname (letters, numbers, underscores)"
          minLength={3}
          maxLength={32}
          pattern="[A-Za-z0-9_]{3,32}"
          autoComplete="username"
        />
      </div>
      <div className="form-group">
        <label htmlFor="signup-password">Password:</label>
        <input
          type="password"
          id="signup-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          minLength={8}
          placeholder="At least 8 characters"
          autoComplete="new-password"
        />
      </div>
      <div className="form-group">
        <label htmlFor="signup-password-confirmation">Confirm password:</label>
        <input
          type="password"
          id="signup-password-confirmation"
          value={passwordConfirmation}
          onChange={(e) => setPasswordConfirmation(e.target.value)}
          required
          minLength={8}
          placeholder="Repeat your password"
          autoComplete="new-password"
        />
      </div>
      <button type="submit" disabled={loading}>
        {loading ? 'Creating account…' : 'Create account'}
      </button>
    </form>
  );
};

const ForgotPasswordForm = ({ onCancel }: { onCancel: () => void }) => {
  const { requestPasswordReset } = useAuth();
  const [email, setEmail] = useState('');
  const [message, setMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setMessage(null);
    try {
      await requestPasswordReset(email);
      setMessage("If that email is in our system, a reset link is on its way.");
    } catch {
      setMessage("If that email is in our system, a reset link is on its way.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <p>Enter your email and we'll send you a reset link.</p>
      {message && <p className="feedback-success">{message}</p>}
      <div className="form-group">
        <label htmlFor="forgot-email">Email:</label>
        <input
          type="email"
          id="forgot-email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          autoComplete="email"
        />
      </div>
      <button type="submit" disabled={loading}>
        {loading ? 'Sending…' : 'Send reset link'}
      </button>
      <p className="auth-secondary-link">
        <button type="button" className="link-button" onClick={onCancel}>
          Back to sign in
        </button>
      </p>
    </form>
  );
};

export const Login = () => {
  const [mode, setMode] = useState<AuthMode>('signin');

  return (
    <div className="login-container">
      <div className="login-box">
        <h1>Leather Armor</h1>

        <GuestConversionButton />

        <div className="login-divider">
          <span>or sign in with</span>
        </div>

        <div className="oauth-row">
          <OAuthButton provider="google_oauth2" label="Sign in with Google">
            <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
              <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z"/>
              <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
              <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18A10.96 10.96 0 0 0 1 12c0 1.77.42 3.45 1.18 4.93l3.66-2.84z"/>
              <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
            </svg>
          </OAuthButton>

          <OAuthButton provider="discord" label="Sign in with Discord">
            <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
              <path fill="#5865F2" d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028 14.09 14.09 0 0 0 1.226-1.994.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.947 2.418-2.157 2.418z"/>
            </svg>
          </OAuthButton>

          <OAuthButton provider="twitchtv" label="Sign in with Twitch">
            <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
              <path fill="#9146FF" d="M11.571 4.714h1.715v5.143H11.57zm4.715 0H18v5.143h-1.714zM6 0L1.714 4.286v15.428h5.143V24l4.286-4.286h3.428L22.286 12V0zm14.571 11.143l-3.428 3.428h-3.429l-3 3v-3H6.857V1.714h13.714z"/>
            </svg>
          </OAuthButton>
        </div>

        <div className="login-divider">
          <span>{mode === 'signup' ? 'or create an account with email' : 'or sign in with email'}</span>
        </div>

        {mode === 'signin' && <SignInForm onForgotPassword={() => setMode('forgot')} />}
        {mode === 'signup' && <SignUpForm />}
        {mode === 'forgot' && <ForgotPasswordForm onCancel={() => setMode('signin')} />}

        {mode !== 'forgot' && (
          <p className="auth-toggle">
            {mode === 'signin' ? (
              <>
                New here?{' '}
                <button type="button" className="link-button" onClick={() => setMode('signup')}>
                  Create an account
                </button>
              </>
            ) : (
              <>
                Already have an account?{' '}
                <button type="button" className="link-button" onClick={() => setMode('signin')}>
                  Sign in
                </button>
              </>
            )}
          </p>
        )}
      </div>
    </div>
  );
};
