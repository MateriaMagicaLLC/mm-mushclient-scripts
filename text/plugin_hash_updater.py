#!/usr/bin/env python3

import hashlib
import re
from functools import partial

# this script will regenerate the plugin hashes for all the plugins.  the list of plugins is derived from the
# PLUGINS_ID_TO_NAME_PATH file.  if you add an entirely new plugin, you will need to add the entry manually to
# the PLUGINS_VERSIONS_TXT_PATH, as this script only replaces existing hashes in the file, it doesn't actually
# generate the file.
#
# usage:
#   python3 plugin_hash_updater.py > out
#   mv out plugins_versions.txt
#
# NOTE: don't try and redirect the output directly to plugins_versions.txt or it will zero out the file!

# relative path from where we execute this script to where the plugins are located.
# needs trailing slash.
PLUGINS_PATH = "../src/"
PLUGINS_VERSIONS_TXT_PATH = "plugins_versions.txt"
PLUGINS_ID_TO_NAME_PATH = "plugins_id_to_name.txt"

plugins = {}

def read_plugins_info(path):
    with open(path, "r") as f:
        for line in f:
            id, name = line.split()

            plugins[id] = {}
            plugins[id]["name"] = name
            plugins[id]["md5"] = md5sum(PLUGINS_PATH + name).upper()

def md5sum(path):
    with open(path, mode="rb") as f:
        d = hashlib.md5()
        for buf in iter(partial(f.read, 128), b''):
            d.update(buf)

    return d.hexdigest()

def parse_plugins_dot_txt(path):
    with open(path, "r") as f:
        for line in f:
            id = hash = name = rest = None

            match = re.search(r'id\s*=\s*(\w+)', line)
            if match:
                id = match.group(1)

            match = re.search(r'hash\s*=\s*(\w+)\s', line)
            if match:
                hash = match.group(1)

            match = re.search(r'hash\s*=\s*(\w+)\s(.+)', line)
            if match:
                hash = match.group(1)
                rest = match.group(2)

            match = re.search(r'name\s*=\s*([\w.]+)', line)
            if match:
                name = match.group(1)

            if id and hash and rest:
                print("id = {}  hash = {} {}".format(id, plugins[id]["md5"], rest))
                continue

            if id and hash:
                print("id = {}  hash = {}".format(id, plugins[id]["md5"]))
                continue

            if name and hash:
                print("name = {}  hash = {}".format(name, hash))
                continue

if __name__ == "__main__":
    read_plugins_info(PLUGINS_ID_TO_NAME_PATH)
    parse_plugins_dot_txt(PLUGINS_VERSIONS_TXT_PATH)
