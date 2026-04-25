# reMarkable News Delivery

Fetches news daily and delivers it to your reMarkable tablet as EPUBs,
without needing an always-on machine of your own. A free GitHub Actions
job runs once a day, builds an EPUB per publication using
[Calibre](https://calibre-ebook.com/)'s news recipes, and uploads each
one to your reMarkable cloud via
[`rmapi`](https://github.com/ddvk/rmapi). Your tablet picks them up
the next time it has WiFi.

## How it works

```
┌─────────────────────┐   1. cron-triggered (10:30 UTC daily)
│   GitHub Actions    │
│                     │   2. install Calibre + rmapi
│   ubuntu-latest     │
│                     │   3. for each publication in recipes.txt:
│   ┌───────────────┐ │        ebook-convert <recipe> <output.epub>
│   │ Calibre       │ │
│   └───────────────┘ │   4. rmapi put <epub> /News/
│   ┌───────────────┐ │
│   │ rmapi         │ │
│   └───────────────┘ │
└──────────┬──────────┘
           │
           ▼
   reMarkable Cloud  ───────►  Tablet syncs over WiFi
```

The workflow runs at **10:30 UTC** daily, which lands the EPUB on your
reMarkable cloud well before 6:00 AM Mountain Time year-round. The
tablet downloads it the next time it joins WiFi.

## One-time setup

### 1. Create your repository

Either fork this repo or create a new public repo in your account and
copy these four files into it:

```
.github/workflows/news.yml
fetch-news.sh
recipes.txt
README.md
```

Public is recommended because GitHub Actions minutes are unlimited on
public repos. Your `RMAPI_CONFIG` secret stays encrypted regardless of
repo visibility.

### 2. Install rmapi on a local machine

You need to run `rmapi` once locally to pair it with your reMarkable
account; the resulting config file is what GitHub Actions will use.

- **macOS:**
  ```
  brew install io41/tap/rmapi
  ```
- **Linux:** if Go is installed,
  ```
  go install github.com/ddvk/rmapi@latest
  ```
  Otherwise grab a binary from
  [github.com/ddvk/rmapi/releases](https://github.com/ddvk/rmapi/releases).
- **Windows:** download a binary from the same releases page.

### 3. Pair rmapi with your reMarkable account

Run `rmapi` in a terminal. The first time it runs, it will prompt you
for an 8-character one-time code. To get one, log in at
[my.remarkable.com](https://my.remarkable.com) and look for the option
to connect a desktop or third-party app — it will display a code there.
Paste it into the rmapi prompt.

If pairing succeeds, you should see an `rmapi >` prompt. Type `ls` to
confirm it can list your reMarkable files, then `exit`.

### 4. Copy the rmapi config into a GitHub secret

The pairing step above wrote a small config file containing your
device token. Find it at:

- macOS / Linux: `~/.config/rmapi/rmapi.conf`
  (older versions use `~/.rmapi` instead)
- Windows: `%USERPROFILE%\.config\rmapi\rmapi.conf`

Print its contents:

```
cat ~/.config/rmapi/rmapi.conf
```

You'll see something like:

```
devicetoken: eyJ...long string...
usertoken: eyJ...another long string...
```

Now, in your GitHub repo, go to **Settings → Secrets and variables →
Actions → New repository secret**:

- **Name:** `RMAPI_CONFIG`
- **Value:** paste the entire contents of the file (both lines)

Save.

> The token is scoped to a "device" registration on your account. You
> can revoke it any time from my.remarkable.com if you ever want to
> rotate or disable this setup.

### 5. Test the workflow manually

In your repo, go to **Actions → Daily News Delivery → Run workflow →
Run workflow**. The first run takes about 5–10 minutes (Calibre install
is the slow part). Watch the log; if everything works, you'll see
something like:

```
===== Summary =====
Successes (1):
  ✓ NPR
Failures  (0):
```

Connect your reMarkable to WiFi and the new EPUB should appear in a
folder called `News` within a minute or two.

After this passes once, the daily schedule will take care of itself.

## Adding more publications

Edit `recipes.txt` and add a line per publication. The format is:

```
<recipe-slug>  <display name>
```

The recipe slug is the filename (minus `.recipe`) of any file in
[Calibre's recipes folder](https://github.com/kovidgoyal/calibre/tree/master/recipes).
A few that have worked well as free sources:

```
guardian       The Guardian
ap             Associated Press
bbc            BBC News
reuters        Reuters
propublica     ProPublica
aljazeera      Al Jazeera
```

Commit and push; the next scheduled run picks it up.

## Things to know going in

- **The daily file accumulates.** Each run uploads a new file with
  today's date in the name, so over time you'll build up a stack of
  back issues on the tablet. Delete old ones manually, or let me know
  if you want automated cleanup added.
- **The tablet must connect to WiFi to receive the day's sync.** There
  is no offline magic.
- **Recipes occasionally break.** When a publisher redesigns their
  site, the matching Calibre recipe can break for a few days until the
  Calibre maintainers update it. Re-running the workflow later usually
  picks up the fix automatically since we download recipes fresh on
  every run.
- **`rmapi` depends on a reverse-engineered API.** If reMarkable
  changes their cloud sync protocol server-side, uploads can break
  until the `ddvk/rmapi` fork catches up. Historically this has
  happened roughly once a year and gets fixed within days to a few
  weeks. There is no SLA here — this is community software.
- **The 50-day cloud retention rule.** reMarkable's free cloud tier
  deletes files that go untouched for 50 days. As long as you're
  reading the news regularly this won't bite you, since opening a file
  on the tablet counts as activity.

## Troubleshooting

**`RMAPI_CONFIG secret is not set`** — you skipped step 4 above, or the
secret name is misspelled. It must be exactly `RMAPI_CONFIG`.

**`failed to build documents tree` or HTTP 401/403 from rmapi** — your
device token has been invalidated. Re-pair `rmapi` locally (step 3)
and update the GitHub secret with the new config contents.

**Calibre exits with errors specific to one publication** — that
publisher's site likely changed. Wait a day or two and re-run; the
Calibre maintainers usually patch popular recipes quickly. If a
particular recipe stays broken for over a week, comment it out of
`recipes.txt`.

**Empty or near-empty EPUB** — some sites limit non-logged-in scraping.
NPR, the Guardian, AP, Reuters, and the BBC have generally been
reliable as free sources.

**Workflow ran but nothing appeared on the tablet** — make sure WiFi is
on and give it a minute. The tablet only syncs when connected. If
files are visible at my.remarkable.com but not on the tablet, force a
sync from the tablet's settings.
