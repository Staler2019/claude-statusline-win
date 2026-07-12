# claude-statusline

Configure your Claude Code statusline to show limits, directory and git info

![demo](./.github/demo.png)

## Install

Run the command below to set it up

```bash
npx @staler2019/claude-statusline-win
```

It backups your old status line if any, copies the right status line script for your platform (`~/.claude/statusline.sh` on macOS/Linux, `~/.claude/statusline.ps1` on Windows), and configures your Claude Code settings. Git Bash/WSL is **not** required on Windows — native PowerShell 5.1 (already installed on Windows 10/11) is used.

## Requirements

**macOS / Linux:**

- [jq](https://jqlang.github.io/jq/) — for parsing JSON
- curl — for fetching rate limit data
- git — for branch info

On macOS:

```bash
brew install jq
```

**Windows:**

- git — for branch info

That's it — the Windows status line script (`statusline.ps1`) uses PowerShell's built-in JSON parsing and `Invoke-RestMethod` instead of `jq`/`curl`.

## Uninstall

```bash
npx @staler2019/claude-statusline-win --uninstall
```

If you had a previous statusline, it restores it from the backup. Otherwise it removes the script and cleans up your settings.

## Special Thanks

This project is a fork of [claude-statusline](https://github.com/kamranahmedse/claude-statusline) by [Kamran Ahmed](https://github.com/kamranahmedse), adding native Windows support and other improvements. Many thanks to him for the original work this builds on.

## License

MIT
