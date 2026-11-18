# Seaside Seating Planner

A wedding seating planner in one static file, `index.html`. No build step today.
It was built as a Claude artifact. It's moving to Vercel so the couple (Yu Zon and her partner) can both use it, and the partner doesn't use Claude.

## Your job in this session, in order

1. **Deploy** this folder to Vercel as a static production site. Run "Verify after deploy". Report the URL.
2. **Build the shared online save** described below, so both partners see and edit the same plan from the Vercel URL. This is required.
3. Redeploy, run "Verify after deploy" and "Sync acceptance tests", and report results.

Ask the user before creating accounts, projects, repos or turning on paid features. You'll need from them:
- A Supabase account (free tier is enough), or permission to walk them through creating one.
- The two email addresses allowed to edit the plan.

## Hard rules

- Keep it a static site: `index.html` plus, if needed, a small `config.js`. No framework, bundler or package.json unless the user asks.
- Never commit guest data. Plan files (`seating-plan-*.json`), spreadsheets and CSVs are personal data; `.gitignore` covers them. Never seed the database with real names from files; the user loads her plan through the app.
- Keep `index.html` ASCII-only: non-ASCII as `\uXXXX` in JavaScript and `&#xXXXX;` in HTML (prevents garbled symbols). Check:
  `python3 -c "s=open('index.html',encoding='utf-8').read();print(all(ord(c)<128 for c in s))"`
- After any edit, syntax-check the script:
  `python3 -c "s=open('index.html').read();open('/tmp/a.js','w').write(s.split('<script>')[1].split('</script>')[0])" && node --check /tmp/a.js`
- Don't change the plan document format (`version: 3`) without a migration in `Domain.valid`/`Domain.sanitize`. Layout files the couple already saved must keep opening.
- The file also contains Claude-only code (`window.claude`). In this build it's switched off by `const FEATURES = {changeBox: false, familyReview: false, accountSave: false}` at the top of the script. Leave those off: the user doesn't want "Make a change", "Share for review" or "Save to account" here. Don't delete that code; it's shared with the Claude version.
- Keep `noindex` (meta tag in `index.html`, header in `vercel.json`).
- Never put a Supabase service-role key in the page. The anon key is fine because Row Level Security protects the data.

## Deploy

From this folder:

```
npx vercel login
npx vercel --prod
```

Framework preset "Other", no build command, output directory `.`.
Or push to a private GitHub repo and import at vercel.com/new with the same settings.

## Shared online save (required)

### Behaviour the couple should get
- Both open the same Vercel URL and sign in with their email (magic link, no password).
- The plan saves to the cloud a couple of seconds after each change, and the other person's screen updates within a few seconds.
- If both edit at once, nobody's work is silently lost: the second saver sees "Your partner saved a newer version" with "Load theirs" or "Keep mine (overwrite)".
- Offline or signed out, it keeps working and saves in the browser, then syncs when back.
- Anyone else who finds the URL sees a sign-in screen and can't read the plan.
- "Download layout file" and "Open saved plan" stay as a backup.

### Suggested design (confirm with the user, then build)

Supabase project, SQL editor:

```sql
create table public.plans (
  id text primary key,
  json jsonb not null,
  rev bigint not null default 1,
  updated_at timestamptz not null default now(),
  updated_by text
);
create table public.plan_members (
  plan_id text not null references public.plans(id) on delete cascade,
  email text not null,
  primary key (plan_id, email)
);
alter table public.plans enable row level security;
alter table public.plan_members enable row level security;

create policy "member reads own membership" on public.plan_members
  for select using (email = auth.jwt() ->> 'email');
create policy "members read plan" on public.plans
  for select using (exists (select 1 from public.plan_members m where m.plan_id = plans.id and m.email = auth.jwt() ->> 'email'));
create policy "members update plan" on public.plans
  for update using (exists (select 1 from public.plan_members m where m.plan_id = plans.id and m.email = auth.jwt() ->> 'email'))
  with check (exists (select 1 from public.plan_members m where m.plan_id = plans.id and m.email = auth.jwt() ->> 'email'));

-- one plan row (empty until the user uploads hers from the app) and the two members
insert into public.plans (id, json) values ('our-wedding', '{}'::jsonb);
insert into public.plan_members values ('our-wedding', '<email 1>'), ('our-wedding', '<email 2>');
```

Enable Realtime on `public.plans`. In Auth settings, add the Vercel URL to the redirect URLs and set the Site URL.

Client:
- Load `@supabase/supabase-js` v2 UMD from jsDelivr or cdnjs with an exact pinned version (check the real path, for example `.../dist/umd/supabase.js`). Put `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `PLAN_ID` in `config.js`, loaded before the main script.
- Add a new script section `15. SHARED SYNC` before `14. BOOT`, with a small `Sync` object:
  - `signIn(email)`: `auth.signInWithOtp({email, options: {emailRedirectTo: location.origin}})`. Show a simple sign-in card on first visit (reuse `.card`, `.field`, `button.primary` styles). Show "Signed in as …" and a "Sign out" button in the More menu.
  - `pull()`: select the row. If `json` is empty, offer to upload this browser's plan. If local is empty, load remote. If remote `rev` is newer than the last `rev` seen and local has unsynced edits, show the existing `#cloud-note` banner (text in `#cloud-note-t`, buttons `#cloud-load` / `#cloud-dismiss`) with "Load theirs" / "Keep mine".
  - `push()`: `update plans set json, rev = rev + 1, updated_by = email where id = PLAN_ID and rev = lastRev`. Zero rows updated means a conflict: pull and show the banner. Never overwrite blindly.
  - Realtime: subscribe to updates on the row. If there are no unsynced local edits, load the new version straight away (keep the current view and selection if possible). Otherwise show the banner.
- Hooks already in `index.html`:
  - `persist()` (section 8) runs after every change. Add a debounced `Sync.schedule()` call there (2 to 3 s), next to the existing `scheduleCloud()` call, which does nothing in this build.
  - `renderSave()` (section 13g) writes the status under the title (`#save-pill`). Make it show: "Signed out: saved in this browser", "Saving…", "Synced", "Offline: saved in this browser", "Couldn't sync. Retrying".
  - Loading a plan: reuse `loadLayoutText(text)` (section 13g). It validates, swaps the document into `S`, records undo and re-renders.
- Exclude nothing from the synced JSON except the floor plan image, which isn't in `S` anyway (it lives in localStorage key `seaside-seating-img`).
- Scenarios (saved versions to compare) live in `S.scenarios` and should sync too, so both partners can compare the same options. Each scenario is a full copy of the plan, so a document with several scenarios can reach 0.5 to 1 MB. That's fine for jsonb; if pushes get slow, debounce longer rather than dropping scenarios.
- Size: a plan with about 150 guests is roughly 60 to 100 KB of JSON without scenarios.

### Sync acceptance tests
Use two browsers (or one normal plus one private window) signed in with the two member emails.
1. A: Open saved plan (a layout file). B sees the same plan within about 5 s, or after a reload.
2. A renames a table. B sees the new name and seat IDs within about 5 s.
3. Both edit at the same moment. One of them gets the banner, and choosing either option leaves both browsers showing the same plan. Nothing is lost silently.
4. Turn A's network off and move a guest. The status says saved in this browser. Network on: it syncs, and B gets the change.
5. A third email that isn't a member can't read the plan. Check in the Supabase table editor as that user, or with the anon key and that user's session.
6. Sign out, reload: sign-in card shows, and no guest names are visible before signing in.
7. A saves a scenario (Scenarios, Save). B sees it under Scenarios and can compare it with the current plan.

## Verify after deploy

Open the production URL in a normal browser and a private window.
1. Page loads with no console errors. Layout and fonts look right.
2. Step 1: "Try a sample list", then "Continue to rules"; step 2 Approve; step 3 steppers update the preview and the seat count; Next opens the canvas with everyone seated.
3. Canvas: hovering a chair shows its seat ID (like T3-03) and reasons; clicking a table scrolls the seat chart to it; Rename and Swap on a seat chart card work; Undo reverts.
4. "Make a change", "Share for review" and "Save to account" are not visible.
5. Seat chart "Download" saves an .xlsx with tabs Seat chart, Guests A-Z, Tables.
6. More, then "Download layout file", saves a .json. In a private window, step 1 "Open saved plan" with it restores the same plan.
7. Reload keeps the plan.
8. Scenarios: save "Option A", swap two tables, open Scenarios and Compare. The compare view shows scores for both, two mini plans with moved guests ringed in amber, and the list of who moved. "Use this layout" switches to it, and Undo switches back.

## How the code is organised

Everything is in the `<script>` at the end of `index.html`, in numbered sections:

| Section | What it does |
|---|---|
| 1. CONFIG | `FEATURES` switches, component registry `TYPES`, `TABLE_SHAPES`, `PALETTE` |
| 2. HELPERS | `$`, `esc`, `uid`, `clamp`, `seatId(table, i)` gives "T3-03" |
| 3. GEOMETRY | Table sizes from seat counts, chair positions, rotation maths (metres) |
| 4. DOMAIN | Pure rules: `sanitize`, `seatMap`, `place` (swap on taken seat), `ranks`, `check`, `autoSeat` (subgroup then group, tiers, together/apart) |
| 5. IMPORT | `Importer.parse` (header aliases incl. "Group specifics" for Subgroup, "X +1 (Y)"), `Extractor.run` |
| 6. LAYOUT | `Layout.build(venue)`: beach deck, open hall, uploaded plan |
| 7. SAMPLE | Made-up sample guest list |
| 8. STORE | One document `S`; every change goes through `commit()` (undo, `persist()`, re-render) |
| 9. CANVAS RENDERER | SVG drawing |
| 10. SHELL AND WIZARD | Steps 1 to 3 |
| 11-12. EDITOR | Canvas, inspector, seat chart, guests and rules tabs, clear/swap/rename tables |
| 13. INTERACTION | Pointer controller: drag tables, guests, palette items, table swaps |
| 13b-13d | Seat reasons; plain-language changes and `Domain.repair` (change box UI is off in this build) |
| 13e | Family review (Claude only, off) |
| 13f | Floor plan upload (image backdrop; Claude conversion falls back to tracing) |
| 13g | Save status `renderSave`, Excel export, layout file download/open, `browserDownload` |
| 13h | Scenarios: `S.scenarios`, `Domain.metrics`, compare view (`openCompare`, `renderCompare`). Scenarios are left out of undo history (`snap()` skips them) |
| 14. BOOT | Initial render, applies `FEATURES` |

Plan document (also the layout file):

```
{ version: 3, step, venueDone, savedAt,
  elements: [{id, type, x, y, w, h, rot, label, locked, anchor, shape?, seats?}],   // metres
  groups:   [{id, name, color}],
  guests:   [{id, name, groupId, sub, tier (0 main, 1 vip, 2 guest), notes}],
  rules:    [{id, type: "together"|"apart", a, b, note}],
  candidates: [...rules awaiting approval in step 2],
  seating:  { guestId: {t: tableId, s: seatIndex} },
  venue:    {base, main, stage, dance, rows:[{id, shape, tables, seats, label?}], upload?},
  settings: {snap, primeCount}, backdrop?,
  scenarios: [{id, name, savedAt, doc: {...same shape without scenarios}}] }
```

## Status of the shared online save (built)

- Code: section `15. SHARED SYNC` in `index.html` (`Sync` object), sign-in screen `#gate`, account row `#m-acct` in More.
- Settings: `config.js` (`window.SEATPLAN_CONFIG`). Empty `SUPABASE_URL` turns sync off and the app behaves as before.
- Database: `supabase/setup.sql`. Replace the two placeholder emails before running it; don't commit real emails.
- Browser cache for sync: localStorage `seaside-sync-v1` = `{plan, rev, dirty, fresh, email, json}`. `json` holds the full plan including scenarios.
- Sign out clears this browser's copy of the plan so no guest names are left behind.

## Brand: Seat The Plan

- Name: Seat The Plan. Tagline: "Less seating stress. More wedding bliss." Script line: "Make room for the magic."
- Palette: sage #6B8F71 (buttons use #5E8164 for contrast), olive #A9B8A0, blush #E8C9C3, cream #F8F6EF, beige #E6DDCF, ink #3D4637.
- Type: Fraunces for headings and the wordmark, Nunito Sans for body and UI, Dancing Script only for the script line.
- The app uses the same palette, including the floor plan (tables, walkways, water, trees) and group colours (`GROUP_COLORS`). Plans saved with the old default group colours are switched to the new ones once, flagged by `settings.brandColors`.
- Mascot: Mr Table (`mascotSvg({mood, sign})`, moods happy, wink, think, cheer). Pill buttons, line icons.
- The front page lives in `#gate` (section `15b. LANDING`): `showLanding("signin")` when online sync is on and nobody is signed in, `showLanding("start")` for a brand-new local plan. It never shows guest data.
- Storage keys still start with `seaside-`. Don't rename them, or saved plans in browsers are lost.

## Commits and pull requests

- No Claude attribution: no Co-Authored-By, Claude-Session or "Generated with Claude Code" lines in commit messages or PR descriptions.
