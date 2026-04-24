# Auth Import Playbook

You are executing an agentic import of OpenCode auth and plugin migration bundle with ecosystem-first plugin reinstall decisions.

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

6. **Run one-model-per-provider test for all present providers**
   - Build provider set from the union of restored auth providers and restored config providers
   - Use cheaper/free verification model selection policy:
     - `google` (antigravity): prefer `google/antigravity-gemini-3-flash:low`, then `google/antigravity-gemini-3-flash`
     - `openai`/codex: prefer codex-mini/mini models
     - `openrouter`: prefer models marked free (`:free`, `/free`, `-free`)
     - `kilo`: prefer `kilo/kilo-auto/free`, then models marked free
     - `opencode` or `zen`: prefer models marked free
     - Otherwise use cheap heuristics (`free`, `lite`, `mini`, `nano`, `small`, `flash`) then fallback selection
   - Run: `opencode run -m <provider>/<selected-cheap-model> "Reply with exactly: PROVIDER_OK"`
   - Report pass/fail/skip for each provider
   - If any provider fails or is skipped, warn and continue; include details in post-run report

7. **Output report**
   - Report plugin_actions (list with action: updated_from_ecosystem|installed_from_original|skipped_already_present|failed)
   - Report provider_results (list with status: pass|fail|skip)
   - Include model selection strategy in provider results
   - Store report as JSON

## Requirements

- Always check ecosystem first before falling back to exported sources
- Prompt for user confirmation if fallback needed
- Test every provider present in restored auth/config
- Handle the guard22/opencode-multi-auth-codex repo specially

## Key References

- Ecosystem: https://opencode.ai/docs/ecosystem/
- Manual override: https://github.com/guard22/opencode-multi-auth-codex

## Output

When complete, report:
- Plugin action summary (with action per plugin)
- Provider test results (pass/fail per provider)
- Report JSON path
