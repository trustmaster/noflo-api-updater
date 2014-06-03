# NoFlo API Updater

This command-line tool automates some tasks on updating legacy NoFlo libraries with the latest APIs.

## Features

Currently this tool supports:
 - Semi-automatic update of the old CoffeeScript components to the new Ports API introduced in NoFlo 0.5.

## Installation

If you don't have CoffeeScript installed, then first install the latest CoffeeScript:

```
# npm install -g coffee-script
```

Then install the updater tool

```
# npm install -g noflo-api-updater
```

## Usage

Updating a single `*.coffee` file:

```
$ noflo-api-updater components/MyComponent.coffee
```

Updating all components in the folder:

```
$ noflo-api-updater components
```

There is a `--pretend` option that prints the result on screen rather than overwriting original files:

```
$ noflo-api-updater --pretend components/MyComponent.coffee
```

## Disclaimer

This tool comes with absolutely NO WARRANTY and it is not designed to result into 100% bugproof working code. Use it to aid your manual code refactoring and don't forget to backup / git commit before running this tool.
