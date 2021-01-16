# backup-with-borg

A shell script and configuration to backup a GNU/Linux system using [borg-backup](https://www.borgbackup.org/).


## Installation

First ensure you have *borgbackup* installed (with a *Debian* distro) :
```sh
~> sudo apt install borgbackup
```

Clone this repo somewhere (lets say /usr/local/lib/backup-with-borg) :
```sh
~> git clone -q https://github.com/mbideau/backup-with-borg /tmp/backup-with-borg
~> sudo mv /tmp/backup-with-borg /usr/local/lib/backup-with-borg
```

Link the files to their final destinations :
```sh
~> sudo ln -s /usr/local/lib/backup-with-borg/backup_system.sh /usr/local/sbin/backup-system
~> sudo mkdir /etc/borg
~> sudo ln -s /usr/local/lib/backup-with-borg/default.conf /etc/borg/
~> sudo ln -s /usr/local/lib/backup-with-borg/root-fs.excludes /etc/borg/
~> sed "s|mypc|`hostname`|g" /usr/local/lib/backup-with-borg/example.conf | sudo tee /etc/borg/`hostname`.conf >/dev/null
```

Create a secret pass file :
```sh
~> tr -dc _A-Z-a-z-0-9 < /dev/urandom | head -c${1:-32} | sudo tee /etc/borg/root-fs.pass >/dev/null
```

Run it the first time :
```sh
~> backup-system --config /etc/borg/`hostname`.conf
```

Then add a *cron* or an *anacron* job. That's left for the user as an exercise.


## Usage

```
USAGE

    backup-system [-c|--config FILE] [-e|--excludes FILE] [-h|--help]


OPTIONS

    -c|--config FILE    Path to a file containing overridings of the default configuration.
    -e|--excludes FILE  Path to a file containing excludes (see 'borg help create' and 'borg help patterns').
    -h|--help           Display this help.


EXAMPLES

    # backuping the system with some default variables overriden
    $ backup-system --config /etc/borg/mypc.conf
```


## Authors

Written by: Michael Bideau


## Reporting bugs

Report bugs to: https://github.com/mbideau/backup-with-borg/issues


## Copyright

Copyright (C) 2016-2021 Michael Bideau.
License GPLv3+: [GNU GPL version 3 or later](https://gnu.org/licenses/gpl.html)
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
