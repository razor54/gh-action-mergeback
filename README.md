# Mergeback

A simple github action to merge back master to a development branch.
￼
This action uses an optional environment variable:
- `BASE_BRANCH`
  The base branch where master changes should be merged to. Defaults to `develop`.
- `DESC_PATH`
  The path in your repository for the PR body template. Defaults to `.github/merge-instructions.md`.
  If this file exists, this will be used for the description of the PR (only if it's not mergable).
  Environment variables can be used in this file, they will be resolved.
- `REVIEWERS`
  An array with the list of reviewers for the PR, if there are merge conflicts
- `TEAM_REVIEWERS`
  An array of team slugs for reviewing the PR, if there are merge conflicts

The action uses GitHub's REST API to create a PR and merge it remotely on GitHub's servers.
