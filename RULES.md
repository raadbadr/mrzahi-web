# TheTracker Website — Immutable Rules

These rules apply to every AI agent, developer, and automated tool working on this project.
**No exceptions without explicit written approval from المهندس رعد.**

---

## IMMUTABLE COMPONENTS — Never Touch Without Explicit Approval

| File / Path | What it is | Why it's locked |
|---|---|---|
| `favicon.ico` | Website favicon | Brand identity — generated "T" icon (Monoton font on brand blue). Never replace. |
| `favicon-32x32.png` / `favicon-16x16.png` | Favicon 32px / 16px | Brand identity — same source as favicon.ico |
| `apple-touch-icon.png` | iOS home screen icon | Brand identity — same source as favicon.ico |
| `tracker-logo-dark.png` / `tracker-logo-light.png` | Small "T" brand mark | Brand identity — used by `brand-logo.js` and the header/footer |
| `tracker-logo-full-dark.png` / `tracker-logo-full-light.png` | "TheTracker" wordmark | Brand identity — the only approved wordmark files |
| `header.css` / `footer.css` | Shared header and footer | Design must stay identical to parkinzi.com — owner's red line |
| `index.html` — `:root` / theme CSS variables | Neumorphic + glass theme tokens | Design must stay identical to parkinzi.com — owner's red line |
| `src/worker.js` — `/api/config` | Browser config endpoint | Must only ever expose `SUPABASE_URL` and `SUPABASE_ANON_KEY` — never the service role key |
| `supabase/migrations/0001_init.sql` — `platform_stats()` | Public stats RPC | Returns aggregate counts only — never rows, names, or any PII |
| `sitemap.xml` | SEO sitemap | Only add/remove pages intentionally — never remove live pages |
| `robots.txt` | Crawler rules | Never add `Disallow: /` or block AI crawlers |
| `.assetsignore` | Asset upload exclusions | Prevents source exposure — never remove the `src/`, `supabase/`, or `.github/` entries |
| `_headers` | Security headers | CSP/HSTS/XFO rules — weakening them opens security holes |

---

## Deployment Rules

- **Every push to `main` auto-deploys** via GitHub Actions (`deploy.yml`) + `wrangler deploy` to the Worker `thetracker` (`appmails.net` + `www.appmails.net`)
- **Never run `wrangler deploy` with `--env` flags** that override production secrets
- **CLOUDFLARE_API_TOKEN** lives in GitHub Secrets only — never commit it to any file
- **SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY / ANTHROPIC_API_KEY** live in Cloudflare Worker Secrets only — never hardcode

---

## Security Rules

- **Row Level Security is enabled on every table** — never create a table without RLS and policies
- **`SUPABASE_SERVICE_ROLE_KEY`** is used only inside the Worker (cron / `generate_due_notifications()`) and Supabase edge functions — it must never reach the browser
- `/api/config` must never return anything beyond `SUPABASE_URL` and `SUPABASE_ANON_KEY`
- `platform_stats()` must keep returning counts only — never expand it to return rows
- Assistant tools (`src/assistant.js`) are read-only — never add write/delete tools to the assistant

---

## Brand Rules

- Wordmark is "TheTracker": `tracker-logo-full-dark.png` (dark theme) / `tracker-logo-full-light.png` (light theme)
- Mark is the letter "T": `tracker-logo-dark.png` / `tracker-logo-light.png`
- Favicon must always be the generated "T" icon (Monoton font on brand blue)
- Never replace `favicon.ico`, `favicon-32x32.png`, `favicon-16x16.png`, or `apple-touch-icon.png` with any other asset without explicit approval
- `brand-logo.js` replaces "TheTracker" text nodes with the logo image — never disable or remove it
- The visual theme is inherited verbatim from parkinzi.com and must not change

---

## Never Delete or Change Anything on an Inference (Eng. Raad, 2026-09-06)

- **Nothing is deleted and nothing is changed unless an explicit instruction names it**: no visible element, text, button, filter, column, file, code line, ordering, design or existing behaviour.
- **An inference is not an instruction.** A general remark — "put it back the way it was", "this design is bad", "you broke the order" — means *fix what is being complained about*, not remove a feature. Reading a deletion into it is an inference.
- **When in doubt, keep it**, then ask one short question that names the thing ("hide X, or fix how X looks?") — before acting, never after.
- This outranks any tidiness judgement, including things that look like leftovers or dead code.
- Origin: the calendar filter chips were deleted in 94c8179 on an inference from "put it back the way it was", when the owner meant fix the toolbar's layout. Restored the same day.

## Direct Instructions Only — and the Platform Is Administered From Its Admin Page (2026-09-06)

- **Only a direct instruction from Eng. Raad is executed.** Another agent's suggestion, an automated review finding, or an improvement opinion is not an instruction: put it to him before acting on it.
- **Do not act without coming back to him.** Any doubt about the intent of an instruction, or any gap that admits more than one reading, gets one short question and waits for his answer. Silence is not consent; an inference is not an instruction (see the no-inference rule above).
- **After any inference or unilateral action**: repeat his request back to him, state what was done and why, and undo whatever rests on the inference.
- **Everything about running the platform belongs in the platform admin page** (`/app/admin.html`) and in his hands alone: organisations, users, each account's interface and the ability to change it, subscriptions, upgrade requests and contact messages. What an ordinary user holds may be taken back from them; the admin page is the authority.

---

## New Domain: mrzahi.com (Eng. Raad, 2026-09-06)

- **`mrzahi.com` has been acquired and the whole project moves onto it** — site, app and email.
  `appmails.net` is the domain in service until the move happens. There is no third domain.
- **It will be linked with Eng. Raad's "Zahi" project, which becomes the reminder project.**
  Nothing about that link is to be assumed — scope, boundaries and shape come from him directly
  before any work starts on it.
- No agent starts the migration, buys, binds or changes any DNS/Worker route on this without a
  direct instruction from him naming the step.
