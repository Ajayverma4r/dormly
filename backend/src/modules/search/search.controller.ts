// modules/search/search.controller.ts
import { Response, NextFunction } from 'express';
import type { AuthedRequest } from '@shared/middleware/auth-guard';
import {
  CATEGORIES_BY_ROLE,
  FILTER_CATEGORIES,
  FILTERS_BY_ROLE,
  SEARCH_CATEGORIES,
  SEARCH_FILTERS,
  SearchRequestError,
  isSearchRole,
  type SearchCategory,
  type SearchFilter,
  type SearchRole,
} from './search.policy';
import { SearchService, type SearchRequest } from './search.service';

export const MIN_QUERY_LENGTH = 2;
export const MAX_QUERY_LENGTH = 80;
export const MAX_LIMIT = 20;
/** Per-category limit when every category is searched at once. */
export const DEFAULT_LIMIT_ALL = 5;
/** Per-category limit when one category or filter is selected. */
export const DEFAULT_LIMIT_ONE = 20;

function single(value: unknown, code: SearchRequestError['code'], message: string): string | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== 'string') throw new SearchRequestError(400, code, message);
  return value;
}

/**
 * Validates the search query string. Only `q`, `category`, `filter` and
 * `limit` are read; any property, tenant, organization or role values the
 * client sends are ignored — scope comes from the token context.
 */
export function parseSearchRequest(raw: Record<string, unknown>, role: SearchRole): SearchRequest & {
  category: SearchCategory | null;
} {
  const rawText = single(raw.q, 'invalid_search_query', 'Enter the search text once.') ?? '';
  const text = rawText.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();
  if (text.length > MAX_QUERY_LENGTH) {
    throw new SearchRequestError(400, 'invalid_search_query', `Search text can be at most ${MAX_QUERY_LENGTH} characters.`);
  }

  const rawCategory = single(raw.category, 'invalid_search_category', 'Choose one search category.');
  let category: SearchCategory | null = null;
  if (rawCategory !== undefined && rawCategory !== '' && rawCategory !== 'all') {
    if (!(SEARCH_CATEGORIES as readonly string[]).includes(rawCategory)) {
      throw new SearchRequestError(400, 'invalid_search_category', 'That search category does not exist.');
    }
    category = rawCategory as SearchCategory;
    if (!CATEGORIES_BY_ROLE[role].includes(category)) {
      throw new SearchRequestError(403, 'search_category_forbidden', 'You do not have access to search this category.');
    }
  }

  const rawFilter = single(raw.filter, 'invalid_search_filter', 'Choose one search filter.');
  let filter: SearchFilter | null = null;
  if (rawFilter !== undefined && rawFilter !== '') {
    if (!(SEARCH_FILTERS as readonly string[]).includes(rawFilter)) {
      throw new SearchRequestError(400, 'invalid_search_filter', 'That search filter does not exist.');
    }
    filter = rawFilter as SearchFilter;
    if (!FILTERS_BY_ROLE[role].includes(filter)) {
      throw new SearchRequestError(403, 'search_filter_forbidden', 'You do not have access to this search filter.');
    }
    if (category && !FILTER_CATEGORIES[filter].includes(category)) {
      throw new SearchRequestError(400, 'invalid_search_filter', 'That filter does not apply to this category.');
    }
  }

  if (!filter && text.length < MIN_QUERY_LENGTH) {
    throw new SearchRequestError(400, 'search_query_too_short', `Type at least ${MIN_QUERY_LENGTH} characters to search.`);
  }

  const rawLimit = single(raw.limit, 'invalid_search_limit', 'Choose one result limit.');
  const narrowed = Boolean(category || filter);
  let limit = narrowed ? DEFAULT_LIMIT_ONE : DEFAULT_LIMIT_ALL;
  if (rawLimit !== undefined && rawLimit !== '') {
    if (!/^\d{1,3}$/.test(rawLimit) || Number(rawLimit) < 1 || Number(rawLimit) > MAX_LIMIT) {
      throw new SearchRequestError(400, 'invalid_search_limit', `Limit must be a whole number from 1 to ${MAX_LIMIT}.`);
    }
    limit = Number(rawLimit);
  }

  const categories: SearchCategory[] = category
    ? [category]
    : filter
      ? FILTER_CATEGORIES[filter].filter((c) => CATEGORIES_BY_ROLE[role].includes(c))
      : [...CATEGORIES_BY_ROLE[role]];

  return { text, category, categories, filter, limit };
}

const service = new SearchService();

export class SearchController {
  search = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const role = req.ctxRole;
      if (!isSearchRole(role) || !req.userId || !req.ctxId) {
        throw new SearchRequestError(403, 'search_not_available', 'Search is not available for this workspace.');
      }
      const request = parseSearchRequest(req.query as Record<string, unknown>, role);
      const results = await service.search(
        {
          userId: req.userId,
          role,
          ctxType: req.ctxType,
          ctxId: req.ctxId,
          ctxPropertyId: req.ctxPropertyId ?? null,
        },
        request,
      );
      res.set('Cache-Control', 'no-store');
      res.json({
        data: {
          query: request.text,
          category: request.category,
          filter: request.filter,
          categories: CATEGORIES_BY_ROLE[role],
          filters: FILTERS_BY_ROLE[role],
          results,
        },
      });
    } catch (err) {
      next(err);
    }
  };
}
