# Contributing

1. Fork, then create a branch from `main`.
2. `npm install`, then make your change.
3. Add or update tests in `tests/` (add a regression test for every bug fix).
4. Run `npm run typecheck && npm test && npm run build` before opening a PR.
5. Never commit API keys, `.env*` files (except `.env.example`), or personal data.
