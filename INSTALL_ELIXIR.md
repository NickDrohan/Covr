# Installing Elixir on Windows

## Quick Install (Recommended)

### Using Chocolatey (Easiest)

1. Install Chocolatey if you don't have it:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
   ```

2. Install Elixir:
   ```powershell
   choco install elixir
   ```

3. Restart your terminal and verify:
   ```powershell
   mix --version
   ```

### Using asdf (Version Manager)

1. Install asdf-vm:
   ```powershell
   # Install via Git
   git clone https://github.com/asdf-community/asdf-vm.git $HOME\.asdf
   ```

2. Add to PowerShell profile:
   ```powershell
   Add-Content $PROFILE ". $HOME\.asdf\asdf.sh"
   ```

3. Install Erlang and Elixir:
   ```powershell
   asdf plugin add erlang
   asdf plugin add elixir
   asdf install erlang 26.2.5
   asdf install elixir 1.16.2
   asdf global erlang 26.2.5
   asdf global elixir 1.16.2
   ```

### Manual Install

1. Download Erlang from: https://www.erlang.org/downloads
2. Download Elixir from: https://elixir-lang.org/install.html#windows
3. Follow the installer instructions
4. Restart your terminal

## Verify Installation

```powershell
elixir --version
mix --version
```

## After Installation

Run these commands in your project:

```powershell
cd "c:\Users\Arman\Desktop\Dev\Covr"
mix deps.get
mix ecto.setup
mix phx.server
```

Then open: http://localhost:4000/admin
