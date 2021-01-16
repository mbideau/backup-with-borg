#!/bin/sh
#
# Backup the system in a borg repository
#
# Standards in this script:
#   POSIX compliance:
#      - http://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html
#      - https://www.gnu.org/software/autoconf/manual/autoconf.html#Portable-Shell
#   CLI standards (no --version though):
#      - https://www.gnu.org/prep/standards/standards.html#Command_002dLine-Interfaces
#
# Source code, documentation and support:
#   https://github.com/mbideau/backup-with-borg
#
# Copyright (C) 2016-2021 Michael Bideau [France]
#
# This file is part of backup-with-borg.
#
# backup-with-borg is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# backup-with-borg is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with backup-with-borg. If not, see <https://www.gnu.org/licenses/>.
#

# shellcheck disable=SC2006,SC2166

# halt on first error
set -e

#<constants>
DEFAULT_BORG_CONFIG_FILE=/etc/borg/default.conf
IFS_BAK="$IFS"

#<package infos>
VERSION=0.1.0
PROGRAM_NAME="backup-system"
AUTHOR='Michael Bideau'
HOME_PAGE='https://github.com/mbideau/backup-with-borg'
REPORT_BUGS_TO="$HOME_PAGE/issues"


#<helpers>
usage()
{
	cat <<ENDCAT

USAGE

    $PROGRAM_NAME [-c|--config FILE] [-e|--excludes FILE] [-h|--help]


OPTIONS

    -c|--config FILE    Path to a file containing overridings of the default configuration.
    -e|--excludes FILE  Path to a file containing excludes (see 'borg help create' and 'borg help patterns').
    -h|--help           Display this help.


EXAMPLES

    # backuping the system with some default variables overriden
    \$ backup-system --config /etc/borg/mypc.conf


AUTHORS

    Written by: $AUTHOR


REPORTING BUGS

    Report bugs to: <$REPORT_BUGS_TO>


COPYRIGHT

    $PROGRAM_NAME $VERSION
    Copyright (C) 2016-`date "+%Y"||true` $AUTHOR.
    License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>
    This is free software: you are free to change and redistribute it.
    There is NO WARRANTY, to the extent permitted by law.


SEE ALSO

    Home page: <$HOME_PAGE>

ENDCAT
}

debug()
{
	if [ "$DEBUG" = 'true' ]; then
		echo "[`date '+%F %T'`]  DEBUG  $1" >&2
	fi
}

info()
{
	echo "[`date '+%F %T'`]   INFO  $1" >&2
	[ "$ZENITY_INFO_MESSAGE" != 'true' ] || echo "# $1"
}

warning()
{
	echo "[`date '+%F %T'`] WARNING $1" >&2
}

error()
{
	echo "[`date '+%F %T'`]  ERROR  $1" >&2
}

fatal_error()
{
	error "$1"
	exit 4
}

mail_msg()
{
	if [ "$MAIL_BIN" != '' ]; then
		# shellcheck disable=SC2086
		echo "$2"|"$MAIL_BIN" -s "$1" $MAILTO
	fi
}


#<arguments>
# check for enhanced 'getopt'
set +e
getopt --test > /dev/null
return=$?
set -e
[ $return -eq 4 ] || fatal_error "Unable to parse arguments/options because of missing enhanced getopt"
# define short options
SHORT=hc:e:z
# define long options
LONG=help,config:,excludes:
# parse them
PARSED=`getopt --options $SHORT --longoptions $LONG --name "$0" -- "$@"` || exit 3
# process them
eval set -- "$PARSED"
while true; do
	case $1 in
		-c|--config)   OPT_CONFIG_FILE="$2"; shift 2;;
		-e|--excludes) OPT_EXCLUDES_FILE="$2"; shift 2;;
		-h|--help)     usage; exit 0;;
		--)            shift; break ;;
		*)             fatal_error "Programming error"
	esac
done


#<checks #1>
[ -e "$OPT_CONFIG_FILE" ] || fatal_error "Configuration file '$OPT_CONFIG_FILE' doesn't exist"
[ -e "$OPT_EXCLUDES_FILE" ] || fatal_error "Excludes file '$OPT_EXCLUDES_FILE' doesn't exist"


#<configuration>
debug "Sourcing optional configuration file '$OPT_CONFIG_FILE'"
# shellcheck disable=SC1090
. "$OPT_CONFIG_FILE"
debug "Sourcing default borg configuration file '$DEFAULT_BORG_CONFIG_FILE'"
# shellcheck disable=SC1090
. "$DEFAULT_BORG_CONFIG_FILE"


#<checks #2>
[ "$BORG_BIN" != '' -a -x "$BORG_BIN" ] || fatal_error "Borg binary '$BORG_BIN' doesn't exist or is not executable"
[ "$MAIL_BIN" = '' -o -x "$MAIL_BIN" ] || fatal_error "Mail binary '$MAIL_BIN' doesn't exist or is not executable"
[ -e "$ROOT_EXCLUDE_FILE" ] || fatal_error "Exclude file '$ROOT_EXCLUDE_FILE' doesn't exist"
[ -e "$PASSPHRASE_FILE" ] || fatal_error "Passphrase file '$PASSPHRASE_FILE' doesn't exist"


#<vars>
PASSPHRASE="`head -n 1 "$PASSPHRASE_FILE"`"
[ "$PASSPHRASE" != '' ] || fatal_error "Empty borg passphrase. Passphrase file '$PASSPHRASE_FILE' may be empty"


#<process>
# set nice class to Idle (for this script)
debug "Setting nice class to 'Idle'"
ionice -c 3 --pid $$
# set real-time scheduling to Idle
debug "Setting real-time scheduling to 'Idle'"
chrt -i -p 0 $$


#<env>
BORG_DISPLAY_PASSPHRASE=n
BORG_REPO="$REPO_DIR"
BORG_KEYS_DIR="$KEYS_DIR"
BORG_CACHE_DIR="$CACHE_DIR"
TMPDIR="$TEMP_DIR"
export BORG_DISPLAY_PASSPHRASE
export BORG_REPO
export BORG_KEYS_DIR
export BORG_CACHE_DIR
export TMPDIR


#<functions>
# create the missing directories for the backup
setup_dirs()
{
	debug "Setting up directories ..."
	lock_file_dir=`dirname "$LOCK_FILE"`
	IFS="
"
	for d in \
		"$BACKUP_DIR"		\
		"$REPO_DIR"		\
		"$KEYS_DIR"		\
		"$CACHE_DIR"		\
		"$TEMP_DIR"		\
		"$LOGS_DIR"		\
		"$BIN_DIR"		\
		"$KEYS_BACKUP_DIR"	\
		"$lock_file_dir"
	do
		IFS=$IFS_BAK
		if [ ! -d "$d" ]; then
			mkdir -m "$DIR_MODE" -p "$d"
			chown "$BACKUP_OWNER:$BACKUP_GROUP" "$d"
			chmod g+s "$d"
			debug "\tcreated dir '$d'"
		fi
		IFS="
"
	done
	IFS=$IFS_BAK
}

setup_logs()
{
	debug "Setting up logs ..."
	IFS="
"
	for l in \
		"$INIT_OUTPUT_FILE"	\
		"$ROOT_OUTPUT_FILE"	\
		"$CHECK_OUTPUT_FILE"	\
		"$ROOT_LAST_BACKUP_LOG"
	do
		IFS=$IFS_BAK
		if [ ! -e "$l" ]; then
			debug "\tcreating log '$l'"
			touch "$l"
		fi
		debug "\tchmoding $LOG_FILE_MODE log '$l'"
		chmod "$LOG_FILE_MODE" "$l"
		IFS="
"
	done
	IFS=$IFS_BAK
}

cleanup_borg_locks()
{
	debug "Cleaning up borg locks ..."
	debug "\t'$LOCK_REPO_ROSTER'"
	rm -f "$LOCK_REPO_ROSTER"
	debug "\t'$LOCK_REPO_EXCLUSIVE'"
	rm -fr "$LOCK_REPO_EXCLUSIVE"
	debug "Cleaned borg locks"
}

# initialize the borg repository
init_repository()
{
	info "Initializing borg repository ..."
	if ! BORG_PASSPHRASE="$PASSPHRASE" "$BORG_BIN" init \
		-v  				\
		--umask "$UMASK"		\
		--encryption keyfile		\
		"$REPO_DIR"			\
		> "$INIT_OUTPUT_FILE" 2>&1
	then
		error "Failed to initialize the repository. See log '$INIT_OUTPUT_FILE'"
		return 1
	else
		if [ "$APPEND_ONLY" = 'true' ]; then
			sed 's/^append_only = 0$/append_only = 1/' -i "$REPO_DIR/config"
			debug "Enforced append-only mode"
		fi
		info "Initialized repository '$REPO_DIR'"
	fi
}

# create a new archive in the borg repository
create_new_archive()
{
	info "Creating a new borg archive ..."
	# TODO check the space left before (preserve 1G at least)

	# check for a dry run
	dry="$1"
	if [ "$dry" != "" -a "$dry" != "--dry-run" ]; then
		error "Invalid parameter value for 'create_new_archive()'"
		return 1
	fi

	# output file and format
	output_file="$ROOT_OUTPUT_FILE"
	filter="--filter=AME"

	# temp file for output if dry run
	if [ "$dry" = "--dry-run" ]; then
		output_file="`mktemp`"
		info "[dry-run] output to '$output_file'"
		filter=
	fi

	# merge the configuration file with the one provided in the option
	excludes_file_tmp="$ROOT_EXCLUDE_FILE"
	if [ "$OPT_EXCLUDES_FILE" != '' ]; then
		excludes_file_tmp="`mktemp`"
		cat -s "$ROOT_EXCLUDE_FILE" "$OPT_EXCLUDES_FILE" > "$excludes_file_tmp"
		debug "Merged excludes files '$ROOT_EXCLUDE_FILE' and '$OPT_EXCLUDES_FILE' to '$excludes_file_tmp'"
	fi

	# create the archive
	if ! BORG_PASSPHRASE="$PASSPHRASE" "$BORG_BIN" create \
		$dry					\
		-v --stats --list $filter		\
		--umask "$UMASK"			\
		--numeric-owner 			\
		--compression "$COMPRESSION" 		\
		--exclude-from "$excludes_file_tmp"	\
		--exclude-caches 			\
		--keep-exclude-tags 			\
		::"$ROOT_ARCHIVE_NAME"			\
		/					\
		> "$output_file" 2>&1

	# error
	then
		error "Failed to create the archive '$ROOT_ARCHIVE_NAME'"
		error "Output file is located at '$output_file'"
		mail_msg "$AIL_MESSAGE_CREATION_FAILED_SUBJECT" \
			"$MAIL_MESSAGE_CREATION_FAILED_BODY\n\n---\n`cat "$output_file"`"
		rm -f "$excludes_file_tmp"
		return 1

	# dry run
	elif [ "$dry" = "--dry-run" ]; then
		info "Archive creation simulated (dry-run), see output at '$output_file'"

	# success
	else
		info "Archive created to '$ROOT_ARCHIVE_NAME'"
	fi

	# cleanup
	rm -f "$excludes_file_tmp"
}

get_last_backup_date_from_log()
{
	tail -n 1 "$ROOT_LAST_BACKUP_LOG"
}

is_already_a_backup_for_today()
{
	BORG_PASSPHRASE="$PASSPHRASE" "$BORG_BIN" list ::"$ROOT_ARCHIVE_NAME" >/dev/null 2>&1
}

remove_today_archive_from_repo()
{
	info "Removing today archive from the borg repository"
	cleanup_borg_locks
	output_file="$ROOT_OUTPUT_FILE"
	if ! BORG_PASSPHRASE="$PASSPHRASE" "$BORG_BIN" delete ::"$ROOT_ARCHIVE_NAME" > "$output_file" 2>&1; then
		error "Failed to remove the archive '$ROOT_ARCHIVE_NAME' from the repo"
		error "Output file is located at '$output_file'"
		echo "La création de l'archive a échoué.\nCi-dessous le log.\n\n---\n`cat "$output_file"`" \
		|mail -s "Borg - échec de la sauvegarde root-fs" $MAILTO
		return 1
	else
		info "Archive '::$ROOT_ARCHIVE_NAME' removed from the repo"
	fi
}

check_repository()
{
	info "Checking the borg repository integrity ..."
	output_file="$CHECK_OUTPUT_FILE"
	if ! BORG_PASSPHRASE="$PASSPHRASE" "$BORG_BIN" check :: > "$output_file" 2>&1; then
		error "Failed to check repository"
		error "Output file is located at '$output_file'"
		mail_msg "$MAIL_MESSAGE_CHECK_FAILED_SUBJECT" \
			"$MAIL_MESSAGE_CHECK_FAILED_BODY\n\n---\n`cat $output_file`"
		return 1
	else
		info "Repository checked and is OK"
	fi
}

copy_bin()
{
	info "Copying borg binary ..."
	bin_name="borg-`"$BORG_BIN" --version|awk '{print $2}'`_`uname -s`_`uname -m`"
	bin_path="$BIN_DIR/$bin_name"
	if [ ! -e "$bin_path" ]; then
		cp -a "`readlink -f "$BORG_BIN"`" "$bin_path"
		info "Copied borg binary to '$bin_path'"
		# TODO copy the rest of the dependencies/libraries (see 'ldd')
	fi
}

copy_keys()
{
	info "Copying borg keys ..."
	if [ ! -e "$KEYS_BACKUP_DIR" ]; then
		mkdir "$KEYS_BACKUP_DIR"
	fi
	cp -a "$KEYS_DIR"/* "$KEYS_BACKUP_DIR"/
	info "Copied borg keys to '$KEYS_BACKUP_DIR'"
}

# remove old backup archives from the repository
prune()
{
	ret=0

	info "Pruning borg old archives ..."

	# check for dry run
	dry="$1"
	if [ "$dry" != '' -a "$dry" != '--dry-run' ]; then
		error "Invalid parameter value for 'prune($1)'"
		return 1
	fi

	# output file
	output_file="$ROOT_OUTPUT_FILE"

	# flag if append-only mode was disabled for this operation
	append_only_disabled=false

	# create temp output file for the dry-run
	if [ "$dry" = "--dry-run" ]; then
		output_file=`mktemp`
		info "[dry-run] output to '$output_file'"

	# not a dry-run
	else

		# disable append-only mode to be able to write to the repo, else nothing is gonna be pruned
		if [ "$APPEND_ONLY" = 'true' ]; then
			sed 's/^append_only = 1$/append_only = 0/' -i "$REPO_DIR/config"
			debug "Disabled append-only mode temporarily"
			append_only_disabled=true
		fi
	fi

	# prune old archives
	if ! BORG_PASSPHRASE="$PASSPHRASE" "$BORG_BIN" prune \
		$dry				 	\
		-v --list --stats		 	\
		--umask "$UMASK"		 	\
		--keep-within="${RETENTION_DAYS}d" 	\
		--keep-weekly="$RETENTION_WEEKS" 	\
		--keep-monthly="$RETENTION_MONTHS" 	\
		--keep-yearly="$RETENTION_YEARS" 	\
		--prefix="$ROOT_ARCHIVE_PREFIX"	 	\
		>> "$output_file" 2>&1

	# error
	then
		error "Failed to prune archives"
		error "Output file is located at '$output_file'"
		mail_msg "$MAIL_MESSAGE_PRUNE_FAILED_SUBJECT" \
			"$MAIL_MESSAGE_PRUNE_FAILED_BODY\n\n---\n`cat $output_file`"
		ret=1

	# dry-run
	elif [ "$dry" = "--dry-run" ]; then
		info "Archive pruning simulated (dry-run), see output at '$output_file'"

	# success
	else
		info "Archives pruned successfully"
	fi

	# restore append-only mode
	if [ "$append_only_disabled" = 'true' ]; then
		sed 's/^append_only = 0$/append_only = 1/' -i "$REPO_DIR/config"
		debug "Restored append-only mode"
	fi
	return $ret
}


# always
setup_dirs
setup_logs

# the first time
if [ ! -d "$REPO_DIR"/data ]; then
	init_repository
fi

# other times
if [ -f "$LOCK_FILE" ]; then
	error "Another borg backup script is running (`head -n 1 "$LOCK_FILE"`). Aborting."
	error "Please wait ... or manually remove the lockfile '$LOCK_FILE'"
	exit 1
# elif is_already_a_backup_for_today; then
# 	last_backup_date_from_log="`get_last_backup_date_from_log`"
# 	if [ "$last_backup_date_from_log" != "$BACKUP_DATE" ]
# 	then
# 		warning "It appears that there is already a backup for today but the last backup date from the log doesn't match ()"
# 		warning "It may be an interupted backup (corrupted)"
# 		remove_it=$AUTO_REMOVE_INTERRUPTED_BACKUP
# 		while ! echo "$remove_it"|grep -q '^[YyNn]$'; do
# 			warning "Do you want to remove this backup, then make a new one (Y/n) : "
# 			read remove_it
# 		done
# 		if [ "$remove_it" = 'Y' -o "$remove_it" = 'y' ]; then
# 			remove_today_archive_from_repo
# 		else
# 			exit 0
# 		fi
# 	else
# 		info "There is already a backup for today"
# 		exit 2
# 	fi
else
	echo "PID $$, started at `date`" > "$LOCK_FILE"
	debug "Lock acquired"
	create_new_archive
	copy_keys
	copy_bin
	prune
	check_repository
	rm -f "$LOCK_FILE"
	debug "Lock released"
	debug "Loging backup date"
	echo "$BACKUP_DATE" >> "$ROOT_LAST_BACKUP_LOG"
fi

