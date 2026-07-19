# buildarken

This repo is ONLY the main marketing site: landing page, navbar, footer, and
the vercel.json that stitches the independent tool deployments together
under this domain (Next.js Multi-Zones pattern).

It intentionally does NOT contain any tool's source code. Compare, Chat, and
Code Check each live in their own separate repo/Vercel project and are
proxied in via the rewrites below — this repo just needs to know their
deployed URLs.

## Setup

1. Deploy this repo to Vercel as its own project (this becomes buildarken.com).
2. Deploy `arken-compare-zone`, `arken-code-check-zone`, and the chat app as
   their own separate Vercel projects.
3. Edit `vercel.json` here, replacing the three placeholder URLs with the
   real `.vercel.app` (or custom) URLs from step 2.
4. Redeploy this repo. buildarken.com/compare, /code-check, and /chat will
   now transparently proxy to those projects while staying on this domain.

## Adding a new tool later

1. Build it as its own independent repo/Vercel project.
2. If it's a Next.js app, set `basePath: '/<tool-name>'` in its next.config.
3. Add one rewrite entry here pointing `/<tool-name>/:path*` at its deployed URL.
4. Add a card for it in index.html's product grid.

No changes needed to any other tool when adding a new one — that's the
whole point of keeping them independent.
