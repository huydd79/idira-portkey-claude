# idira-portkey-claude

A lab testing integration between **CyberArk Identity (idira)**, the
**Portkey AI Gateway**, and **Claude Code** — using a JWT issued by
CyberArk Identity (via OAuth2 Authorization Code + PKCE, no client_secret
required) to authenticate directly against Portkey instead of a static API
key, then wiring that JWT into Claude Code so it can call a real LLM
(Bedrock, routed through Portkey).

## How it works

```
                 1. open browser
                    SSO / MFA login
  Claude Code  ───────────────────────────▶  CyberArk Identity
 (apiKeyHelper)   (Authorization Code        (OIDC app, PKCE,
       │           + PKCE, no secret)         public client)
       │                                             │
       │ runs                                        │ 2. redirect back
       ▼                                              │    with auth code
 idira-get-jwt.sh                                     ▼
  - PKCE code_verifier/challenge        3. exchange code -> JWT
  - local callback listener                (code_verifier, no secret)
  - caches JWT at                               │
    ~/.cache/idira_auth/tokens.json             │
       │                                        │
       └───────────────◀── JWT (access_token) ──┘

       │
       │ 4. Authorization: Bearer <JWT>
       ▼
 ┌───────────────────────────────────────────────┐
 │               Portkey AI Gateway                │
 │  - verifies JWT signature via JWKS              │
 │  - reads custom claims: portkey_oid,             │
 │    portkey_workspace, scope                      │
 │  - routes request via a saved Config             │
 │    (x-portkey-config header)                     │
 └───────────────────────┬───────────────────────┘
                          │ 5. routed call
                          ▼
                 AWS Bedrock (Claude model)
                          │
                          ▼
                  response flows back to
                  Claude Code as a normal
                  /v1/messages reply
```

## Before you run this - read this first

The values in `idira-get-jwt.sh` (`CLIENT_ID`, `AUTHORIZE_URL`,
`TOKEN_URL`) and in `.claude/settings.local.json` (the Portkey config slug)
are hardcoded for **one specific existing lab environment** — a single
CyberArk Identity tenant and a single Portkey workspace. Cloning this repo
and running it as-is will **not work** without an account on that lab.

Want to try it quickly? Contact huydd@huydo.net to request a test account.

## Install

```bash
git clone git@github.com:huydd79/idira-portkey-claude.git
cd idira-portkey-claude
./install.sh
```

`install.sh` checks for the required tools (`curl`, `jq`, `nc`, `openssl`;
auto-installs missing ones via Homebrew if available), then symlinks
`idira-get-jwt.sh` into `~/.local/bin` so it can be run from anywhere.

## Usage

```bash
idira-get-jwt.sh
```

On first run (or once the token expires after 5h), a browser window opens
for SSO/MFA login. The JWT is cached at `~/.cache/idira_auth/tokens.json`
and printed to stdout, ready to use as a Bearer token or as Claude Code's
`apiKeyHelper`.

Opening Claude Code inside this directory (`idira-portkey-claude/`) picks
up `.claude/settings.local.json` automatically and routes every request
through Portkey using this JWT.
