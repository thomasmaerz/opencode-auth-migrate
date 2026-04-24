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

6. **Run one-model-per-provider test**
   - For each provider in config, run: `opencode run -m <provider>/<model> "Reply with exactly: PROVIDER_OK"`
   - Report pass/fail for each

7. **Output report**
   - Report plugin_actions (list with action: updated_from_ecosystem|installed_from_original|skipped_already_present|failed)
   - Report provider_results (list with status: pass|fail|skip)
   - Store report as JSON

## Requirements

- Always check ecosystem first before falling back to exported sources
- Prompt for user confirmation if fallback needed
- Test every provider that has configuration
- Handle the guard22/opencode-multi-auth-codex repo specially

## Key References

- Ecosystem: https://opencode.ai/docs/ecosystem/
- Manual override: https://github.com/guard22/opencode-multi-auth-codex

## Output

When complete, report:
- Plugin action summary (with action per plugin)
- Provider test results (pass/fail per provider)
- Report JSON path