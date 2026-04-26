# Auth Export Playbook

You are executing an export of OpenCode auth and plugin migration bundle with ecosystem-first plugin discovery.

## Your Task

Perform the following steps exactly:

1. **Detect active providers correctly**
   - Collect providers from `auth.json` (all providers with stored tokens/keys).
   - Collect providers from `opencode.json` `provider` config blocks.
   - **CRITICAL for multi-auth plugins**: Detect providers managed dynamically by plugins:
     - Check if `opencode-multi-auth` or `@guard22/opencode-multi-auth-codex` is in plugins.
     - If yes, ADD `openai` to active providers.
     - Check if `opencode-antigravity-auth` is in plugins.
     - If yes, ADD `google` and `antigravity` to active providers.

2. **Filter stale providers**
   - Only export auth entries for active providers.
   - Stale providers are those in `auth.json` but NOT in active providers.
   - **ACCOUNT FILES ARE NEVER STALE**: The export script explicitly exempts `*-accounts.json`, `antigravity.json`, and `puter.json` from stale filtering.

3. **Export tokens/keys/config**
   - Export `auth.json` tokens for active providers.
   - Export config files (`opencode.json`, `config.json`).
   - Export plugin state directories (e.g., `opencode-multi-auth/` from store path).
   - Export plugin account files (e.g., `antigravity-accounts.json` from config dir).

4. **Discover plugin sources**
   - Read `https://opencode.ai/docs/ecosystem/` for available plugins.
   - Fall back to guard22 GitHub for multi-auth: `https://github.com/guard22/opencode-multi-auth-codex`.

5. **Bundle and encrypt**
   - Create bundle with snapshots, manifest, checksums.
   - Encrypt with AES-256-CBC, `-pbkdf2 -iter 200000`.

6. **Verify exported accounts**
   - Run `opencode-multi-auth status` to check accounts are exported.
   - Verify `antigravity-accounts.json` is included in the bundle manifest.

## Requirements
- Always detect multi-auth/antigravity plugins and add their dynamic providers.
- Use correct encryption parameters (`-iter 200000`).
- Support `--password` flag for automation.

## Troubleshooting

### "openai" provider filtered as stale
- Check if multi-auth plugin is detected.
- Verify `openai` is added to active providers when multi-auth is present.

### Multi-auth accounts missing from export
- Check `opencode-multi-auth path` for correct store directory.
- Verify `accounts.json` exists.
- The export script now explicitly ignores stale filtering for account files.
