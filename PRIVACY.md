# Privacy

AI Usage Monitor is designed to run entirely on the user's Mac.

## Data processed

AI Usage Monitor asks the locally installed Codex app-server for usage-limit data. It
normalizes and displays quota names, used and remaining percentages, reset
times, banked reset summaries, connection state, and update time.

## Data stored

The app stores its appearance preference, notification boundary state, and a
small pace-estimation history in local user defaults. The pace history is
limited to 64 samples per quota bucket. AI Usage Monitor does not add analytics,
advertising identifiers, or telemetry.

## Widget data

The menu bar app provides the widget with a normalized snapshot through an
HTTP listener bound only to `127.0.0.1`. No credential, token, account record,
or raw app-server response is intentionally sent to the widget.

## Authentication

Codex owns sign-in and token refresh. AI Usage Monitor does not intentionally read
`~/.codex/auth.json`, request an API key, or store an access token.

## Network boundary

AI Usage Monitor itself does not add a third-party backend. The local Codex app-server
may communicate with OpenAI under the user's existing OpenAI account and
applicable terms. That traffic belongs to Codex, not to an AI Usage Monitor service.

Review the source before use and avoid sharing diagnostic output without
checking it first.
