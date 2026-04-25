# Auth Import Playbook

You are executing an import of OpenCode auth and plugin migration bundle with ecosystem-first plugin reinstall decisions.

## Your Task

Perform the following steps exactly:

1. **Check current destination plugins and skip duplicates**
   - Read destination opencode.json plugin array
   - Normalize paths and source specs
   - Skip any plugins that match existing plugins (by name, with version suffixes stripped)

2. **Ecosystem-first plugin reinstall**
   - Read `https://opencode.ai/docs/ecosystem/` to discover available plugins
   - For each incoming plugin, check if ecosystem has a compatible version
   - Follow linked plugin repo README.md install instructions
   - Prefer latest stable release guidance
   - Fall back to default branch guidance if no release tag

3. **Manual guard22 override lookup**
   - Look up `https://github.com/guard22/opencode-multi-auth-codex` specifically
   - If not on ecosystem page, install from this repo per its README

4. **Fallback for reinstall failures**
   - If ecosystem reinstall fails, prompt user whether to install original exported plugin source
   - If user says yes, use the original plugin source from the exported manifest

5. **Restore tokens/keys/config**
   - Restore auth.json tokens
   - Restore config files
   - Restore plugin state directories
   - **CRITICAL**: Ensure multi-auth store goes to correct path:
     - Run `opencode-multi-auth path` to discover correct store directory
     - Default: `~/.config/opencode-multi-auth/accounts.json`
     - NOT `~/.local/share/opencode/opencode-multi-auth/`

6. **Fix common import issues**
   - **NEVER create empty provider blocks** like `"openai": {"models": {}}` in opencode.json
   - Empty provider blocks OVERRIDE the built-in model registry, causing models to disappear
   - If source machine has no `openai` provider block, don't create one
   - The multi-auth plugin creates the provider dynamically at runtime via its `config` hook
   - Reset `authInvalid` flags on imported accounts (they may be stale from source machine)
   - Reset `rateLimitedUntil` timestamps on imported accounts

7. **Install plugin npm packages**
   - Install plugin npm packages into `~/.config/opencode/node_modules/`
   - Example: `cd ~/.config/opencode && npm install opencode-antigravity-auth@latest`
   - Example: `cd ~/.config/opencode && npm install @guard22/opencode-multi-auth-codex@latest`

8. **Run one-model-per-provider test for all present providers**
   - Build provider set from the union of restored auth providers and restored config providers
   - Use cheaper/free verification model selection policy:
     - `google` (antigravity): prefer `google/antigravity-gemini-3-flash:low`, then `google/antigravity-gemini-3-flash`
     - `openai`/codex: use base models like `openai/gpt-5.4` (NOT spark variants with reasoning levels)
     - `openrouter`: prefer models marked free (`:free`, `/free`, `-free`)
     - `kilo`: prefer `kilo/kilo-auto/free`, then models marked free
     - `opencode` or `zen`: prefer models marked free
     - Otherwise use cheap heuristics (`free`, `lite`, `mini`, `nano`, `small`, `flash`) then fallback selection
   - Run: `opencode run -m <provider>/<selected-cheap-model> "Reply with exactly: PROVIDER_OK"`
   - Report pass/fail/skip for each provider
   - If any provider fails or is skipped, warn and continue; include details in post-run report

9. **Verify multi-auth specifically**
   - Run `opencode-multi-auth status` to verify accounts are present
   - Run `opencode models openai` to verify base models show up (gpt-5.4, gpt-5.3-codex, etc.)
   - **Expected**: Base models show up from built-in registry
   - **NOT Expected**: Only spark variants (gpt-5.3-codex-spark-{low,medium,high,xhigh}) showing
   - If only spark variants show: check for empty `"openai": {"models": {}}` in opencode.json and REMOVE it

10. **Output report**
    - Report plugin_actions (list with action: updated_from_ecosystem|installed_from_original|skipped_already_present|failed)
    - Report provider_results (list with status: pass|fail|skip)
    - Include model selection strategy in provider results
    - Store report as JSON

## Requirements

- Always check ecosystem first before falling back to exported sources
- Prompt for user confirmation if fallback needed
- Test every provider present in restored auth/config
- Handle the guard22/opencode-multi-auth-codex repo specially
- **Never create empty provider blocks in opencode.json**
- **Always verify multi-auth store path is correct**

## Key References

- Ecosystem: https://opencode.ai/docs/ecosystem/
- Manual override: https://github.com/guard22/opencode-multi-auth-codex
- Multi-auth store path: `opencode-multi-auth path` (default: ~/.config/opencode-multi-auth/)

## Output

When complete, report:
- Plugin action summary (with action per plugin)
- Provider test results (pass/fail per provider)
- Multi-auth verification results (accounts present, models showing correctly)
- Report JSON path

## Troubleshooting

### "No available accounts after filtering" error
- Check `~/.config/opencode-multi-auth/accounts.json` exists and has accounts
- Run `opencode-multi-auth status` to verify
- If accounts are in wrong directory (`~/.local/share/opencode/opencode-multi-auth/`), copy them to correct path

### Models not showing up (only spark variants showing)
- Check for empty `"openai": {"models": {}}` in `~/.config/opencode/opencode.json`
- Remove the empty openai provider block if present
- OpenCode needs the built-in registry to load base models

### Plugin not loading
- Check plugin npm packages are installed in `~/.config/opencode/node_modules/`
- Run: `cd ~/.config/opencode && npm install <plugin>@latest`

### Token refresh failures
- Accounts may have stale `authInvalid: true` or `rateLimitedUntil` from source machine
- Accounts with expired tokens (check `tokenExpiresAt`) will fail refresh
- This is expected for expired tokens - user needs to re-authenticate those accounts
