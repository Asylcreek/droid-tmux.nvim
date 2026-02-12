# Releasing

## Versioning

Use semantic versioning tags:

- `MAJOR.MINOR.PATCH`
- Example: `v0.1.0`

## Release Steps

1. Update `CHANGELOG.md`.
2. Commit changes to `main`.
3. Create and push a tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

4. Publish a GitHub release for that tag.

## Notes

- Keep user-facing migration notes in release notes when behavior changes.
- Users can pin plugin versions in `lazy.nvim` using `version`.
