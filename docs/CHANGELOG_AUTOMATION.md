# Changelog Automation

This project includes automated tools to manage changelog dates and prevent date inconsistencies.

## Available Tools

### 1. Rake Tasks

Update changelog dates automatically:

```bash
# Update all changelog entries with current date
rake changelog:update_date

# Add a new version entry with current date
rake changelog:new_version[1.0.1]

# Prepare a release (updates changelog and provides next steps)
rake release:prepare[1.0.1]
```

### 2. Ruby Script

Direct script execution:

```bash
# Update all entries
ruby scripts/update_changelog_date.rb

# Update specific version
ruby scripts/update_changelog_date.rb 1.0.1
```

### 3. Pre-commit Hook (Optional)

Automatically update changelog dates when committing:

```bash
# Install the pre-commit hook
ln -s ../../scripts/pre-commit-changelog .git/hooks/pre-commit
```

### 4. GitHub Actions Integration

The release workflow automatically updates changelog dates when creating releases from git tags.

## Usage Examples

### Adding a New Release

1. **Manual approach:**
   ```bash
   rake changelog:new_version[1.2.0]
   # Edit CHANGELOG.md to add your changes
   git add CHANGELOG.md
   git commit -m "Add changelog for v1.2.0"
   ```

2. **With release preparation:**
   ```bash
   rake release:prepare[1.2.0]
   # Follow the printed instructions
   ```

### Fixing Date Issues

If you notice incorrect dates in the changelog:

```bash
rake changelog:update_date
```

This will update all entries to use the current system date.

## Benefits

- **Consistency**: All dates use the current system time
- **Automation**: No manual date entry required
- **CI/CD Integration**: Automatic updates during releases
- **Developer Friendly**: Optional pre-commit hooks for convenience

## Date Format

All dates use the ISO 8601 format: `YYYY-MM-DD` (e.g., `2025-09-15`)

This format is:
- Sortable
- Unambiguous
- Follows the [Keep a Changelog](https://keepachangelog.com/) standard