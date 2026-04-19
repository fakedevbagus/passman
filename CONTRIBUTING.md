# Contributing to Passman

Thank you for investing your time in contributing to our project!

## Development Setup
1. Clone the repository.
2. Ensure you have Node v20+ and PostgreSQL.
3. Run `npm install` in the root folder. Postinstall hooks will automatically bootstrap the `/client` and `/server` child directories for you.
4. Run `npm run dev` to start both local environments simultaneously.

## Coding Rules
- **Formatting Policy:** We enforce Prettier/ESLint defaults in Next.js and standard TS config conventions locally.
- **Client Render Guarantee:** Components invoking `window.crypto.subtle` must be flagged `"use client"` and heavily guarded via hydration hooks (such as `useEffect(() => setMounted(true))`).
- **No Extraneous Imports:** Since UI targets a sleek, bespoke enterprise aesthetic, refrain from introducing monolithic component libraries. Rely on Tailwind utilities.
- **Never Log Secrets:** Do not commit `console.log` statements containing `ciphertext`, `masterPassword`, or `secret_keys`. Treat logs with highly sensitive operational security rules.

## Opening Pull Requests
- Provide a summary describing the core functionality.
- If it includes UI adjustments, provide a screenshot.
- Keep pull requests confined to atomic chunks. Do not overlap multiple unrelated issue fixes inside the same PR.
