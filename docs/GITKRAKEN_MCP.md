# GitKraken MCP Setup for Claude Code

This guide helps you set up the GitKraken MCP server for enhanced Git operations within Claude Code.

## What is GitKraken MCP?

GitKraken MCP (Model Context Protocol) gives AI assistants like Claude Code safe access to Git, issues, and project context directly inside your workflow. It works with GitHub, GitLab, Bitbucket, Azure DevOps, and Jira.

## Installation Steps

### 1. Install GitKraken CLI

**Windows**:
```bash
winget install gitkraken.cli
```

**macOS**:
```bash
brew install gitkraken-cli
```

**Linux**:
Download from [GitKraken CLI releases](https://github.com/gitkraken/gk-cli/releases)

### 2. Verify Installation

Close and reopen your terminal, then:
```bash
gk --version
```

You should see the version number.

### 3. Authenticate with GitKraken

```bash
gk auth login
```

Follow the browser prompts to authenticate with your GitKraken account (you may need to create a free account).

### 4. Configure MCP for Claude Code

**macOS/Linux**:
```bash
claude mcp add --transport stdio gitkraken -- gk mcp
```

**Windows (PowerShell)**:
```bash
claude mcp add --transport stdio gitkraken -- gk mcp
```

**Windows (Command Prompt)**:
```bash
claude mcp add --transport stdio gitkraken -- cmd /c gk mcp
```

### 5. Verify Configuration

```bash
claude mcp list
```

You should see `gitkraken` in the list of configured servers.

## What GitKraken MCP Enables

Once configured, Claude Code can:

- **Safe Git operations**: Create branches, commits, and pull requests with confirmation
- **Context-aware assistance**: Understand your repository structure and history
- **Issue tracking**: Work with GitHub Issues, GitLab Issues, Jira tickets
- **Code review**: Analyze pull requests and suggest improvements
- **Multi-platform**: Works across GitHub, GitLab, Bitbucket, Azure DevOps

## Security

GitKraken MCP requires confirmation before executing commands, so you maintain full control over Git operations.

## Troubleshooting

### "gk: command not found"

1. Close and reopen your terminal
2. On Windows, restart your terminal/IDE
3. Verify installation path is in your PATH environment variable

### Authentication issues

```bash
# Check authentication status
gk auth status

# Re-authenticate if needed
gk auth logout
gk auth login
```

### MCP not showing in Claude Code

```bash
# Remove and re-add
claude mcp remove gitkraken
claude mcp add --transport stdio gitkraken -- gk mcp
```

## Resources

- [GitKraken MCP Documentation](https://help.gitkraken.com/cli/gk-cli-mcp/)
- [GitKraken CLI Documentation](https://www.gitkraken.com/cli)
- [Model Context Protocol](https://modelcontextprotocol.io/)

## Alternative: Manual Git Operations

If you prefer not to use GitKraken MCP, Claude Code can still work with Git using standard git commands. The MCP integration simply provides enhanced context and safety features.
