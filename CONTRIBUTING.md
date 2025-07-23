# 🤝 Contributing

We welcome contributions from the community! Here's how you can help improve the
Vybovaly Automated Installation System.

## 🚀 Getting Started

### Prerequisites

- **Nix** with flakes enabled
- **Git** and basic Git knowledge
- **GitHub account** for pull requests
- **Some understanding** of Linux, Nix and iPXE

### Development Setup

- **Fork the repository**

  ```bash
  # Fork on GitHub, then clone your fork
  git clone https://github.com/au-phiware/vybovaly-installer
  cd vybovaly-installer
  ```

- **Set up development environment**

  Enter development shell:

  ```bash
  nix develop
 ```

  Or use direnv (recommended):

 ```bash
  echo "use flake" > .envrc
  direnv allow
  ```

- **Create feature branch**

  ```bash
  git checkout -b feature/awesome-new-feature
  ```

## 📝 Types of Contributions

### 🐛 Bug Reports

- Use GitHub Issues with the bug report template
- Include detailed reproduction steps
- Provide system information and logs
- Test with latest version first

### ✨ Feature Requests

- Use GitHub Issues with the feature request template
- Explain the use case and expected behavior
- Consider implementation complexity
- Discuss with maintainers before large changes

### 🔧 Code Contributions

- **Bug fixes**: Always welcome
- **New features**: Discuss in issues first
- **Documentation**: Improvements always appreciated
- **Tests**: Help improve test coverage

### 📚 Documentation

- Fix typos and unclear explanations
- Add usage examples
- Improve troubleshooting guides
- Translate documentation (future)

## 🛠 Development Guidelines

### Code Style

#### Nix Code

```nix
# Use consistent formatting
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.example;
in {
  # Options should be well-documented
  options.services.example = {
    enable = mkEnableOption "example service";

    port = mkOption {
      type = types.int;
      default = 8080;
      description = "Port to listen on";
    };
  };

  # Configuration should be conditional
  config = mkIf cfg.enable {
    # Implementation
  };
}
```

#### Shell Scripts

```bash
#!/bin/bash
# Use strict error handling
set -euo pipefail

# Document functions
# Description of what this function does
function_name() {
    local param="$1"
    echo "Processing: $param"
}

# Use shellcheck for validation
# shellcheck disable=SC2034  # Only when necessary
```

#### iPXE Scripts

```ipxe
#!ipxe

# Use consistent variable naming
set variable_name value

# Add comments for complex logic
# This section handles parameter validation
isset ${required_param} || goto error

# Use descriptive labels
:error_handling
echo Error message
goto retry
```

### Testing Requirements

#### Local Testing

```bash
# Test all build variants
./scripts/build.sh build minimal
./scripts/build.sh build full
./scripts/build.sh build gpu-optimized

# Run validation
./scripts/build.sh test

# Test in VM
qemu-system-x86_64 -m 4G -boot n ...
```

#### Integration Testing

- Test with actual hardware when possible
- Verify different network configurations
- Test error conditions and recovery
- Validate all supported parameters

### Documentation Requirements

- **Update README** for user-facing changes
- **Add inline comments** for complex code
- **Update examples** when changing interfaces
- **Include troubleshooting** for known issues

## 🔄 Pull Request Process

### Before Submitting

1. **Test thoroughly**

   ```bash
   # Run all tests
   ./scripts/build.sh test

   # Check code style
   nixpkgs-fmt **/*.nix
   shellcheck scripts/*.sh
   ```

2. **Update documentation**
   - Update README for user-facing changes
   - Add/update examples
   - Update troubleshooting guide

3. **Write commit message**
   - See [How to Write a Git Commit Message](https://cbea.ms/git-commit/)
   - Don't use conventional commits

### Submitting the PR

1. **Create descriptive PR**
   - Use the PR template
   - Explain what the change does
   - Link related issues
   - Include testing information

2. **Ensure CI passes**
   - All automated tests must pass
   - Fix any linting or formatting issues
   - Address reviewer feedback promptly

3. **Be responsive**
   - Respond to review comments
   - Make requested changes
   - Ask questions if unclear

## 🏗 Architecture Guidelines

### Module Design

- **Single responsibility**: Each module should have one clear purpose
- **Configurable**: Use options for customization
- **Composable**: Modules should work well together
- **Documented**: Include descriptions for all options

### Error Handling

- **Fail fast**: Detect errors early in the process
- **Graceful degradation**: Provide fallbacks when possible
- **Clear messages**: Error messages should be actionable
- **Recovery options**: Provide ways to recover from failures

### Security Considerations

- **Least privilege**: Run with minimal required permissions
- **Input validation**: Validate all user inputs
- **Secure defaults**: Choose secure default configurations
- **Audit trail**: Log security-relevant events

## 📋 Issue Triage

### Labels We Use

- `bug` - Something isn't working
- `enhancement` - New feature or improvement
- `documentation` - Documentation improvements
- `good first issue` - Good for new contributors
- `help wanted` - Extra attention needed
- `priority: high` - Urgent issues
- `priority: low` - Nice to have improvements

### Priority Guidelines

- **Critical**: Security issues, data loss, system crashes
- **High**: Major functionality broken, performance issues
- **Medium**: Minor bugs, feature requests with strong use case
- **Low**: Cosmetic issues, edge cases, nice-to-have features

## 🎯 Contribution Ideas

### Beginner-Friendly

- Fix typos in documentation
- Add usage examples
- Improve error messages
- Add validation for configuration options

### Intermediate

- Add support for new hardware
- Improve installation performance
- Add new build variants
- Enhance monitoring capabilities

### Advanced

- ARM64 architecture support
- Integration with cloud providers
- Advanced networking features
- Security hardening improvements

## 🏆 Recognition

### Contributors

All contributors are recognized in:

- GitHub contributors list
- Release notes for significant contributions
- Annual contributor summary

### Maintainer Path

Regular contributors may be invited to become maintainers with:

- Commit access to the repository
- Ability to review and merge PRs
- Responsibility for project direction

## 📞 Getting Help

### Development Questions

- **GitHub Discussions**: Best for design questions
- **Issues**: For specific bugs or features
- **Matrix Chat**: Real-time development discussion
- **Email**: Direct contact with maintainers

### Code Review

- All PRs receive thorough review
- Feedback is constructive and educational
- Multiple reviewers for significant changes
- Maintainer approval required for merging

---

**Thank you for contributing!** 🚀

Your contributions help create better infrastructure automation tools for the
entire community.
