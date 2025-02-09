# PHP Version Manager for Windows

## Installation

Clone the repo and add the directory to you Path variable.

## Preparation

Check the .env file and copy the "PHP_CURRENT_ENV_NAME" value to the end of your PATH variable : ";%php_current%"

## Usage

```sh
pvm help
```
```sh
pvm current # Display active version
```
```sh
pvm list [available] [-f]
```
This one lists the PHP installations. Type 'available' at the end to see what can be installed. Add '-f' to load from the online source.

```sh                              
pvm install [version] # Install a specific version
```
```sh     
pvm use [version] # Switch to use the specified version
```

> [!NOTE]  
> Most of the commands edits or adds to the  system environment variables, to reload the updates without restarting your terminal, you need to install chocolatey, and run `refreshenv` command