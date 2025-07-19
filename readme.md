# PHP Version Manager for Windows

## Installation

Clone the repo and add the directory to you Path variable.

```sh
git clone https://github.com/drissBoumlik/pvm

cd pvm
cp .env.example .env
```

Check .env and edit with your own values and
then run this command to setup pvm

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force

.\pvm.ps1 setup
```


## Usage

Display the avilable options

```sh
pvm help
```


Display active version

```sh
pvm current
```


This one lists the PHP installations. Type 'available' at the end to see what can be installed. Add `-f` to load from the online source.

```sh
pvm list [available [-f]]
```


Install a specific version. Add `-d` to include xdebug

```sh
pvm install [version] [-d]
```


Uninstall a specific version

```sh
pvm uninstall [version]
```


Switch to use the specified version

```sh
pvm use [version]
```

> [!NOTE]  
> Most of the commands edits or adds to the  system environment variables, to reload the updates without restarting your terminal, you need to install chocolatey, and run `refreshenv` command
