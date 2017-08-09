# General Linux CLI utilities, defaults and helper functions

Installation:

    git clone --depth 1 https://github.com/dagelf/utils
    utils/install.sh

Notes:

This repository is me sharing all my helper functions, defaults and utilities in one place, and also me finding my feet with a comfortable sharing workflow. Some utilities are curated, some created, some vetted, some not. I have yet to work out a way to tag- and keep them up to date. Some are made redundant by upgrades to the tools they manage... maybe someday all of them will... until then, this is my band-aid. Contributions welcome. 

# Scripts

## dockertags  
*List all tags for a Docker image on docker hub.*


List all tags for *ubuntu*:
 
    dockertags ubuntu

List all *php* tags containing *apache*:
 
    dockertags php apache

List all *mariadb* tags in one line:
 
    echo `dockertags mariadb`

>dependencies: *wget, awk*  
*source:* [stackoverflow: How do you list all tags for a Docker image on a remote registry?](https://stackoverflow.com/questions/28320134/how-to-list-all-tags-for-a-docker-image-on-a-remote-registry)

## github-*
*Github helper utilities*

Changes current git repo source url from ssh to https

    github-tohttps

Changes current git repo source url from https to ssh

    github-tossh

dependency: *git*  
*source:* [icyflame gist](https://gist.github.com/icyflame/532edee5422baeabac56d111f642bd73)

# Defaults

coming soon(TM): ssh_config, .screenrc
