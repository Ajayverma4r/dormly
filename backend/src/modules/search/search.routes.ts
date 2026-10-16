// modules/search/search.routes.ts
import { Router } from 'express';
import { authGuard, requireContext } from '@shared/middleware/auth-guard';
import { userRateLimit } from '@shared/middleware/rate-limit';
import { SearchController } from './search.controller';

/** Bursts of typing are fine (the app debounces); sustained use is 30 a minute. */
export const SEARCH_RATE_LIMIT = { capacity: 30, refillPerSecond: 0.5 } as const;

export const searchRateLimit = userRateLimit({
  ...SEARCH_RATE_LIMIT,
  code: 'search_rate_limited',
  message: 'Too many searches. Please wait a moment and try again.',
});

const controller = new SearchController();
export const searchRouter = Router();

// Rate limit before the context check so rejected requests cost no queries.
searchRouter.use(authGuard, searchRateLimit, requireContext);

// Role-scoped search across the caller's workspace (see search.policy.ts).
searchRouter.get('/', controller.search);
