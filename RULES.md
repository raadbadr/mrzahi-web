# MrZahi Website — Immutable Rules

These rules apply to every AI agent, developer, and automated tool working on this project.
**No exceptions without explicit written approval from المهندس رعد.**

---

## IMMUTABLE COMPONENTS — Never Touch Without Explicit Approval

| File / Path | What it is | Why it's locked |
|---|---|---|
| `mrzahi-icon.ico` | Website favicon | Brand identity — the Mr.Zahi "M" icon (white striped M on brand blue), linked with `?v=2`. Never replace. |
| `mrzahi-icon-32.png` / `mrzahi-icon-16.png` | Favicon 32px / 16px | Brand identity — same source as mrzahi-icon.ico |
| `mrzahi-icon-180.png` | iOS home screen icon (apple-touch-icon) | Brand identity — same source as mrzahi-icon.ico |
| `mrzahi-logo-dark.png` / `mrzahi-logo-light.png` | Small "T" brand mark | Brand identity — used by `brand-logo.js` and the header/footer |
| `mrzahi-logo-full-dark.png` / `mrzahi-logo-full-light.png` | "MrZahi" wordmark | Brand identity — the only approved wordmark files |
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

- **Every push to `main` auto-deploys** via GitHub Actions (`deploy.yml`) + `wrangler deploy` to the Worker `thetracker` (`mrzahi.com` + `www.mrzahi.com`)
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

- Wordmark is "MrZahi": `mrzahi-logo-full-dark.png` (dark theme) / `mrzahi-logo-full-light.png` (light theme)
- Mark is the letter "T": `mrzahi-logo-dark.png` / `mrzahi-logo-light.png`
- Favicon must always be the Mr.Zahi "M" icon set (`mrzahi-icon.ico`, `mrzahi-icon-32.png`, `mrzahi-icon-16.png`, `mrzahi-icon-180.png`), linked with `?v=2` on every HTML page
- Never replace `mrzahi-icon.ico`, `mrzahi-icon-32.png`, `mrzahi-icon-16.png`, or `mrzahi-icon-180.png` with any other asset without explicit approval
- `brand-logo.js` replaces "MrZahi" text nodes with the logo image — never disable or remove it
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
  The old domain served until the move; it was retired entirely on 2026-09-11 (see below). There is no third domain.
- **It will be linked with Eng. Raad's "Zahi" project, which becomes the reminder project.**
  Nothing about that link is to be assumed — scope, boundaries and shape come from him directly
  before any work starts on it.
- **Status (2026-09-06, later): the move is done — mrzahi.com is the site.** appmails.net now
  answers every page with a 301 to the same path on mrzahi.com (verified on /, /pricing,
  /app/dashboard, /privacy and www). Only `/api/*` still answers on the old host, deliberately,
  because the Telegram webhook still points there and a POST does not follow a redirect; that
  exception is removed the moment the webhook moves.
- **Remaining, and only Eng. Raad can do them**: Google Search Console domain verification for
  mrzahi.com (TXT record via Cloudflare), then the consent screen (name MrZahi, home
  https://mrzahi.com, privacy /privacy, terms /terms — the terms field wrongly points at
  /privacy today) and authorised domain, then the OAuth client's JavaScript origins, then
  Supabase Site URL and redirect URLs. Until the origins are added, Google sign-in will fail on
  the new domain.
- **The new bot** @mrzahibot has been created; its token and username go into the Worker secrets
  by his own hand, then the webhook moves to https://mrzahi.com/api/telegram/webhook and the
  four existing links are re-made from the settings page.
- **Earlier status: the move has started and the new domain is live.** mrzahi.com and
  www.mrzahi.com are bound to the Worker `thetracker` as custom domains and serve every path;
  all 186 internal references (canonical, Open Graph, sitemap, robots, manifest, bot links,
  calendar, MCP endpoint, assistant answers) now point at mrzahi.com.
- **Status (2026-09-11): the old domain appmails.net is retired entirely** on Eng. Raad's order
  ("الدومين دا الغيه تماما"): both custom domains detached from the Worker, routes removed from
  wrangler.toml, CORS origins and the redirect branch removed, docs and the email function point
  at mrzahi.com. Nothing in the repository names it any more. Anything outside the repository
  that still names it (Google OAuth origins, Supabase Auth URLs, DNS zone) is his to clean.
- **Three steps remain and only Eng. Raad can do them** (each is his own account, not ours):
  Google OAuth authorised JavaScript origins and redirect URIs, Supabase Auth redirect/site
  URLs, and repointing the Telegram webhook at mrzahi.com.
- **The two projects merge into one under mrzahi.com**: MrZahi and Eng. Raad's Zahi robot
  project become one product — the robot backed by the platform, the platform as its reminder
  brain. Agents on either side coordinate before touching shared surfaces (domain, Worker,
  Supabase, bot). Nothing about the Zahi side is assumed: its scope, data and boundaries come
  from Eng. Raad or from its own agents, never invented here.
- No agent starts the remaining migration steps, buys, binds or changes any DNS/Worker route
  without a direct instruction from him naming the step.

### Zahi device — facts received from its firmware session (2026-09-06, information only)

Recorded so no agent invents them. **Nothing here is built without a direct instruction from
Eng. Raad**; the three decisions below are his.

- Zahi is a desk robot on an ESP32-S3 with a 480×480 touch screen, firmware `Zahi-Touch.ino` in
  `/Users/Raad/Documents/Arduino/ZahiRobot`. One of its seven screens shows appointments.
- It **receives** appointments, it cannot fetch them: `POST /cal` on the device's own address, or
  a `CAL:` line over USB, body `epoch|title;epoch|title`. Clock is set with a `T:` line.
- Hard limits: **4 appointments**, **83 bytes** per title, **local epoch (not UTC)**, and an entry
  drops 30 minutes after it passes.
- Arabic must arrive **already shaped and visually ordered** — the device's fonts do not join
  letters or handle direction. Today that is done on the Mac with arabic_reshaper and bidi.
- The firmware has **no TLS client, no HTTPClient and no NTP**: it cannot pull from mrzahi.com at
  all. Pulling would require new firmware.
- Its text rules match ours: no diacritics, western digits; and its screen carries no English.

Consequence worth stating plainly: a Worker in Cloudflare cannot reach a device on a home
network by itself. Push from the platform therefore needs either a bridge process on the Mac
holding the account token, or a tunnel giving the device a public address.

**A rule conflict he must settle** (raised by the firmware session, not by us): our rule forbids
`text-overflow: ellipsis` and forbids cutting text in code — the information is shown whole. The
device holds 83 bytes per title and four appointments. Either the device screen is treated as a
different surface with its own limit, or the platform sends a deliberately short wording that
was written short (not a cut title), or long items simply do not go to the device.

Shaping is not a conflict: what the platform stores and shows stays logically ordered and
unshaped, exactly as our rules require; the presentation-form and visual-order conversion
belongs to the moment of sending to the device, on whichever side owns the bridge. No diacritics
and western digits are identical rules on both sides.

Open for Eng. Raad alone: push or pull; whether a "device" channel joins the notification
channels; who owns the bridge that holds the token; and the title-length conflict above.

### Why these "small" faults keep appearing after a domain move (2026-09-06)

Every one of today's faults had the same shape: **something outside the repository still points
at the old host**. The code was right; the environment was stale. Sign-in stopped landing on the
dashboard because Supabase's Site URL and Redirect URLs still name appmails.net, so Supabase
sent the user to the home page instead of the path the app asked for. Nothing in the diff could
have shown that.

The rule for any agent touching a domain, a host or a provider from now on:

1. **List the external settings before declaring a move done.** For this platform they are:
   Google OAuth authorised JavaScript origins and redirect URIs; the Google consent screen's
   home, privacy and terms links and its authorised domain; Google Search Console verification;
   Supabase Auth Site URL and Redirect URLs; the Telegram webhook; and the MCP endpoint given to
   clients. Each is owned by Eng. Raad's account, so name them for him one by one — do not
   assume any of them followed the code.
2. **Make the app survive the stale setting** where it can be done without hiding the fault: the
   sign-in return now lands on the dashboard even when the provider drops the user on the home
   page, and it only acts when the URL actually carries an auth return (access_token or code).
3. **Verify by using the thing, not by reading it.** A 301 that answers correctly to curl says
   nothing about whether Google will accept the origin.

## No Generalising, No Inferring — a procedure, not a slogan (2026-09-06)

- **The scope is exactly what he named**: that screen, that element, that file. Anything outside
  the name is forbidden, however related it looks.
- **The shared function is the trap.** `loadItems` on the dashboard serves the dashboard, cases,
  violations and expenses; one line there applies a one-screen instruction to all four. If the
  instruction names one screen, gate the change on that screen (`state.viewType === "..."`) —
  never put it in the shared function. If it cannot be gated, ask one short question first.
- **Ask before every deploy**: who is affected by this line besides the thing he named? If the
  answer is "someone else", the change is wrong and goes back.
- Origin: "take them off the dashboard", said about document items, was applied to four screens;
  a user's data vanished from his lists and he thought the domain move had lost it.
