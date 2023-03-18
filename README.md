# StringsCheck

## Introduction

StringsCheck is a command line tool and a Swift library for checking that strings files inside Xcode `.lproj` folders contain translations for the same strings.

## Usage

Run StringsCheck from the command line by giving it path to a directory where you have `.lproj` directories, and a list of languages to check:

```shell
$ stringscheck /path/to/project/resources en fi sv
```

StringsCheck checks that each language has the same `.strings` files and each set of `.strings` files with the same name has the same messages in every language.
