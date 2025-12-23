# PHP Version Manager for Windows

PVM (PHP Version Manager) is a lightweight PowerShell tool for Windows that makes it easy to install, switch, and manage multiple PHP versions.

## Installation & Setup

Clone the repo and add the directory to your PATH variable.

```sh
git clone https://github.com/drissboumlik/pvm
cd pvm

# Run this command to setup pvm
pvm setup
```

## Usage


```sh
# Display the available options
pvm help

# Display help for a specific command
pvm help <command>
# Example: pvm help setup

# Display information about the current PHP (version, path, extensions, settings)
pvm info # pvm ini info

# Display information about the current PHP extensions
pvm info extensions # pvm ini info extensions

# Display information about the current PHP settings
pvm info settings # pvm ini info settings

# Display information about the current PHP (version, path, extensions, settings) with 'cache' in their name
pvm info --search=<term> # pvm ini info --search=<term>
# Example: pvm info --search=cache

# Display active PHP version
pvm current

# List installed PHP versions
pvm list # pvm ls

# List installed versions with 8.2 in the name
pvm list --search=<version>
# Example: pvm list --search=8.2

# List installable PHP versions from remote source
pvm list available # pvm ls available

# List available versions with 8.2 in the name
pvm list available --search=<version>
# Example: pvm list available --search=8.2

# Install a specific version.
pvm install <version> # pvm i <version>
# Example: pvm install 8.4 # pvm i 8.4

# Install the php version specified on your project.
pvm install auto # pvm i auto

# Uninstall a specific version
pvm uninstall <version> # pvm rm <version>
# Example: pvm uninstall 8.4 # pvm rm 8.4

# Switch to use the specified version
pvm use <version>
# Example: pvm use 8.4

# Switch to use the detected PHP version from .php-version or composer.json in your current project/directory
pvm use auto
```

### Manage php.ini settings and extensions directly from the CLI.

```sh
# Check status of multiple extensions
pvm ini status <extension> # It shows all matching extensions
# Example: pvm ini status xdebug opcache
# Example: pvm ini status sql

# Enable or disable multiple extensions
pvm ini enable <extension> # It shows all matching extensions
# Example: pvm ini enable xdebug opcache
# Example: pvm ini enable sql
pvm ini disable <extension> # It shows all matching extensions
# Example: pvm ini disable xdebug opcache
# Example: pvm ini disable sql

# Set or Get multiple settings values and change the status
pvm ini set <setting>=<value> [--disable] # Default is enabling the setting
pvm ini set <setting> [--disable] # It shows all matching settings
# Example: pvm ini set memory_limit=512M max_file_uploads=20
# Example: pvm ini set max_input_time=60 --disable
# Example: pvm ini set memory=1G
# Example: pvm ini set memory
pvm ini get <setting> # It shows all matching settings
# Example: pvm ini get memory_limit max_file_uploads
# Example: pvm ini get memory

# Install extensions from remote source
pvm ini install <extension>
# Example: pvm ini install opcache

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
pvm ini restore

# Check logs
pvm log --pageSize=[number] # Default value is 5
# Example: pvm log --pageSize=3
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
pvm profile delete <name>
# Example: pvm profile delete old-profile

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

```sh
pvm test [files = (files inside the tests/ directory)] [--coverage[=<number>]] [--verbosity=(None|Normal|Detailed|Diagnostic)] [--tag=<tag>]

# Examples:
pvm test # .............................. Runs all tests with Normal (default) verbosity.
pvm test use install # .................. Runs only 'use.tests.ps1' and 'install.tests.ps1' files with Normal verbosity.
pvm test --verbosity=Detailed # ......... Runs all tests with Detailed verbosity.
pvm test --coverage # ................... Runs all tests and generates coverage report (target: 75%)
pvm test --coverage=80.5 # .............. Runs all tests and generates coverage report (target: 80.5%)
pvm test --tag=myTag #................... Runs helpers.tests.ps1 and list.tests.ps1 with Diagnostic verbosity and only runs tests with tag "myTag".
```

## Contributing

Please see [CONTRIBUTING](CONTRIBUTING.md) for details.

## Credits

- [Driss](https://github.com/drissboumlik)
- [All Contributors](https://github.com/drissboumlik/pvm/contributors)

## License

The MIT License (MIT). Please see [License File](LICENSE) for more information.