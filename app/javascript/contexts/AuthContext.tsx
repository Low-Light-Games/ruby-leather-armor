import {
  createContext,
  useState,
  useEffect,
  ReactNode,
  useContext,
} from 'react';
import type { Dispatch, SetStateAction } from 'react';
import { apiFetch } from '../utils/api';
import { API_ROUTES } from '../constants/apiRoutes';
import { fetchCurrentUser } from '../services/authService';
import type { AuthUser, SignupPayload } from '../types/auth';

interface AuthContextType {
  user: AuthUser | null;
  setUser: Dispatch<SetStateAction<AuthUser | null>>;
  loading: boolean;
  emailPrompt: boolean;
  dismissEmailPrompt: () => void;
  login: (email: string, password: string) => Promise<void>;
  signup: (payload: SignupPayload) => Promise<void>;
  startGuest: () => Promise<void>;
  requestPasswordReset: (email: string) => Promise<void>;
  logout: () => Promise<void>;
  checkAuth: () => Promise<void>;
}

interface UserEnvelope {
  user: AuthUser;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [emailPrompt, setEmailPrompt] = useState(false);

  const dismissEmailPrompt = () => setEmailPrompt(false);

  const checkAuth = async () => {
    try {
      const result = await fetchCurrentUser();
      setUser(result.user);
      if (result.emailPrompt) setEmailPrompt(true);
    } catch (error) {
      console.error('Auth check failed:', error);
      setUser(null);
    } finally {
      setLoading(false);
    }
  };

  const login = async (email: string, password: string) => {
    const data = await apiFetch<UserEnvelope>(API_ROUTES.login, {
      method: 'POST',
      body: JSON.stringify({ email, password }),
      credentials: 'same-origin',
    });
    setUser(data.user);
  };

  const signup = async (payload: SignupPayload) => {
    const data = await apiFetch<UserEnvelope>(API_ROUTES.signup, {
      method: 'POST',
      body: JSON.stringify({
        email: payload.email,
        handle: payload.handle,
        password: payload.password,
        password_confirmation: payload.passwordConfirmation,
      }),
      credentials: 'same-origin',
    });
    setUser(data.user);
  };

  const startGuest = async () => {
    const data = await apiFetch<UserEnvelope>(API_ROUTES.guestSessions, {
      method: 'POST',
      credentials: 'same-origin',
    });
    setUser(data.user);
  };

  const requestPasswordReset = async (email: string) => {
    await apiFetch(API_ROUTES.passwordResets, {
      method: 'POST',
      body: JSON.stringify({ email }),
      credentials: 'same-origin',
    });
  };

  const logout = async () => {
    try {
      await apiFetch(API_ROUTES.logout, {
        method: 'DELETE',
        credentials: 'same-origin',
      });
    } catch (error) {
      console.error('Logout failed:', error);
    } finally {
      setUser(null);
    }
  };

  useEffect(() => {
    checkAuth();
  }, []);

  const value = {
    user,
    setUser,
    loading,
    emailPrompt,
    dismissEmailPrompt,
    login,
    signup,
    startGuest,
    requestPasswordReset,
    logout,
    checkAuth,
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return ctx;
};
