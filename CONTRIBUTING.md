# Contributing to A2A Ruby SDK

We love your input! We want to make contributing to the A2A Ruby SDK as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of the code
- Submitting a fix
- Proposing new features
- Becoming a maintainer

## Development Process

We use GitHub to host code, to track issues and feature requests, as well as accept pull requests.

1. Fork the repo and create your branch from `main`.
2. If you've added code that should be tested, add tests.
3. If you've changed APIs, update the documentation.
4. Ensure the test suite passes.
5. Make sure your code lints.
6. Issue that pull request!

## Setting Up Development Environment

1. **Clone the repository:**
   ```bash
   git clone https://github.com/a2aproject/a2a-ruby.git
   cd a2a-ruby
   ```

2. **Install dependencies:**
   ```bash
   bin/setup
   ```

3. **Run tests:**
   ```bash
   bundle exec rspec
   ```

4. **Run linting:**
   ```bash
   bundle exec rubocop
   ```

5. **Start console:**
   ```bash
   bin/console
   ```

## Code Style

We use RuboCop to maintain consistent code style. Please ensure your code follows our style guide:

```bash
# Check style
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a
```

## Testing

We use RSpec for testing. Please ensure:

- All new features have corresponding tests
- All tests pass before submitting PR
- Maintain or improve code coverage

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/a2a/client_spec.rb

# Run with coverage
COVERAGE=true bundle exec rspec
```

## Documentation

- Update relevant documentation for any API changes
- Add YARD comments for new public methods
- Update README.md if needed
- Add examples for new features

Generate documentation:
```bash
bundle exec yard doc
```

## Pull Request Process

1. **Create a feature branch:**
   ```bash
   git checkout -b feature/amazing-feature
   ```

2. **Make your changes and commit:**
   ```bash
   git commit -m "Add amazing feature"
   ```

3. **Push to your fork:**
   ```bash
   git push origin feature/amazing-feature
   ```

4. **Create a Pull Request** with:
   - Clear title and description
   - Reference any related issues
   - Include tests for new functionality
   - Update documentation as needed

## Reporting Bugs

We use GitHub issues to track public bugs. Report a bug by [opening a new issue](https://github.com/a2aproject/a2a-ruby/issues).

**Great Bug Reports** tend to have:

- A quick summary and/or background
- Steps to reproduce
  - Be specific!
  - Give sample code if you can
- What you expected would happen
- What actually happens
- Notes (possibly including why you think this might be happening, or stuff you tried that didn't work)

## Feature Requests

We welcome feature requests! Please:

1. Check if the feature already exists or is planned
2. Open an issue with the `enhancement` label
3. Describe the feature and its use case
4. Discuss the implementation approach

## Versioning

We use [Semantic Versioning](http://semver.org/). For the versions available, see the [tags on this repository](https://github.com/a2aproject/a2a-ruby/tags).

## Release Process

1. Update version in `lib/a2a/version.rb`
2. Update `CHANGELOG.md`
3. Create a pull request
4. After merge, create a release tag
5. Gem is automatically published via GitHub Actions

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Questions?

Feel free to contact the maintainers:
- Open an issue for public discussion
- Email: team@a2a-ruby.org

Thank you for contributing! 🎉