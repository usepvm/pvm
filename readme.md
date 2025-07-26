# PHP Version Manager for Windows

## Installation & Setup

Clone the repo and add the directory to you Path variable.

```sh
git clone https://github.com/drissboumlik/pvm

cd pvm
```

Run this command to setup pvm
- Use '--overwrite-path-backup' option to overwrite the backup of the PATH variable (if it exists).
```sh
pvm setup [--overwrite-path-backup]
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


### Manage php.ini settings and extensions directly from the CLI.

Enable or disable PHP extensions

```sh
pvm ini enable xdebug

pvm ini disable xdebug
```

Set a setting

```sh
pvm ini set memory_limit=512M
```

Get a setting

```sh
pvm ini get memory_limit
```

Restore backup

```sh
pvm ini restore
```

> [!NOTE]  
> Most of the commands edits or adds to the system environment variables, to reload the updates without restarting your terminal, you need to install chocolatey, and run `refreshenv` command
