# PHP Version Manager for Windows

PVM (PHP Version Manager) is a lightweight PowerShell tool for Windows that makes it easy to install, switch, and manage multiple PHP versions.

## Installation & Setup

Clone the repo and add the directory to you Path variable.

```sh
git clone https://github.com/drissboumlik/pvm
cd pvm

# Run this command to setup pvm
pvm setup
```

## Usage


```sh
# Display the avilable options
pvm help

# Display information about the environment
pvm info
pvm ini info

# Display active PHP version
pvm current

# List installed PHP versions
pvm list

# List installable PHP versions from remote source
pvm list available

# Install a specific version.
pvm install <version>

# Install & enable xdebug
pvm install <version> --xdebug

# Uninstall a specific version
pvm uninstall <version>

# Switch to use the specified version
pvm use <version>

# Switch to use the detected PHP version from .php-version or composer.json in your current project/directory
pvm use auto
```

### Manage php.ini settings and extensions directly from the CLI.

```sh
# Enable or disable PHP multiple extensions
pvm ini enable xdebug opcache
pvm ini disable xdebug opcache

# Set or Get multiple settings values
pvm ini set memory_limit=512M max_file_uploads=20
pvm ini get memory_limit max_file_uploads

# Restore backup
pvm ini restore

# Check logs
pvm log --pageSize=[number] # Default value is 5
```

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
pvm test [files = (files inside the tests/ directory)] [verbosity = (None|Normal|Detailed|Diagnostic)]

# Examples:
pvm test # Runs all tests with Normal (default) verbosity.
pvm test use install # Runs only use.tests.ps1 and install.tests.ps1 with Normal verbosity.
pvm test Detailed # Runs all tests with Detailed verbosity.
pvm test helpers list Diagnostic # Runs helpers.tests.ps1 and list.tests.ps1 with Diagnostic verbosity.
```

## Contributing

Please see [CONTRIBUTING](CONTRIBUTING.md) for details.

## Credits

- [Driss](https://github.com/drissboumlik)
- [All Contributors](https://github.com/drissboumlik/pvm/contributors)

## License

The MIT License (MIT). Please see [License File](LICENSE) for more information.