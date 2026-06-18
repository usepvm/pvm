
function Get-Actions {
    param ($arguments)

    $script:arguments = $arguments

    return [ordered]@{
        'help'      = @{
            command     = 'pvm help [command]';
            description = 'Display help for a command.';
            usage       = [ordered]@{
                USAGE       = 'pvm help [command]';
                DESCRIPTION = @(
                    'Displays help for a command.',
                    'If no command is provided, displays help for all commands.'
                );
            };
            action      = { return Invoke-Help -arguments $script:arguments }
        }
        'setup'     = @{
            command     = 'pvm setup';
            description = 'Configure PHP environment variables, paths, directories, and files.';
            usage       = [ordered]@{
                USAGE       = 'pvm setup';
                DESCRIPTION = @(
                    'Sets environment variables and config paths for PHP.',
                    'This command should be run once after installation to configure PVM for first use.'
                )
            };
            action      = { return Invoke-Setup }
        }
        'current'   = @{
            command     = 'pvm current';
            description = 'Display the active PHP version.';
            usage       = [ordered]@{
                USAGE       = 'pvm current'
                DESCRIPTION = @(
                    'Shows the currently active PHP version, including the absolute path.',
                    'It also shows the status of xdebug and opcache.'
                )
            };
            action      = { return Invoke-Current }
        }
        'list'      = @{
            command     = 'pvm list [available] [x86|x64] [ts|nts]';
            description = "List installed PHP versions, or use 'available' to show versions that can be installed.";
            usage       = [ordered]@{
                USAGE       = 'pvm list [available] [--search=<term>] [x86|x64] [ts|nts] (alias: ls for list)'
                DESCRIPTION = @(
                    'Shows installed PHP versions.'
                    "With the 'available' argument, shows PHP versions available for installation. The available-version list is cached for $($PVMConfig.env.CACHE_MAX_HOURS) hours."
                )
                EXAMPLES    = @(
                    'pvm list ........................... Show installed versions'
                    'pvm list x64 ts .................... Show installed versions matching x64 TS'
                    'pvm list available ................. Show versions available for installation instead of installed versions'
                    'pvm list available x64 ts .......... Show versions available matching x64 TS'
                    'pvm list --search=8.2 .............. Show installed versions with 8.2 in the name'
                    'pvm list available --search=8.2 .... Show available versions with 8.2 in the name'
                )
            };
            action      = { return Invoke-List -arguments $script:arguments }
        }
        'install'   = @{
            command     = 'pvm install <version>|[auto] [x86|x64] [ts|nts]';
            description = "Install a specific PHP version, 'latest', or use 'auto' to install the version from composer.json or .php-version.";
            usage       = [ordered]@{
                USAGE       = 'pvm install <version> (alias: pvm i <version>) | pvm install auto | pvm install latest'
                DESCRIPTION = @(
                    'Downloads and installs the PHP version.'
                    "Use 'auto' to automatically select the version based on project configuration files."
                )
                ARGUMENTS   = @(
                    '<version> .... The version must be a number e.g. 8, 8.2 or 8.2.0 (required)'
                    'auto ......... Auto-detect version from project files'
                    'latest ....... Install the latest available PHP version'
                )
                EXAMPLES    = @(
                    'pvm install 8.2 .............. Install specific version'
                    'pvm install auto ............. Install detected version from project files (.php-version or composer.json)'
                    'pvm install 8.2 x64 ts ....... Install specific version matching x64 TS'
                    'pvm install latest ........... Install the latest available PHP version'
                )
            }
            action      = { return Invoke-Install -arguments $script:arguments }
        }
        'uninstall' = @{
            command     = 'pvm uninstall <version>';
            description = 'Remove an installed PHP version.';
            usage       = [ordered]@{
                USAGE       = 'pvm uninstall <version> (alias: pvm rm <version>)'
                DESCRIPTION = @(
                    'Removes the specified PHP version from your system.'
                    'The version must be a version number that is currently installed.'
                )
                ARGUMENTS   = @(
                    '<version> .... The version must be a number e.g. 8, 8.2 or 8.2.0 (required)'
                )
            }
            action      = { return Invoke-Uninstall -arguments $script:arguments }
        }
        'use'       = @{
            command     = 'pvm use <version>|[auto]';
            description = "Switch to a specific PHP version, or use 'auto' to select the version from composer.json or .php-version.";
            usage       = [ordered]@{
                USAGE       = 'pvm use <version> | pvm use auto'
                DESCRIPTION = @(
                    "Switches the active PHP version. You can specify a version number or use 'auto'"
                    'to automatically select the version based on project configuration files.'
                )
                EXAMPLES    = @(
                    'pvm use 8.2.0 .... Switches to PHP version 8.2.0'
                    'pvm use auto ..... Automatically uses version from composer.json or .php-version file'
                )
                ARGUMENTS   = @(
                    '<version> ........ Specific PHP version to use'
                    'auto ............. Auto-detect version from project files'
                )
            }
            action      = { return Invoke-Use -arguments $script:arguments }
        }
        'info'      = @{
            command     = 'pvm info [--verbose]';
            description = 'Show PVM status and environment information.';
            usage       = [ordered]@{
                USAGE       = 'pvm info | pvm info --verbose'
                DESCRIPTION = @(
                    'Displays information about the environment,'
                    'including PVM version, currently active PHP version, paths, and environment variables.'
                )
            }
            action      = { return Invoke-Info -arguments $script:arguments }
        }
        'ini'       = @{
            command     = 'pvm ini <action> [<args>]';
            description = "Manage php.ini settings and extensions for the active PHP version.";
            usage       = [ordered]@{
                USAGE       = 'pvm ini <action> [arguments]'
                DESCRIPTION = @(
                    'Manage PHP configuration (php.ini) settings and extensions for the currently active PHP version.'
                )
                ARGUMENTS   = @(
                    'set <setting>=<value> [--disable] ................. Set a php.ini configuration value'
                    'get <setting> ..................................... Get a php.ini configuration value'
                    'enable <extension> ................................ Enable a PHP extension'
                    'disable <extension> ............................... Disable a PHP extension'
                    'status <extension> ................................ Check if extension is enabled'
                    'info [extensions] [settings] [--search=<term>] .... Displays information about the environment and php.ini information summary'
                    'restore ........................................... Restore original php.ini from backup'
                    'add <extension> ................................... Install a PHP extension'
                    'remove <extension> ................................ Remove a PHP extension'
                    "list [available] [--search=<term>] ................ Lists the PHP extensions. Type 'available' at the end to see what can be installed."
                )
                EXAMPLES    = @(
                    'pvm ini set memory_limit=256M ..................... Sets memory limit to 256MB and enables the setting'
                    'pvm ini set opcache.enable=1 --disable ............ Sets opcache.enable to 1 and disables the setting'
                    "pvm ini set memory=1G ............................. Shows matching settings for 'memory' then prompts for value and enables the setting"
                    "pvm ini set memory ................................ Shows matching settings for 'memory' then prompts for value and enables the setting"
                    'pvm ini get memory_limit .......................... Shows current memory limit setting'
                    "pvm ini get memory...... .......................... Shows matching settings for 'memory' setting"
                    'pvm ini enable mysqli ............................. Enables the mysqli extension'
                    "pvm ini enable sql ................................ Shows matching extensions for 'sql' then enables the chosen one"
                    'pvm ini disable xdebug ............................ Disables the xdebug extension'
                    "pvm ini disable sql ............................... Shows matching extensions for 'sql' then disables the chosen one"
                    'pvm ini status opcache ............................ Shows opcache extension status'
                    "pvm ini status sql ................................ Shows matching extensions status for 'sql'"
                    'pvm ini info ...................................... Lists php.ini settings and extensions'
                    "pvm ini info --search=cache ....................... Lists php.ini settings and extensions with 'cache' in their name"
                    'pvm ini info extensions ........................... Lists php.ini extensions only'
                    'pvm ini info settings ............................. Lists php.ini settings only'
                    'pvm ini add opcache ............................... Installs the opcache extension'
                    "pvm ini add sql ................................... Shows matching extensions for 'sql' then installs the chosen one"
                    'pvm ini remove xdebug ............................. Removes the xdebug extension'
                    "pvm ini remove sql ................................ Shows matching extensions for 'sql' then removes the chosen one"
                    'pvm ini list ...................................... Lists the PHP extensions'
                    'pvm ini list available ............................ Lists available PHP extensions'
                    "pvm ini list --search=zip ......................... Lists PHP extensions with 'zip' in their name"
                    "pvm ini list available --search=zip ............... Lists available PHP extensions with 'zip' in their name"
                )
            }
            action      = { return Invoke-Ini -arguments $script:arguments }
        }
        'profile'   = @{
            command     = 'pvm profile <action> [<args>]';
            description = 'Save, load, inspect, import, and export PHP configuration profiles.';
            usage       = [ordered]@{
                USAGE       = 'pvm profile <action> [arguments]'
                DESCRIPTION = @(
                    'Manage PHP configuration profiles stored as JSON files.',
                    'Profiles contain popular/common PHP settings and extension states that can be saved and loaded.',
                    "Only popular/common settings and extensions are included. Other settings/extensions can be added manually using 'pvm ini' commands."
                )
                ARGUMENTS   = @(
                    'save <name> [description] .................... Save current PHP configuration to a profile'
                    'load <name> .................................. Load and apply a saved profile'
                    'list ......................................... List all available profiles'
                    'show <name> .................................. Show detailed profile contents'
                    'delete <name> ................................ Delete a profile'
                    'export <name> [path] ......................... Export profile to a JSON file'
                    'import <path> [name] ......................... Import profile from a JSON file'
                )
                EXAMPLES    = @(
                    "pvm profile save development ................. Saves current config as 'development' profile"
                    "pvm profile save production 'Prod config' .... Saves with description"
                    "pvm profile load development ................. Applies 'development' profile to current PHP"
                    'pvm profile list ............................. Lists all saved profiles'
                    'pvm profile show development ................. Shows detailed profile information'
                    'pvm profile delete old-profile ............... Deletes a profile'
                    'pvm profile export development ............... Exports profile to current directory'
                    'pvm profile export dev ./backup.json ......... Exports to specific path'
                    'pvm profile import ./my-profile.json ......... Imports profile from file'
                    'pvm profile import ./profile.json custom ..... Imports with custom name'
                )
            }
            action      = { return Invoke-Profile -arguments $script:arguments }
        }
        'cache'     = @{
            command     = 'pvm cache <action> [<args>]';
            description = 'List, inspect, delete, or clear PVM cache files.';
            usage       = [ordered]@{
                USAGE       = 'pvm cache <action> [arguments]'
                DESCRIPTION = @(
                    'Manage PVM cache files stored in the cache directory.'
                )
                ARGUMENTS   = @(
                    'list ......................................... List all available cache files'
                    'show <name> .................................. Show detailed cache file contents'
                    'delete <name> ................................ Delete a cache file'
                    'clear ........................................ Delete all cache files'
                )
                EXAMPLES    = @(
                    'pvm cache list ............................... Lists all available cache files'
                    'pvm cache show available_php_versions ........ Shows detailed cache file information'
                    'pvm cache delete old-cache ................... Deletes a cache file'
                    'pvm cache clear .............................. Deletes all cache files'
                )
            }
            action      = { return Invoke-Cache -arguments $script:arguments }
        }
        'aliases'   = @{
            command     = 'pvm aliases';
            description = 'List all command aliases.';
            usage       = [ordered]@{
                USAGE       = 'pvm aliases'
                DESCRIPTION = @(
                    'Lists all available aliases.'
                )
                EXAMPLES    = @(
                    'pvm aliases ......................... Lists all available aliases'
                )
            }
            action      = { return Invoke-Aliases -arguments $script:arguments }
        }
        'log'       = @{
            command     = 'pvm log';
            description = 'Display recent PVM log entries.';
            usage       = [ordered]@{
                USAGE       = "pvm log --pageSize=[number] [--search=<term>] (default is $($PVMConfig.env.DEFAULT_LOG_PAGE_SIZE))"
                DESCRIPTION = @(
                    'Displays the PVM log file contents, showing recent errors,'
                    'and system messages. Useful for troubleshooting issues.'
                )
                EXAMPLES    = @(
                    "pvm log ................... Shows the last $($PVMConfig.env.DEFAULT_LOG_PAGE_SIZE) entries of the log file"
                    'pvm log --pageSize=50 ..... Shows the last 50 entries of the log file'
                    "pvm log --search=error .... Shows entries matching 'error' term"
                )
            }
            action      = { return Invoke-Log -arguments $script:arguments }
        }
        'test'      = @{
            command     = 'pvm test';
            description = 'Run the PVM test suite.';
            usage       = [ordered]@{
                USAGE       = 'pvm test [files] [--exclude=files] [--coverage[=<number>]] [--verbosity=<verbosity>] [--tag=<tag>] [--sort=[coverage|duration|file]]'
                DESCRIPTION = @(
                    'Runs the PVM test suite to verify that the installation and configuration'
                    'are working correctly. This includes testing PHP version switching,'
                    'path resolution, and core functionality.'
                )
                EXAMPLES    = @(
                    'pvm test ......................... Runs all tests with Normal (default) verbosity'
                    'pvm test use install ............. Runs only use.tests.ps1 and install.tests.ps1 with Normal verbosity.'
                    'pvm test --exclude=use,install ... Runs all tests except use.tests.ps1 and install.tests.ps1 with Normal verbosity.'
                    'pvm test --verbosity=Detailed .... Runs all tests with Detailed verbosity.'
                    'pvm test --coverage .............. Runs all tests and generates coverage report (target: 75%)'
                    'pvm test --coverage=80 ........... Runs all tests and generates coverage report (target: 80%)'
                    "pvm test --tag=unit .............. Runs only tests with tag 'unit'"
                    'pvm test --sort=coverage ......... Runs all tests and sort results by coverage'
                )
                ARGUMENTS   = @(
                    'files ............................ Run only specific test files (e.g. use, install)'
                )
                OPTIONS     = @(
                    '--sort=[coverage|duration|file] .. Sort tests results by coverage, duration or file names'
                    '--coverage[=<number>] ............ Generate coverage report with optional target percentage (default: 75%)'
                    '--verbosity=<verbosity> .......... Set verbosity level (None, Normal (Default), Detailed, Diagnostic)'
                    '--tag=<tag> ...................... Run only tests with specific tag'
                    '--exclude=[files] ................ Run all tests except selected files'
                )
            }
            action      = { return Invoke-Test -arguments $script:arguments }
        }
    }
}
