# CONTRIBUTING TO LYFTIUM MEV LAB

## 📋 Overview

Thank you for your interest in contributing to LYFTIUM's MEV infrastructure! This document outlines the guidelines, workflows, and best practices for contributing to this production blockchain platform.

## 🚀 Quick Start

1. **Fork and Clone**
   ```bash
   git clone https://github.com/YOUR-USERNAME/nodes.git
   cd nodes
   git remote add upstream https://github.com/LYFTIUM-INC/nodes.git
   ```

2. **Create Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make Changes**
   - Follow code style guidelines
   - Add tests for new functionality
   - Update documentation

4. **Submit Pull Request**
   - Describe your changes clearly
   - Link related issues
   - Ensure CI/CD checks pass

## 🎯 Contribution Guidelines

### What We're Looking For

- **Bug fixes** with reproduction steps
- **New features** aligned with MEV operations
- **Performance optimizations** with benchmarks
- **Documentation improvements**
- **Security vulnerability disclosures** (private channel)
- **Test coverage improvements**

### Before Contributing

- [ ] Check existing issues and PRs
- [ ] Discuss major changes in an issue first
- [ ] Follow the code style guide
- [ ] Write tests for new code
- [ ] Update relevant documentation
- [ ] Ensure all CI checks pass

## 📝 Code Style

### Commit Messages

Follow **Conventional Commits** specification:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Test additions/changes
- `chore`: Maintenance tasks
- `ci`: CI/CD changes
- `security`: Security vulnerability fixes

**Examples:**
```
feat(mev): add cross-chain arbitrage detection

Implements automated detection of arbitrage opportunities
across Ethereum mainnet and major L2s (Arbitrum, Optimism).

Closes #123

Co-authored-by: Team Member <email@lyftium.com>
```

```
fix(erigon): resolve Snap Sync memory leak

Memory usage was growing unbounded during Snap Sync due to
unreleased batch buffers. Added explicit cleanup in sync loop.

Fixes #456
```

### Language-Specific Guidelines

#### Python
- **Type hints**: Required for all functions
- **Docstrings**: Google style docstrings
- **Formatting**: `ruff format`
- **Linting**: `ruff check`
- **Testing**: `pytest` with >80% coverage

#### Rust
- **Style**: `cargo fmt`
- **Lints**: `cargo clippy -- -W clippy::all`
- **Tests**: `cargo test`
- **Documentation**: Rustdoc examples

#### TypeScript/JavaScript
- **Style**: Prettier
- **Linting**: ESLint with strict rules
- **Type Safety**: No `any`, use `unknown`
- **Testing**: Jest + Vitest

#### Shell Scripts
- **Shellcheck**: Required validation
- **Shebang**: `#!/usr/bin/env bash`
- **Error handling**: `set -euo pipefail`

## 🧪 Testing

### Test Requirements

- **Unit tests**: All new code must have unit tests
- **Integration tests**: For cross-service interactions
- **E2E tests**: For critical user workflows
- **Load tests**: For performance-critical paths

### Running Tests

```bash
# Python
pytest tests/ --cov=src --cov-report=html

# Rust
cargo test --all-features

# TypeScript
npm test

# Shell
shellcheck scripts/**/*.sh
```

## 📚 Documentation

### Documentation Standards

- **README.md**: Project overview, quick start
- **API docs**: OpenAPI/Swagger for REST APIs
- **Runbooks**: Operational procedures
- **Architecture docs**: System design (C4 model)
- **Changelog**: Auto-generated from commits

### Writing Good Documentation

- ✅ Clear and concise
- ✅ Include code examples
- ✅ Keep diagrams up to date
- ✅ Document edge cases
- ✅ Use active voice
- ❌ Avoid jargon without explanation

## 🔒 Security

### Reporting Vulnerabilities

**Do NOT open a public issue for security vulnerabilities!**

Instead, send details to:
- Email: security@lyftium.com
- PGP Key: [Available on website]

Include:
- Vulnerability description
- Steps to reproduce
- Impact assessment
- Proposed fix (optional)

### Security Best Practices

- Never commit secrets, keys, or credentials
- Use `.env.example` for environment templates
- Validate all user inputs
- Follow OWASP guidelines
- Keep dependencies updated

## 🚦 Pull Request Process

### Before Opening PR

1. **Update Documentation**
   - README.md (if user-facing)
   - API docs (if API changes)
   - Runbooks (if operational changes)

2. **Ensure Tests Pass**
   ```bash
   make test-all
   ```

3. **Run Linters**
   ```bash
   make lint-all
   ```

4. **Update Changelog**
   - Add entry to `CHANGELOG.md`

### PR Description Template

```markdown
## Description
Brief description of changes (1-2 sentences).

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Performance improvement
- [ ] Documentation update
- [ ] Refactoring
- [ ] Security fix

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No new warnings
- [ ] Tests added/updated
- [ ] CHANGELOG.md updated
- [ ] Commits follow conventional format

## Related Issues
Fixes #123
Related to #456
```

### Review Process

1. **Automated Checks**: CI/CD pipeline validates
2. **Code Review**: At least one maintainer approval
3. **Security Review**: For sensitive changes
4. **Testing**: Verified in staging environment
5. **Merge**: Squash and merge to `main` branch

## 🔄 Branch Strategy

### Branch Structure

```
main (protected)
  ├── develop (integration branch)
  ├── feature/* (feature branches)
  ├── bugfix/* (bug fixes)
  ├── hotfix/* (production emergencies)
  └── release/* (release preparation)
```

### Workflow

1. **Feature Development**
   ```bash
   git checkout develop
   git pull origin develop
   git checkout -b feature/your-feature
   # Make changes
   git push origin feature/your-feature
   # Create PR: feature/your-feature → develop
   ```

2. **Hotfix (Production Emergency)**
   ```bash
   git checkout main
   git pull origin main
   git checkout -b hotfix/critical-fix
   # Make changes
   git push origin hotfix/critical-fix
   # Create PR: hotfix/critical-fix → main
   # Merge to both main and develop
   ```

## 🎨 Project Structure

```
nodes/
├── environments/          # Environment-specific configs
│   ├── dev/
│   ├── staging/
│   └── prod/
├── services/             # Service definitions
├── strategies/           # MEV strategy code
├── infrastructure/       # IaC and automation
├── observability/        # Monitoring & logging
├── security/            # Security policies
├── docs/                # Documentation
└── tools/               # Developer tools
```

## 🤝 Community Guidelines

### Code of Conduct

- Be respectful and inclusive
- Welcome newcomers and help them learn
- Focus on constructive feedback
- Assume good intentions
- Resolve conflicts privately

### Getting Help

- **Issues**: Use GitHub issues for bugs/features
- **Discussions**: Use GitHub Discussions for questions
- **Slack**: `#lyftium-dev` for real-time chat
- **Email**: contact@lyftium.com

## 📜 License

By contributing, you agree that your contributions will be licensed under the **LYFTIUM INC Proprietary License**.

## 🙏 Recognition

Contributors will be:
- Listed in CONTRIBUTORS.md
- Mentioned in release notes
- Invited to internal syncs (for significant contributions)
- Eligible for LYFTIUM merchandise

---

**Questions?** Open an issue or contact contact@lyftium.com

**Ready to contribute?** Check out [good first issues](https://github.com/LYFTIUM-INC/nodes/labels/good%20first%20issue)!

---

*Last Updated: 2026-01-31*
