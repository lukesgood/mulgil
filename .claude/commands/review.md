Review PR $ARGUMENTS with fresh context. Launch the reviewer agent as a
subagent with only the PR number — it reads the diff itself. If the PR touches
auth, RLS, masking, audit, keys, PII, secrets, dependencies or deletion, also
launch the security agent as a separate subagent in parallel. Neither sees the
other's output. Post both results as PR comments and summarize the verdicts.
