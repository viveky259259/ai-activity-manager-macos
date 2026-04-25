# Press Blast — Embargoed Outreach

Send **5 working days before launch**. Embargo lifts the morning of the Show HN / Product Hunt go-live.

## Target list (first wave — 8 outlets)

| Outlet | Beat | Contact pattern | Notes |
|---|---|---|---|
| MacStories | Indie Mac apps, AppleScript, Shortcuts | `tips@macstories.net` + Federico Viticci on Mastodon | Will care about the Shortcuts/MCP composition story |
| Daring Fireball | Apple ecosystem editorial | `linked@daringfireball.net` | One-shot link if it's interesting; don't expect a reply |
| 9to5Mac | Apple news, daily | `tips@9to5mac.com` | Lead with privacy-first + on-device LLM |
| Six Colors | Mac/AI thoughtful coverage | `tips@sixcolors.com` | Jason Snell's audience — quality > novelty |
| The Verge — Tom Warren / Wes Davis | Mac/dev tools | Personal email if you have it; otherwise tips line | Tightly worded pitch only |
| Indie Mac Apps newsletter | Curated weekly | `hello@indiemacapps.com` | Pre-launch slot is gold |
| Latent Space podcast | AI infra & tooling | `swyx@latent.space` | The MCP angle plays well here — pitch as podcast guest |
| The Pragmatic Engineer | Eng leadership | Substack DM | Long-shot; only if the architecture story is tight |

## Pitch email — primary template

> **Subject:** Embargoed — open-source macOS app gives Claude a structured view of your Mac (launching [date])
>
> Hi [first name],
>
> Quick pitch under embargo until [date, time PT]:
>
> I'm launching **AI Activity Manager** — an open-source (MIT) macOS app that turns the running-process list, foreground-app history, and focus state into a structured surface that any MCP-compatible AI assistant can read, and (with explicit user opt-in) act on.
>
> Three beats I think your readers will care about:
>
> 1. **MCP-native, not bolted on.** The bundled stdio server (`activity-mcp`) ships with a typed `tools/list` of 12 calls, audited and rate-limited per client, gated on the same `ProcessTerminator` safety rails the GUI uses. Read paths are wide; write paths require a user-flipped toggle.
> 2. **On-device LLM by default.** Apple Foundation Models for timeline Q&A on macOS 26. The Anthropic provider is opt-in, key in Keychain, never set unless the user pastes one in.
> 3. **No telemetry, no App Store, no Pro tier.** Direct DMG, notarized, hardened runtime. Source MIT. The architecture call here is that App Store guideline 2.4.5 wouldn't let this kind of background helper exist anyway.
>
> Press kit: [link to docs/launch/press-kit.zip]
> 60-second demo (no voiceover): [link]
> Repo (will be public at embargo lift): [link]
>
> Happy to do a 15-min walkthrough this week if it'd help shape the story.
>
> — Vivek Yadav
> Maker · viveky259259@gmail.com

## Follow-up (T+3 days, only if no reply)

> **Subject:** Re: Embargoed — AI Activity Manager (launching [date])
>
> Hi [first name] — bumping this in case it slipped past. Embargo still holds until [date, time PT]. Happy to send the DMG ahead of the public link if that's useful for screenshots.
>
> — Vivek

## Press kit contents (ship as `docs/launch/press-kit.zip`)

```
press-kit/
  ABOUT.md                 ← 1-paragraph + 3-paragraph + boilerplate versions
  FACT_SHEET.md            ← stack, license, requirements, install, default safety
  FOUNDER_BIO.md           ← 100-word bio + headshot
  screenshots/
    01-overview.png
    02-mcp-claude-desktop.png
    03-mcp-cursor.png
    04-settings-permissions.png
    05-timeline-search.png
  logos/
    logo-512.png
    logo-1024.png
    logo-on-light.svg
    logo-on-dark.svg
  demo-60s.mp4
  demo-15s.mp4
  CHANGELOG.md             ← copy of repo CHANGELOG
  LICENSE                  ← MIT
```

## Boilerplate (stick at the bottom of every email)

> AI Activity Manager is an open-source (MIT) macOS app from independent developer Vivek Yadav. It combines a local activity timeline with a Model Context Protocol (MCP) server so AI assistants like Claude, Cursor, and Zed can answer questions about — and, with explicit user opt-in, act on — what's running on the Mac. Source: github.com/viveky259259/ai_activity_manager_macos. License: MIT. Requires macOS 26 for the UI app; macOS 13+ for the CLI and MCP server.

## Outreach checklist

- [ ] All emails personalized in the first sentence — *"loved your piece on [specific recent post]"*
- [ ] Embargo time is in **PT explicitly**; convert to UK/EU times for European outlets
- [ ] Press kit zip hosted on GitHub Release (private until embargo) — never on a personal Drive that requires sign-in
- [ ] Maintain a `press-blast.csv` tracking sent date / opened / replied / published — chase only the dead ones
- [ ] Day-of-launch: tweet the public release thread, then immediately email the embargoed list saying "embargo lifted, link is live"
