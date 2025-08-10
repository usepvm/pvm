# PHP Version Manager for Windows

## Installation & Setup

Clone the repo and add the directory to you Path variable.

```sh
git clone https://github.com/drissboumlik/pvm

cd pvm
```

Run this command to setup pvm

```sh
pvm setup
```


## Usage

Display the avilable options

```sh
pvm help
```


Display active PHP version

```sh
pvm current
```


This one lists the PHP installations. Type 'available' at the end to see what can be installed. Add `-f` or `--force` to load from the online source.

```sh
pvm list [available [-f]] # or --force
```


Install a specific version. 
- Add `--xdebug` to enable xdebug
- Add `--opcache` to enable opcache
- Add `--dir=/absolute/path/` to specify a custom installation directory

```sh
pvm install <version> [--xdebug] [--opcache] [--dir=/absolute/path/]
```


Uninstall a specific version

```sh
pvm uninstall <version>
```


Switch to use the specified version

```sh
pvm use <version>
```

Switch to use the detected PHP version from .php-version or composer.json in your current project/directory

```sh
pvm use auto
```


### Manage php.ini settings and extensions directly from the CLI.

Enable or disable PHP multiple extensions

```sh
pvm ini enable xdebug opcache

pvm ini disable xdebug opcache
```

Set or Get multiple settings values

```sh
pvm ini set memory_limit=512M max_file_uploads=20

pvm ini get memory_limit max_file_uploads
```

Restore backup

```sh
pvm ini restore
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
pvm test # Runs all tests with Normal verbosity.
pvm test use install # Runs only use.tests.ps1 and install.tests.ps1 with Normal verbosity.
pvm test Detailed # Runs all tests with Detailed verbosity.
pvm test helpers list Diagnostic # Runs helpers.tests.ps1 and list.tests.ps1 with Diagnostic verbosity.
```
