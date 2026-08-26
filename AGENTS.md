# Arbor Agent Guidelines

## Keep implementations simple

- Start by identifying the smallest invariant that solves the demonstrated problem.
- Prefer a direct implementation of that invariant over defensive abstractions for hypothetical failure modes.
- Keep fixes narrowly scoped. Do not combine the requested fix with migrations, validation frameworks, cleanup systems, or unrelated hardening unless the task requires them.
- Before adding a helper or abstraction, ask whether it makes the main operation easier to understand. If it does not, keep the logic local.
- Reuse established libraries and parsers instead of hand-written parsing, especially regular expressions.
- Add complexity only when a concrete requirement, reproduced failure, or existing project convention justifies it.

For dependency updates, the core invariant is that pip installs into an empty staging directory. The intended flow is:

1. Install the complete dependency set into a temporary staging directory.
2. Preserve the current installation as a temporary rollback copy.
3. Move the staged installation into place.
4. Restore the previous installation only if activation fails.
5. Let the temporary workspace clean itself up.

Do not add metadata-validation layers or special handling for stale package metadata when the fresh staging directory already prevents stale metadata from carrying forward.

## Tests

Do not add test files or new test infrastructure unless the user explicitly requests them.

## Pull requests

- Check the repository pull request template before creating or editing a PR.
- Keep unrelated working-tree changes out of the branch and verify the final PR file list.
- Use a clear title that names the bug or user-visible outcome; avoid vague titles such as "Fix repeated updates."
- Start the description with the Codex banner from the pull request template.
- Use `# Why`, `# What changed`, and `# Test plan` as the description sections.
- Keep the description concise and use bullet points, but include enough context to understand the bug without reading the code or discussion.
- In `Why`, summarize the general symptom and root cause first. Then give a short concrete example and, when relevant, explain why the user's workaround appeared to fix it.
- Do not provide only an example without stating the general bug, and do not bury the explanation in a long narrative.
- In `What changed`, describe the behavioral fix and important safety behavior. Leave out incidental implementation details unless they matter to the review.
- In `Test plan`, give concrete steps that reproduce the original bug and verify the fix, including relevant first-use or failure paths.
- Do not claim tests were run when they were not.
- After creating or editing the PR, view it again to verify the rendered title, description, and file list.
