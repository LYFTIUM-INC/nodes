# Git Branching Strategy

## Overview
This document outlines the Git branching strategy for our blockchain infrastructure project, following industry best practices for critical financial infrastructure.

## Branch Types

### Main Branches

#### `main`
- **Purpose**: Production-ready code
- **Protection**: Fully protected, requires PR approval
- **Deployment**: Auto-deploys to production after all checks pass
- **Merge Policy**: Only from `develop` via PR with full CI/CD validation

#### `develop`
- **Purpose**: Integration branch for features
- **Protection**: Protected, requires PR approval
- **Merge Policy**: Features merge here first for integration testing

### Supporting Branches

#### Feature Branches
- **Naming**: `feature/ISSUE-description`
- **Example**: `feature/123-arbitrum-monitoring`
- **Base**: Created from `develop`
- **Merge**: Back to `develop` via PR
- **Lifetime**: Short-lived (1-7 days)

#### Hotfix Branches
- **Naming**: `hotfix/ISSUE-description`
- **Example**: `hotfix/456-critical-rpc-fix`
- **Base**: Created from `main`
- **Merge**: To both `main` and `develop`
- **Lifetime**: Very short (hours to 1 day)

#### Release Branches
- **Naming**: `release/v1.2.3`
- **Base**: Created from `develop`
- **Merge**: To `main` and back to `develop`
- **Purpose**: Final testing and minor fixes before release

## Workflow

### Feature Development
```bash
# Create feature branch
git checkout develop
git pull origin develop
git checkout -b feature/123-new-monitoring

# Work on feature
git add .
git commit -m "feat: add comprehensive node monitoring"

# Push and create PR
git push origin feature/123-new-monitoring
# Create PR: feature/123-new-monitoring → develop
```

### Hotfix Process
```bash
# Create hotfix branch
git checkout main
git pull origin main
git checkout -b hotfix/456-critical-rpc-fix

# Apply fix
git add .
git commit -m "fix: resolve critical RPC endpoint issue"

# Push and create PRs
git push origin hotfix/456-critical-rpc-fix
# Create PR: hotfix/456-critical-rpc-fix → main
# Create PR: hotfix/456-critical-rpc-fix → develop
```

### Release Process
```bash
# Create release branch
git checkout develop
git pull origin develop
git checkout -b release/v1.2.3

# Final preparations
git add .
git commit -m "chore: prepare release v1.2.3"

# Push and create PR
git push origin release/v1.2.3
# Create PR: release/v1.2.3 → main
```

## Commit Message Standards

### Format
```
<type>(<scope>): <description>

<body>

<footer>
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or modifying tests
- `chore`: Maintenance tasks
- `perf`: Performance improvements
- `security`: Security improvements

### Examples
```bash
feat(arbitrum): add emergency RPC proxy configuration

Implements nginx proxy for Arbitrum RPC endpoint to maintain MEV
operations during local node synchronization issues.

Fixes #123
```

```bash
fix(monitoring): resolve memory leak in node checker

Fixed unbounded array growth in comprehensive-node-checker.sh
that was causing memory consumption issues during extended runs.

Closes #456
```

## Branch Protection Rules

### Main Branch
- Require PR approval (2 reviewers)
- Require status checks to pass:
  - CI/CD pipeline
  - Security scan
  - Pre-commit hooks
  - Service health checks
- Require branches to be up to date
- Restrict pushes to specific users
- Include administrators in restrictions

### Develop Branch
- Require PR approval (1 reviewer)
- Require status checks to pass:
  - CI/CD pipeline
  - Pre-commit hooks
- Require branches to be up to date

## Pre-commit Hook Requirements

All commits must pass:
1. **Configuration Validation**: YAML/JSON syntax and schema validation
2. **Service Health Check**: Critical blockchain services operational
3. **Script Validation**: Shell script syntax and quality checks
4. **Security Scan**: No secrets, dangerous commands, or permission issues
5. **Monitoring Check**: System health within acceptable parameters

## Emergency Procedures

### Critical Production Issue
1. Create hotfix branch from `main`
2. Implement minimal fix
3. Emergency merge process (can bypass some checks with approval)
4. Immediate deployment
5. Post-incident review and documentation

### Rollback Process
```bash
# Identify last known good commit
git log --oneline main

# Create rollback branch
git checkout -b hotfix/rollback-to-COMMIT main
git revert COMMIT_RANGE

# Deploy rollback
git push origin hotfix/rollback-to-COMMIT
# Emergency merge to main
```

## Code Review Guidelines

### Required Checks
- [ ] Code follows project standards
- [ ] All tests pass
- [ ] Security implications considered
- [ ] Documentation updated if needed
- [ ] No performance regressions
- [ ] Blockchain services remain operational

### Review Criteria
- **Functionality**: Code does what it's supposed to do
- **Security**: No vulnerabilities introduced
- **Performance**: No negative impact on node operations
- **Maintainability**: Code is readable and well-structured
- **Testing**: Adequate test coverage

## Integration with CI/CD

### Automated Checks
- Pre-commit hooks run on every commit
- CI pipeline runs on every PR
- Security scans on develop and main
- Automated deployment to staging (develop)
- Manual approval for production (main)

### Quality Gates
- Code coverage > 80%
- Security scan passes
- Performance benchmarks met
- All blockchain services operational
- Documentation up to date

## Best Practices

### General
- Keep commits atomic and focused
- Write clear, descriptive commit messages
- Rebase feature branches before merging
- Delete merged branches to keep repository clean
- Use meaningful branch names

### Blockchain-Specific
- Never commit during active MEV operations
- Ensure all nodes remain synced during development
- Test configuration changes in isolated environment
- Monitor system resources during development
- Maintain backup configurations

### Security
- Never commit secrets or private keys
- Review all configuration changes for security implications
- Use environment variables for sensitive data
- Rotate secrets regularly
- Audit access permissions quarterly

## Troubleshooting

### Common Issues
1. **Pre-commit hooks failing**: Run hooks individually to identify issue
2. **Merge conflicts**: Rebase feature branch on latest develop
3. **CI/CD pipeline failures**: Check service health and logs
4. **Branch protection violations**: Ensure all required checks pass

### Recovery Procedures
- Lost commits: Use `git reflog` to recover
- Corrupted branch: Recreate from known good state
- Failed deployment: Follow rollback procedures
- Service disruption: Emergency hotfix process

---

*This branching strategy ensures high availability and reliability for our critical blockchain infrastructure while maintaining development velocity and code quality.*