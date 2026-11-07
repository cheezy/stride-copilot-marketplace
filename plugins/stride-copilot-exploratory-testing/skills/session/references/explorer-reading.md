# Explorer reading rules

Reference for the `explorer` agent, loaded through the `session` skill. It is efficiency guidance kept out of the agent body, which Copilot caps at 30,000 characters; an explorer that never loads it is still bounded by its budget and its safety boundary.

## Reading files

Nothing here loosens the credential-file rule.

- **Locate first, with line numbers**: `search`, or `grep -n` through `execute`, narrowed by path and pattern.
- **Then read a bounded range** with `sed -n '<first>,<last>p' <file>` through `execute`; `read` a whole file only when it is small or you need all of it.
- **Never re-read a file or range you have already read this session**: note each read's path, range and findings; load each skill once.
- **Except a file that changed since you read it** (a probe wrote it, a log grew): check `wc -l` first, then read only what changed (`tail -n +<line>`).
- **Inspect binary files through `execute`, never `read`**: `file`, `wc -c` or `strings <file> | grep -n <pattern>`, only on a file the charter names.
