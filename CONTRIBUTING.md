# Contributing to Covr

Thank you for your interest in contributing to Covr!

## Getting Started

1. Read the [setup guide](docs/SETUP.md)
2. Review the [architecture documentation](database/ARCHITECTURE.md)
3. Check the [CLAUDE.md](CLAUDE.md) for development patterns

## Development Principles

### Bounded Contexts

Covr is organized into four independent engines:
- Contact Engine
- Ingest Engine
- Search Engine
- Exchange Engine

Keep these boundaries clean. Cross-engine communication happens via events, not direct database queries across schemas.

### Code Quality

- Write self-documenting code
- Add comments only where logic isn't obvious
- Follow the principle of least complexity
- Don't over-engineer for hypothetical future requirements

### Database Changes

- All schema changes go through migrations
- Never modify `database/schema.sql` directly after initial deployment
- Test migrations both up and down
- Update `CLAUDE.md` if architectural patterns change

### Testing

(To be defined once tech stack is chosen)

## Commit Guidelines

### Commit Messages

Follow conventional commits:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks
- `perf`: Performance improvements

**Examples**:
```
feat(ingest): add perceptual hash deduplication
fix(exchange): update current_holder on transfer
docs(architecture): clarify event flow diagrams
```

### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation
- `refactor/description` - Code refactoring

## Pull Request Process

1. Create a feature branch from `main`
2. Make your changes
3. Write/update tests
4. Update documentation if needed
5. Create a pull request
6. Wait for review

## Questions?

(Contact information to be added)
