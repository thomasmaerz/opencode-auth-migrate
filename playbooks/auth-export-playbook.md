# Auth Export Playbook

You are executing an export of OpenCode auth and plugin migration bundle with ecosystem-first plugin discovery.

## Your Task

Perform the following steps exactly:

1. **Detect active providers correctly**
   - Collect providers from `auth.json` (all providers with stored tokens/keys)
   - Collect providers from `opencode.json` `provider` config blocks
   - **CRITICAL for multi-auth plugins**: Detect providers managed dynamically by plugins:
     - Check if `opencode-multi-auth` or `@guard22/opencode-multi-auth-codex` is in plugins
     - If yes, ADD `openai` to active providers (plugin manages this dynamically)
     - Check if `opencode-antigravity-auth` is in plugins
     - If yes, ADD `google` to active providers (plugin manages this dynamically)
   - **Reason**: These plugins create provider blocks at runtime and won't appear in config

2. **Filter stale providers**
   - Only export auth entries for active providers
   - Stale providers are those in auth.json but NOT in active providers
   - This prevents exporting auth for providers that aren't configured

3. **Export tokens/keys/config**
   - Export auth.json tokens for active providers
   - Export config files (opencode.json, config.json)
   - Export plugin state directories (e.g., `opencode-multi-auth/` from store path)

4. **Discover plugin sources**
   - Read `https://opencode.ai/docs/ecosystem/` for available plugins
   - For each plugin in opencode.json:
     - Check ecosystem first
     - Fall back to guard22 GitHub for multi-auth: `https://github.com/guard22/opencode-multi-auth-codex`
     - Use `npm show <package>@latest` to get version info

5. **Bundle and encrypt**
   - Create bundle with snapshots, manifest, checksums
   - Encrypt with AES-256-CBC
   - Use `-pbkdf2 -iter 200000` for key derivation
   - Support `--password` flag for non-interactive use

6. **Verify exported accounts**
   - Run `opencode-multi-auth status` to check accounts are exported
   - Verify bundle integrity with checksums

## Requirements

- Always detect multi-auth/antigravity plugins and add their dynamic providers
- Filter stale providers from export (don't export auth for unused providers)
- Use correct encryption parameters (`-iter 200000`)
- Support `--password` flag for automation

## Key References

- Ecosystem: https://opencode.ai/docs/ecosystem/
- Multi-auth: https://github.com/guard22/opencode-multi-auth-codex
- Multi-auth store path: `opencode-multi-auth path` (default: ~/.config/opencode-multi-auth/)

## Output

When complete, report:
- Exported providers and account counts
- Plugin sources discovered
- Bundle path and checksums
- Verification results (accounts present, models check)

## Troubleshooting

### "openai" provider filtered as stale
- Check if multi-auth plugin is detected
- Verify `openai` is added to active providers when multi-auth is present

### Bundle decryption fails
- Ensure encryption and decryption use same parameters (`-pbkdf2 -iter 200000`)
- Check password is correct

### Multi-auth accounts missing from export
- Check `opencode-multi-auth path` for correct store directory
- Verify `accounts.json` exists and has accounts
