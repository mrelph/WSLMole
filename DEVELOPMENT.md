# WSLMole Development Guide

## Quick Commands

### Linting
```bash
./lint.sh                    # Run ShellCheck on all files
shellcheck wslmole lib/*.sh  # Direct ShellCheck
```

### Testing
```bash
./tests/run_all.sh           # Run all test suites
./tests/test_common.sh       # Run common utilities tests only
./tests/test_safety.sh       # Run safety tests only
```

### Development Workflow
```bash
# 1. Make changes to code
# 2. Run linter
./lint.sh

# 3. Run tests
./tests/run_all.sh

# 4. Test manually (if needed)
./wslmole --help
./wslmole -q  # Quick scan (safe on any system)
```

## Test Coverage

### Common Utilities Tests (test_common.sh)
- ✅ format_size() - All size units (B, KB, MB, GB)
- ✅ is_protected_path() - Protected and non-protected paths
- ✅ validate_path() - Suspicious patterns, root, protected paths
- ✅ safe_delete() - Protection mechanisms

### Safety Tests (test_safety.sh)
- ✅ Protected paths blocking (/bin, /usr, etc.)
- ✅ Root path blocking (/)
- ✅ Relative path blocking
- ✅ Path traversal blocking (../..)
- ✅ Dry run mode preservation
- ✅ Actual deletion for safe paths

## CI/CD Pipeline

GitHub Actions workflow (`.github/workflows/ci.yml`):

1. **ShellCheck Job** - Lints all shell scripts
2. **Test Job** - Runs full test suite
3. **Smoke Test Job** - Tests all help commands

Triggers on:
- Push to `main` or `develop` branches
- Pull requests to `main`

## Safety Features

### Path Validation
```bash
validate_path "/some/path"  # Returns validated absolute path or error
```

Checks:
- Resolves to absolute path
- Blocks suspicious patterns (../.., /)
- Blocks protected paths
- Validates existence (optional)

### Safe Deletion
```bash
safe_delete "/path/to/file" "description"
```

Protections:
- Requires absolute paths
- Blocks path traversal
- Blocks protected paths
- Respects DRY_RUN mode
- Logs all operations

### Protected Paths
Never deleted:
- `/`, `/bin`, `/boot`, `/dev`, `/etc`, `/home`
- `/lib`, `/lib64`, `/media`, `/mnt`, `/opt`
- `/proc`, `/root`, `/run`, `/sbin`, `/srv`
- `/sys`, `/usr`, `/var`

## Adding New Tests

### Create a new test file:
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/common.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Your tests here...

# Summary
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
```

### Make it executable:
```bash
chmod +x tests/test_yourmodule.sh
```

The test runner will automatically discover and run it.

## ShellCheck Configuration

`.shellcheckrc` disables:
- `SC1091` - Not following sourced files
- `SC2034` - Variables used via sourcing

## Cross-Platform Notes

The codebase is designed for WSL2/Ubuntu but tests run on macOS for development:

- `get_size_bytes()` supports both Linux (`stat -c%s`) and macOS (`stat -f%z`)
- `du -sb` works on both platforms
- Tests use `/tmp` which exists on both

## Pre-commit Checklist

- [ ] Run `./lint.sh` - all files pass
- [ ] Run `./tests/run_all.sh` - all tests pass
- [ ] Test manually if adding new features
- [ ] Update tests if changing functionality
- [ ] Update README if adding user-facing features
