![GitHub release](https://img.shields.io/github/v/release/usepvm/pvm)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Windows](https://img.shields.io/badge/Windows-10%2F11-blue)

# PHP Version Manager for Windows

PVM (PHP Version Manager) is a lightweight PowerShell tool for Windows that makes it easy to install, switch, and manage multiple PHP versions.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation & Setup](#installation--setup)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [Automatic Version Detection](#automatic-version-detection)
  - [Managing php.ini](#manage-phpini-settings-and-extensions)
  - [Profiles](#manage-php-configuration-profiles)
  - [Cache](#managing-cache)
  - [Aliases](#command-aliases)
  - [Build Types](#build-types)
  - [Namespaced Commands](#namespaced-commands)
- [Data Storage](#data-storage)
- [Running Tests](#running-tests)
  - [Requirements](#requirements-1)
  - [Run the tests](#run-the-tests)
- [Contributing](#contributing)
- [Credits](#credits)
- [License](#license)

## Features

- Install and manage multiple PHP versions
- Switch PHP versions instantly
- Auto-detect PHP version from project files
- Manage php.ini settings
- Enable, disable, install, and remove extensions
- Save and load reusable PHP configuration profiles
- Built-in cache management
- Built-in test runner with coverage reporting

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1+ or PowerShell 7+
- Internet connection for installing PHP versions and extensions

## Installation & Setup

Clone the repository, copy the environment file, run setup, and ensure the project directory is available in your PATH.

```sh
git clone https://github.com/drissboumlik/pvm
cd pvm
cp .env.example .env # edit .env to set your config values before running setup

# Run this command to setup pvm
pvm setup

# Ensure PVM directories and default files exist
pvm repair
```

## Quick Start

The commands below install PHP 8.4, switch to it, and verify the active version.

```sh
# Install PHP 8.4
pvm install 8.4

# Switch to PHP 8.4
pvm use 8.4

# Verify active version
pvm current

# List installed versions
pvm list
```

## Usage

```sh
# Display the available options
pvm help

# Display help for a specific command
pvm help <command>
# Example: pvm help setup

# Displays information about the environment including PVM version, currently active PHP version, paths, and environment variables.
pvm info
pvm info --verbose

# Display active PHP version
pvm current

# List installed PHP versions
pvm list # pvm ls

# List installed versions with 8.2 in the name
pvm list --search=<version>
# Example: pvm list --search=8.2

# List installed versions matching x86 and nts
pvm list [x86|x64] [ts|nts]
# Example: pvm list x86 nts

# List installable PHP versions from remote source
pvm list available # pvm ls available

# List installable PHP versions from remote source matching x86 and nts
pvm list available [x86|x64] [ts|nts]
# Example: pvm list available x86 nts

# List available versions with 8.2 in the name
pvm list available --search=<version>
# Example: pvm list available --search=8.2

# Install a specific version.
pvm install <version> # pvm i <version>
# Example: pvm install 8.4 # pvm i 8.4

# Install a specific version for a specific arch & build type
pvm install <version> [x86|x64] [ts|nts]
# Example: pvm install 8.4 x64 nts # pvm i 8.4 x64 nts

# Install the latest available PHP version.
pvm install latest # pvm i latest

# Uninstall a specific version
pvm uninstall <version> [--yes|-y] # pvm rm <version> [--yes|-y]
# Example: pvm uninstall 8.4 # pvm rm 8.4
# Example: pvm uninstall 8.4 -y # pvm rm 8.4 -y # Skip confirmation

# Switch to use the specified version
pvm use <version>
# Example: pvm use 8.4

# Update PVM to the latest version from the repository
pvm update [--check]
# Example: pvm update
# Example: pvm update --check
```

### Automatic Version Detection

PVM can detect the PHP version from:

- `.php-version`
- `composer.json`

Example `.php-version`:

```text
8.4
```

Example `composer.json`:

```json
{
  "require": {
    "php": "^8.4"
  }
}
```

```sh
# Install the PHP version specified by your project.
pvm install auto # pvm i auto

# Switch to use the detected PHP version from .php-version or composer.json in your current project/directory
pvm use auto
```

### Manage php.ini settings and extensions

```sh
# Check status of multiple extensions
pvm ini status <extension> # It shows all matching extensions
# Example: pvm ini status xdebug opcache
# Example: pvm ini status sql

# Enable or disable multiple extensions
pvm ini enable <extension> # It shows all matching extensions then enables the selected one
# Example: pvm ini enable xdebug opcache
# Example: pvm ini enable sql
pvm ini disable <extension> # It shows all matching extensions then disables the selected one
# Example: pvm ini disable xdebug opcache
# Example: pvm ini disable sql

# Set or Get multiple settings values and change the status
pvm ini set <setting>=<value> [--disable] # Default is enabling the setting
pvm ini set <setting> [--disable] # It shows all matching settings then enables the selected one
# Example: pvm ini set memory_limit=512M max_file_uploads=20
# Example: pvm ini set max_input_time=60 --disable
# Example: pvm ini set memory=1G
# Example: pvm ini set memory
pvm ini get <setting> # It shows all matching settings
# Example: pvm ini get memory_limit max_file_uploads
# Example: pvm ini get memory

# Install extensions from remote source
pvm ini add <extension> [--yes|-y] # It shows all matching extensions then adds the selected one
# Example: pvm ini add opcache
# Example: pvm ini add opcache -y # Skip confirmation

# Remove extensions from extensions directory and ini file
pvm ini remove <extension> [--yes|-y] # It shows all matching extensions then removes the selected one
# Example: pvm ini remove opcache
# Example: pvm ini remove opcache -y # Skip confirmation

# List installed extensions
pvm ini list

# List available extensions from remote source
pvm ini list available

# List installed extensions with 'zip' in their name
pvm ini list --search=<extension>
# Example: pvm ini list --search=zip

# List available extensions with 'zip' in their name
pvm ini list available --search=<extension>
# Example: pvm ini list available --search=zip

# Restore backup
pvm ini restore # PVM automatically creates php.ini backups before modifying settings or extensions.

# Display information about the current PHP (version, path, extensions, settings)
pvm ini info

# Display information about the current PHP extensions
pvm ini info extensions

# Display information about the current PHP settings
pvm ini info settings

# Display information about the current PHP (version, path, extensions, settings) with 'cache' in their name
pvm ini info --search=<term>
# Example: pvm ini info --search=cache
```

### Check logs

```sh
pvm log --pageSize=[number] --search=<term> # Default value is 5
# Example: pvm log --pageSize=3 --search=error
```

### Manage PHP Configuration Profiles

Save, load, and share PHP settings and extensions using JSON profiles:

```sh
# Save current PHP configuration to a profile
pvm profile save <name> [description]
# Example: pvm profile save development
# Example: pvm profile save production "Production configuration"

# Load and apply a saved profile
pvm profile load <name>
# Example: pvm profile load development

# List all available profiles
pvm profile list

# Show detailed profile contents
pvm profile show <name>
# Example: pvm profile show development

# Delete a profile
pvm profile delete <name> [--yes|-y]
# Example: pvm profile delete old-profile
# Example: pvm profile delete old-profile -y # Skip confirmation

# Remove all profiles files
pvm profile clear [--yes|-y]
# Example: pvm profile clear -y # Skip confirmation

# Export profile to a JSON file
pvm profile export <name> [path]
# Example: pvm profile export development
# Example: pvm profile export dev ./backup.json

# Import profile from a JSON file
pvm profile import <path> [name]
# Example: pvm profile import ./my-profile.json
# Example: pvm profile import ./profile.json custom-name
```

**Profile Structure**: Profiles are stored as JSON files in `storage/data/profiles/` and contain:

- Popular/common PHP settings (key-value pairs with enabled/disabled state)
- Popular/common extensions (enabled/disabled state and type)
- Metadata (name, description, creation date, PHP version)

**Note**: Only popular/common settings and extensions are saved in profiles. This keeps profiles focused and manageable.

### Managing Cache

Manage the cache directory and its contents:

```sh
# List files in the cache directory
pvm cache list

# Show details of a specific cache file
pvm cache show <name>
# Example: pvm cache show example-cache

# Remove a specific cache file
pvm cache delete <name> [--yes|-y]
# Example: pvm cache delete example-cache
# Example: pvm cache delete example-cache --y # Skip confirmation

# Remove all cache files
pvm cache clear [--yes|-y]
# Example: pvm cache clear --y # Skip confirmation
```

### Command Aliases

You can use the following aliases for commonly used commands.

To view the complete list from the CLI:

```sh
pvm aliases
```

| Alias  | Command   |
| ------ | --------- |
| ?      | help      |
| h      | help      |
| init   | setup     |
| cur    | current   |
| active | current   |
| ls     | list      |
| i      | install   |
| u      | uninstall |
| switch | use       |
| on     | enable    |
| off    | disable   |
| a      | add       |
| +      | add       |
| rm     | remove    |
| -      | remove    |
| del    | delete    |
| cls    | clear     |

### Build Types

| Option | Meaning         |
| ------ | --------------- |
| x86    | 32-bit          |
| x64    | 64-bit          |
| ts     | Thread Safe     |
| nts    | Non Thread Safe |

### Namespaced Commands

The following command groups support both syntaxes:

```sh
pvm help <subcommand>
pvm help:<subcommand>

pvm ini <subcommand>
pvm ini:<subcommand>

pvm profile <subcommand>
pvm profile:<subcommand>

pvm cache <subcommand>
pvm cache:<subcommand>
```

## Data Storage

| Item         | Location               |
| ------------ | ---------------------- |
| PHP Versions | storage/php/           |
| Profiles     | storage/data/profiles/ |
| Cache        | storage/data/cache/    |
| Logs         | storage/logs/          |

## Running Tests

Run tests against the PowerShell scripts in the repo — especially useful for contributors verifying changes before submitting a pull request:

### Requirements

To run tests with, you need to have the Pester testing framework installed. Pester is a testing framework for PowerShell.

Open PowerShell as Administrator and run:

```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck
```

> 💡 If prompted to trust the repository, type Y and press Enter.

You can verify the installation with:

```powershell
Get-Module -ListAvailable Pester
```

### Run the tests

By default, pvm test auto-detects pwsh if available, falling back to powershell. Use --shell=powershell or --shell=pwsh to force a specific engine — useful for verifying PS 5.1/7 cross-version compatibility.

```sh
pvm test [files = (files inside the tests/ directory)] [--exclude=files] [--coverage[=<number>]] [--verbosity=(None|Normal|Detailed|Diagnostic)] [--tag=<tag>] [--sort=[coverage|duration|file|-coverage|-duration|-file]] [--group=[coverage|folder]] [--shell=[powershell|pwsh]]

# Examples:
pvm test # .............................. Runs all tests with Normal (default) verbosity.
pvm test use install # .................. Runs only 'use.tests.ps1' and 'install.tests.ps1' files with Normal verbosity.
pvm test --exclude=use,install # ........ Runs all tests except 'use.tests.ps1' and 'install.tests.ps1' with Normal verbosity.
pvm test --verbosity=Detailed # ......... Runs all tests with Detailed verbosity.
pvm test --coverage # ................... Runs all tests and generates coverage report (target: 75%)
pvm test --coverage=80.5 # .............. Runs all tests and generates coverage report (target: 80.5%)
pvm test --sort=duration # .............. Runs all tests and sorts results by duration (ascending)
pvm test --sort=-duration # ............. Runs all tests and sorts results by duration (descending)
pvm test --tag=myTag #................... Runs only runs tests with tag "myTag".
pvm test --group=folder # ............... Runs all tests and groups results by folder
pvm test --shell=powershell # ................. Forces Windows PowerShell (powershell.exe) instead of auto-detected pwsh.
pvm test --shell=pwsh # ....................... Forces PowerShell 7+ (pwsh.exe).
```

## Contributing

Please see [CONTRIBUTING](CONTRIBUTING.md) for details.

## Credits

- [Driss](https://github.com/drissboumlik)
- [All Contributors](https://github.com/usepvm/pvm/graphs/contributors?all=1)

## License

The MIT License (MIT). Please see [License File](LICENSE) for more information.
