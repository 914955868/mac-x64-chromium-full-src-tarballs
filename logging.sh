#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# This script contains reusable functions for logging and error handling.

# Log an informational message
clog() {
    echo -e "\e[1m[\e[0m\e[32mINFO\e[0m\e[1m]\e[0m: $*"
}

# Log a warning message
cwarn() {
    echo -e "\e[1m[\e[0m\e[33mWARNING\e[0m\e[1m]\e[0m: $*" >&2
}

# Log an error message
cerror() {
    echo -e "\e[1m[\e[0m\e[31mERROR\e[0m\e[1m]\e[0m: $*" >&2
}

# Run a command and do not exit on failure
nonfatal() {
    "$@" || true
}

# Log an error message and exit
die() {
    cerror "$@"
    exit 1
}
