# Contributing to Omi Minimal Fork

Thank you for your interest in contributing to the Omi Minimal Fork project! This guide will help you get started.

## Code of Conduct

Please be respectful and constructive in all interactions. We aim to maintain a welcoming environment for all contributors.

## Getting Started

### Development Setup

1. **Fork and Clone**
   ```bash
   git clone https://github.com/yourusername/my-omi.git
   cd my-omi
   ```

2. **Flutter Setup**
   - Install Flutter SDK (latest stable)
   - Run `flutter doctor` to verify setup
   - Install dependencies: `flutter pub get`

3. **Firmware Setup** (if contributing to firmware)
   - Install Docker
   - Or install nRF Connect SDK v2.7.0 locally

### Development Workflow

1. Create a feature branch
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes
3. Test thoroughly
4. Commit with clear messages
5. Push and create a pull request

## Code Style

### Flutter/Dart
- Follow official [Dart style guide](https://dart.dev/guides/language/effective-dart/style)
- Run `flutter analyze` before committing
- Use meaningful variable and function names
- Add comments for complex logic

### Firmware/C
- Follow Zephyr coding standards
- Use consistent indentation (tabs)
- Comment all non-obvious code
- Keep functions focused and small

## Testing

### Flutter App
```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage
```

### Firmware
- Test on actual hardware when possible
- Use debug logging for verification
- Test all code paths

## Pull Request Process

1. **Before Submitting**
   - Ensure all tests pass
   - Update documentation if needed
   - Run code formatters/linters
   - Test on both iOS and Android (for app changes)

2. **PR Description**
   - Clearly describe what changes you made
   - Explain why the changes are needed
   - Reference any related issues
   - Include screenshots for UI changes

3. **Review Process**
   - Address reviewer feedback promptly
   - Be open to suggestions
   - Keep discussions focused and technical

## Areas for Contribution

### High Priority
- Error handling improvements
- Battery optimization
- UI/UX enhancements
- Documentation updates
- Test coverage

### Feature Ideas
- Additional audio codecs
- Extended offline recording
- Advanced button gestures
- Performance optimizations

## Documentation

When adding new features:
1. Update relevant documentation
2. Add code comments
3. Update CLAUDE.md if architecture changes
4. Create user guides if needed

## Commit Messages

Follow conventional commits format:
```
feat: add new audio codec support
fix: resolve connection timeout issue
docs: update setup instructions
refactor: simplify state management
test: add integration tests for recording
```

## Questions?

- Open a GitHub issue for bugs/features
- Start a discussion for questions
- Check existing issues before creating new ones

Thank you for contributing to make Omi better!