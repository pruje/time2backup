#
# time2backup functions
#
# This file is part of time2backup (https://github.com/pruje/time2backup)
#
# MIT License
# Copyright (c) 2017 Jean Prunneaux
#

# Get common path of 2 paths
# e.g. get_common_path /home/user/my/first/path /home/user/my/second/path
# will return /home/user/my/
# Usage: get_common_path PATH_1 PATH_2
# Return: absolute path of the common directory
# Exit codes:
#   0: OK
#   1: usage error
#   2: error with paths
get_common_path() {

	# usage error
	if [ $# -lt 2 ] ; then
		return 1
	fi

	# get absolute paths
	local gcp_dir1="$(lb_abspath "$1")"
	if [ $? != 0 ] ; then
		return 2
	fi

	local gcp_dir2="$(lb_abspath "$2")"
	if [ $? != 0 ] ; then
		return 2
	fi

	# compare characters of paths one by one
	declare -i i=0
	while true ; do

		# if a character changes in the 2 paths,
		if [ "${gcp_dir1:0:$i}" != "${gcp_dir2:0:$i}" ] ; then

			local gcp_path="${gcp_dir1:0:$i}"

			# if it's a directory, return it
			if [ -d "$gcp_path" ] ; then

				if [ "${gcp_path:${#gcp_path}-1}" == "/" ] ; then
					# return path without the last /
					echo "${gcp_path:0:${#gcp_path}-1}"
				else
					echo "$gcp_path"
				fi
			else
				# if not, return parent directory
				dirname "$gcp_path"
			fi

			# quit function
			return 0
		fi
		i+=1
	done
}


# Get relative path to reach second path from a first one
# e.g. get_relative_path /home/user/my/first/path /home/user/my/second/path
# will return ../../second/path
# Usage: get_relative_path SOURCE_PATH DESTINATION_PATH
# Return: relative path
# Exit codes:
#   0: OK
#   1: usage error
#   2: error with paths
#   3: unknown cd error (may be access rights issue)
get_relative_path() {

	# usage error
	if [ $# -lt 2 ] ; then
		return 1
	fi

	# get absolute paths
	local grp_src="$(lb_abspath "$1")"
	if [ $? != 0 ] ; then
		return 2
	fi

	local grp_dest="$(lb_abspath "$2")"
	if [ $? != 0 ] ; then
		return 2
	fi

	# get common path
	local grp_common_path=$(get_common_path "$grp_src" "$grp_dest")
	if [ $? != 0 ] ; then
		return 2
	fi

	# go into the first path
	cd "$grp_src" 2> /dev/null
	if [ $? != 0 ] ; then
		return 3
	fi

	local grp_relative_path="./"

	# loop to find common path
	while [ "$(pwd)" != "$grp_common_path" ] ; do

		# go to upper directory
		cd .. 2> /dev/null
		if [ $? != 0 ] ; then
			return 3
		fi

		# append double dots to relative path
		grp_relative_path+="../"
	done

	# print relative path
	echo "$grp_relative_path/"
}


# Get backup type to check if a backup source is a file or a protocol like ssh, smb, ...
# Usage: get_backup_type SOURCE_URL
# Return: type of source (files/ssh)
get_backup_type() {

	backup_url="$*"
	protocol=$(echo "$backup_url" | cut -d: -f1)

	# get protocol
	case "$protocol" in
		ssh|fish)
			# double check protocol
			echo "$backup_url" | grep -E "^$protocol://" &> /dev/null
			if [ $? == 0 ] ; then
				# special case of fish = ssh
				if [ "$protocol" == "fish" ] ; then
					echo "ssh"
				else
					echo "$protocol"
				fi
				return 0
			fi
			;;
	esac

	# if not found or error of protocol, it is regular file
	echo "files"
}


# Get readable backup date
# Usage: get_backup_fulldate YYYY-MM-DD-HHMMSS
# Return: backup datetime (format YYYY-MM-DD HH:MM:SS)
# e.g. 2016-12-31-233059 -> 2016-12-31 23:30:59
get_backup_fulldate() {

	# test backup format (YYYY-MM-DD-HHMMSS)
	echo "$1" | grep -E "^[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]$" &> /dev/null

	# if not good format, return error
	if [ $? != 0 ] ; then
		return 1
	fi

	# return date at format YYYY-MM-DD HH:MM:SS
	echo ${1:0:10} ${1:11:2}:${1:13:2}:${1:15:2}
}


# Get backup history of a file
# Usage: get_backup_history [OPTIONS] PATH
# Options:
#   -a, --all  return all versions (including same)
# Exit codes:
#   0: OK
#   1: usage error
#   2: no backups found
#   3: cannot found backups (no absolute path, deleted parent directory)
get_backup_history() {

	file_history=()
	allversions=false

	# get options
	while true ; do
		case $1 in
			-a|--all)
				allversions=true
				shift
				;;
			*)
				break
				;;
		esac
	done

	# usage error
	if [ $# == 0 ] ; then
		return 1
	fi

	# get all backups
	backups=($(get_backups))
	if [ ${#backups[@]} == 0 ] ; then
		return 2
	fi

	# get path
	file="$*"
	abs_file="$(get_backup_path "$file")"
	if [ -z "$abs_file" ] ; then
		return 3
	fi

	# try to find backup
	last_inode=""
	for ((h=${#backups[@]}-1; h>=0; h--)) ; do
		backup_file="$backup_destination/${backups[$h]}/$abs_file"
		if [ -e "$backup_file" ] ; then
			if $allversions ; then
				file_history+=("${backups[$h]}")
				continue
			fi

			# if no hardlinks, do not test inodes
			if ! test_hardlinks ; then
				file_history+=("${backups[$h]}")
				continue
			fi

			# check inodes for version detection
			if [ "$(lb_detect_os)" == "macOS" ] ; then
				inode=$(stat -f %i "$backup_file")
			else
				inode=$(stat --format %i "$backup_file")
			fi
			if [ "$inode" != "$last_inode" ] ; then
				file_history+=("${backups[$h]}")
				last_inode=$inode
			fi
		fi
	done

	# return file versions
	if [ ${#file_history[@]} -gt 0 ] ; then
		for b in ${file_history[@]} ; do
			echo $b
		done
	else
		return 2
	fi

	return 0
}


# Create configuration files in user config
# Usage: create_config
# Exit codes: 0 if OK, 1 if cannot create config directory
create_config() {

	# create config directory
	# default: ~/.config/time2backup
	mkdir -p "$config_directory" &> /dev/null
	if [ $? != 0 ] ; then
		lb_error "Cannot create config directory. Please verify your access rights or home path."
		return 1
	fi

	# copy config samples from current directory
	cp -f "$script_directory/config/excludes.example.conf" "$config_directory/excludes.conf"
	cp -f "$script_directory/config/includes.example.conf" "$config_directory/includes.conf"
	cp -f "$script_directory/config/sources.example.conf" "$config_directory/sources.conf"
	cp -f "$script_directory/config/time2backup.example.conf" "$config_directory/time2backup.conf"
}


# Load configuration file
# Usage: load_config
# Exit codes:
#   0: OK
#   1: cannot open config
#   2: there are errors in config
load_config() {

	configok=true

	# load global config
	source "$config_file" > /dev/null
	if [ $? != 0 ] ; then
		lb_error "Config file does not exists!"
		return 1
	fi

	# get config version
	config_version="$(cat "$config_file" | grep "time2backup configuration file v" | grep -o [0-9].[0-9].[0-9])"
	if [ -n "$config_version" ] ; then
		lb_display_debug --log "Loading config version $config_version"
	else
		lb_display_warning --log "Cannot get config version."
	fi

	# test if destination is defined
	if [ -z "$destination" ] ; then
		lb_error "Destination is not set!"
		configok=false
	fi

	# test if sources file exists
	if ! [ -f "$config_sources" ] ; then
		lb_error "No sources file found!"
		configok=false
	fi

	# test integer values
	if ! lb_is_integer $keep_limit ; then
		lb_error "keep_limit must be an integer!"
		configok=false
	fi
	if ! lb_is_integer $clean_keep ; then
		lb_error "clean_keep must be an integer!"
		configok=false
	fi

	# correct bad values
	if [ $clean_keep -lt 0 ] ; then
		clean_keep=0
	fi

	if ! $configok ; then
		lb_error "\nThere are errors in your configuration."
		lb_error "Please edit your configuration with 'config' command or manually."
		return 2
	fi

	# set backup destination
	backup_destination="$destination/backups/$(hostname)/"
}


# Mount destination
# Usage: mount_destination
# Exit codes:
#   0: mount OK
#   1: mount error
#   2: disk not available
#   3: cannot create mount point
#   4: command not supported
#   5: no disk UUID set in config
mount_destination() {

	# if UUID not set, return error
	if [ -z "$backup_disk_uuid" ] ; then
		return 5
	fi

	lb_display --log "Mount disk..."

	# macOS is not supported
	# this is not supposed to happen because macOS always mount disks
	if [ "$(lb_detect_os)" == "macOS" ] ; then
		lb_display_error --log "macOS not supported yet"
		return 4
	fi

	# test if UUID exists (disk plugged)
	ls /dev/disk/by-uuid/ | grep "$backup_disk_uuid" &> /dev/null
	if [ $? != 0 ] ; then
		lb_display_error --log "Disk not available."
		return 2
	fi

	# create mountpoint
	if ! [ -d "$destination" ] ; then

		mkdir "$destination" 2>> "$logfile"

		# if failed, try in sudo mode
		if [ $? != 0 ] ; then
			lb_display_debug --log "...Failed! Try with sudo..."
			sudo mkdir "$destination" 2>> "$logfile"

			if [ $? != 0 ] ; then
				lb_display --log "...Failed!"
				return 3
			fi
		fi
	fi

	# mount disk
	mount "/dev/disk/by-uuid/$backup_disk_uuid" "$destination" 2>> "$logfile"

	# if failed, try in sudo mode
	if [ $? != 0 ] ; then
		lb_display_debug --log "...Failed! Try with sudo..."
		sudo mount "/dev/disk/by-uuid/$backup_disk_uuid" "$destination" 2>> "$logfile"

		if [ $? != 0 ] ; then
			lb_display --log "...Failed!"
			return 1
		fi
	fi

	return 0
}


# Unmount destination
# Usage: unmount_destination
# Exit codes:
#   0: OK
#   1: umount error
#   2: cannot delete mountpoint
unmount_destination() {

	lb_display --log "Unmount destination..."
	umount "$destination" &> /dev/null

	# if failed, try in sudo mode
	if [ $? != 0 ] ; then
		lb_display_debug --log "...Failed! Try with sudo..."
		sudo umount "$destination" &> /dev/null

		if [ $? != 0 ] ; then
			lb_display --log "...Failed!"
			return 1
		fi
	fi

	lb_display_debug --log "Delete mount point..."
	rmdir "$destination" &> /dev/null

	# if failed, try in sudo mode
	if [ $? != 0 ] ; then
		lb_display_debug --log "...Failed! Try with sudo..."
		sudo rmdir "$destination" &> /dev/null

		if [ $? != 0 ] ; then
			lb_display --log "...Failed!"
			return 2
		fi
	fi

	return 0
}


# Get path of a file backup
# Usage: get_backup_path PATH
# Return: backup path
get_backup_path() {

	# get file
	f="$*"

	# if absolute path (first character is a /)
	if [ "${f:0:1}" == "/" ] ; then
		# return file path
		echo "/files$f"
		return 0
	fi

	# if not absolute path, check protocols
	case $(get_backup_type "$f") in
		ssh)
			# transform ssh://user@hostname/path/to/file -> /ssh/user@hostname/path/to/file
			# how it works: split by colon to ssh/user@hostname/path/to/file,
			# with no loose of potential colons then delete the last colon
			echo "$f" | awk -F ':' '{printf $1 ; for(i=2;i<=NF;++i) printf $i ":"}' | sed 's/:$//'
			return 0
			;;
	esac

	# if file or directory

	# if not exists (file moved or deleted), try to get parent directory path
	if [ -e "$f" ] ; then
		echo -n "/files/$(lb_abspath "$f")"

		# if it is a directory, add '/' at the end of the path
		if [ -d "$f" ] ; then
			echo /
		fi
	else
		if [ -d "$(dirname "$f")" ] ; then
			echo "/files/$(lb_abspath "$f")"
		else
			# if not exists, I cannot guess original path
			lb_error "File does not exist."
			lb_error "If you want to restore a deleted file, please specify an absolute path."
			return 1
		fi
	fi

	return 0
}


# Test if backup destination support hard links
# Usage: test_hardlinks
# Exit codes:
#   0: destination supports hard links
#   1: cannot get filesystem type
#   2: destination does not support hard links
test_hardlinks() {

	# filesystems that does not support hard links
	# Details:
	#   vfat:    FAT32 on Linux systems
	#   msdos:   FAT32 on macOS systems
	#   fuseblk: NTFS/exFAT on Linux systems
	#   exfat:   exFAT on macOS systems
	#   vboxsf:  VirtualBox shared folder on Linux guests
	# Note: NTFS supports hard links, but exFAT does not.
	#       Therefore, both are identified on Linux as 'fuseblk' filesystems.
	#       So for safety usage, NTFS will be set with no hard links by default.
	#       Users can set config option force_hard_links=true in this case.
	no_hardlinks_fs=(vfat msdos fuseblk exfat vboxsf)

	# get destination filesystem
	dest_fstype="$(lb_df_fstype "$destination")"
	if [ -z "$dest_fstype" ] ; then
		return 1
	fi

	# if destination filesystem does not support hard links, return error
	if lb_array_contains "$dest_fstype" "${no_hardlinks_fs[@]}" ; then
		return 2
	fi

	return 0
}


# Get list of sources to backup
# Usage: get_sources
get_sources() {
	# reset variable
	sources=()

	# read sources.conf file line by line
	while read line ; do
		if ! lb_is_comment $line ; then
			sources+=("$line")
		fi
	done < "$config_sources"
}


# Get all backup dates list
# Usage: get_backups
get_backups() {
	echo $(ls "$backup_destination" | grep -E "^[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]$" 2> /dev/null)
}


# Clean old backups if limit is reached or if space is not available
# Usage: rotate_backups
rotate_backups() {

	local rotate_errors=0

	# get backups
	old_backups=($(get_backups))
	nbold=${#old_backups[@]}

	# avoid to delete current backup
	if [ $nbold -le 1 ] ; then
		lb_display_debug --log "Rotate backups: There is only one backup."
		return 0
	fi

	# if limit reached
	if [ $nbold -gt $keep_limit ] ; then
		lb_display --log "Cleaning old backups..."
		lb_display_debug "Clean to keep $keep_limit/$nbold"

		old_backups=(${old_backups[@]:0:$(($nbold - $keep_limit))})

		# remove backups from older to newer
		for ((r=0; r<${#old_backups[@]}; r++)) ; do
			lb_display_debug --log "Removing $backup_destination/${old_backups[$r]}..."

			rm -rf "$backup_destination/${old_backups[$r]}" 2> "$logfile"

			rm_result=$?
			if [ $rm_result == 0 ] ; then
				# delete log file
				lb_display_debug --log "Removing log file $backup_destination/logs/time2backup_${old_backups[$r]}.log..."
				rm -rf "$backup_destination/logs/time2backup_${old_backups[$r]}.log" 2> "$logfile"
			else
				lb_display_debug --log "... Failed (exit code: $rm_result)"
				rotate_errors=$rm_result
			fi
		done
	fi

	return $rotate_errors
}


# Print report of duration from start script to now
# Usage: report_duration
report_duration() {
	# calculate
	duration=$(($(date +%s) - $current_timestamp))

	echo "$tr_report_duration $(($duration/3600)):$(printf "%02d" $(($duration/60%60))):$(printf "%02d" $(($duration%60)))"
}


# Install configuration (planned tasks)
# Usage: install_config
install_config() {

	echo "Testing configuration..."

	# if config not ok, error
	if ! load_config ; then
		return 3
	fi

	# install cronjob
	if $recurrent ; then
		tmpcrontab="$config_directory/crontmp"
		crontask="* * * * *	\"$current_script\" backup --planned"

		echo "Install recurrent backup..."

		cmd_opt=""
		if [ -n "$user" ] ; then
			cmd_opt="-u $user"
		fi

		crontab -l $cmd_opt > "$tmpcrontab" 2>&1
		if [ $? != 0 ] ; then
			# special case for error when no crontab
			cat "$tmpcrontab" | grep "no crontab for " > /dev/null
			if [ $? == 0 ] ; then
				# reset crontab
				echo > "$tmpcrontab"
			else
				lb_display --log "Failed! \nPlease edit crontab manually and add the following line:"
				lb_display --log "$crontask"
				return 3
			fi
		fi

		cat "$tmpcrontab" | grep "$crontask" > /dev/null
		if [ $? != 0 ] ; then
			# append command to crontab
			echo -e "\n# time2backup recurrent backups\n$crontask" >> "$tmpcrontab"

			cmd_opt=""
			if [ -n "$user" ] ; then
				cmd_opt="-u $user"
			fi

			crontab $cmd_opt "$tmpcrontab"
			res=$?
		fi

		rm -f "$tmpcrontab" &> /dev/null

		return $res
	fi

	return 0
}


# Test if destination is reachable and mount it if needed
# Usage: prepare_destination
# Exit codes: 0: destination is ready, 1: destination not reachable
prepare_destination() {

	destok=false

	# test backup destination directory
	if [ -d "$destination" ] ; then
		destok=true
	else
		# if automount
		if $mount ; then
			# mount disk
			if mount_destination ; then
				destok=true
			fi
		fi
	fi

	# error message if destination not ready
	if ! $destok ; then
		lb_display --log "Backup destination is not reachable."
		lb_display --log "Verify if your media is plugged in and try again."
		return 1
	fi

	return 0
}


# Test backup command
# rsync simulation and get total size of the files to transfer
# Usage: test_backup
# Exit codes: 0: command OK, 1: error in command
test_backup() {

	# prepare rsync in test mode
	test_cmd=(rsync --dry-run --no-human-readable --stats)

	# append rsync options without the first argument (=rsync)
	test_cmd+=("${cmd[@]:1}")

	# rsync test
	# option dry-run makes a simulation for rsync
	# then we get the last line with the total amount of bytes to be copied
	# which is in format 999,999,999 so then we delete the commas
	lb_display_debug --log "Testing rsync in dry-run mode: ${test_cmd[@]}..."

	total_size=$("${test_cmd[@]}" 2>> "$logfile" | grep "Total transferred file size" | awk '{ print $5 }' | sed 's/,//g')

	# if rsync command not ok, error
	if ! lb_is_integer $total_size ; then
		lb_display_debug --log "rsync test failed."
		return 1
	fi

	lb_display_debug --log "Backup total size (in bytes): $total_size"

	# if there was an unknown error, continue
	if ! lb_is_integer $total_size ; then
		lb_display_debug --log "Error: '$total_size' is not a valid size in bytes. Continue..."
		return 1
	fi

	return 0
}


# Test space available on destination disk
# Usage: test_space
test_space() {
	# get space available
	space_available=$(lb_df_space_left "$destination")

	lb_display_debug --log "Space available on disk (in bytes): $space_available"

	# if there was an unknown error, continue
	if ! lb_is_integer $space_available ; then
		lb_display --log "Cannot get available space. Trying to backup although."
		return 0
	fi

	# if space is not enough, error
	if [ $space_available -lt $total_size ] ; then
		lb_display --log "Not enough space on device!"
		lb_display_debug --log "Needed (in bytes): $total_size/$space_available"
		return 1
	fi

	return 0
}


# Delete empty directories recursively
# Usage: clean_empty_directories PATH
clean_empty_directories() {

	# usage error
	if [ $# == 0 ] ; then
		return 1
	fi

	# get directory path
	d="$*"

	# delete empty directories recursively
	while true ; do
		# if is not a directory, error
		if ! [ -d "$d" ] ; then
			return 1
		fi

		# security check
		if [ "$d" == "/" ] ; then
			return 2
		fi

		# security check: do not delete destination path
		if [ "$(dirname "$d")" == "$(dirname "$destination")" ] ; then
			return 0
		fi

		# if directory is empty,
		if lb_dir_is_empty "$d" ; then

			lb_display_debug "Deleting empty backup: $d"

			# delete directory
			rmdir "$d" &> /dev/null
			if [ $? == 0 ] ; then
				# go to parent directory and continue loop
				d="$(dirname "$d")"
				continue
			fi
		fi

		# if not empty, quit loop
		return 0
	done

	return 0
}


# Edit configuration
# Usage: edit_config [OPTIONS] CONFIG_FILE
# Options:
#   -e, --editor COMMAND  set editor
#   --set "param=value"   set a config parameter in headless mode (no editor)
# Exit codes:
#   0: OK
#   1: usage error
#   2: failed to open/save configuration
#   3: no editor found to open configuration file
edit_config() {

	# default values
	editors=(nano vim vi)
	custom_editor=false
	set_config=""

	# get options
	while true ; do
		case "$1" in
			-e|--editor)
				if lb_test_arguments -eq 0 $2 ; then
					return 1
				fi
				editors=("$2")
				custom_editor=true
				shift 2
				;;
			--set)
				if lb_test_arguments -eq 0 $2 ; then
					return 1
				fi
				set_config="$2"
				shift 2
				;;
			*)
				break
				;;
		esac
	done

	# test config file
	if lb_test_arguments -eq 0 $* ; then
		return 1
	fi

	edit_file="$*"

	# test file
	if [ -e "$edit_file" ] ; then
		# if exists but is not a file, return error
		if ! [ -f "$edit_file" ] ; then
			return 1
		fi
	else
		# create empty file if it does not exists (should be includes.conf)
		echo -e "\n" > "$edit_file"
	fi

	# headless mode
	if [ -n "$set_config" ] ; then

		# get parameter + value
		conf_param="$(echo "$set_config" | cut -d= -f1)"
		conf_value="$(echo "$set_config" | sed 's/\//\\\//g')"

		# get config line
		config_line=$(cat "$edit_file" | grep -n "^[# ]*$conf_param=" | cut -d: -f1)

		# if found, change line
		if [ -n "$config_line" ] ; then
			sed -i'~' "${config_line}s/.*/$conf_value/" "$edit_file"
		else
			# if not found, append to file

			# test type of value
			if ! lb_is_number $set_config ; then
				case $set_config in
					true|false)
						# do nothing
						:
						;;
					*)
						# append quotes
						set_config="\"$set_config\""
						;;
				esac
			fi

			# append config to file
			echo "$conf_param=$set_config" >> "$edit_file"
		fi
	else
		# config editor mode
		all_editors=()

		# if no custom editor,
		if ! $custom_editor ; then

			# open file with graphical editor
			if ! $consolemode ; then
				if [ "$(lbg_get_gui)" != "console" ] ; then
					if [ "$(lb_detect_os)" == "macOS" ] ; then
						all_editors+=(open)
					else
						all_editors+=(xdg-open)
					fi
				fi
			fi

			# add console editors
			all_editors+=("${editors[@]}")
		fi

		# select a console editor
		for e in ${all_editors[@]} ; do
			if [ -n "$editor" ] ; then
				break
			fi
			# test if editor exists
			if lb_command_exists "$e" ; then
				editor="$e"
				break
			fi
		done

		if [ -n "$editor" ] ; then
			"$editor" "$edit_file" 2> /dev/null
			wait $!
		else
			if $custom_editor ; then
				lb_error "Editor '$editors' was not found on this system."
			else
				lb_error "No editor was found on this system."
				lb_error "Please edit $edit_file manually."
			fi

			return 3
		fi
	fi

	if [ $? != 0 ] ; then
		lb_error "Failed to open/save configuration."
		lb_error "Please edit $edit_file manually."
		return 2
	fi

	return 0
}


# Exit on cancel
# Usage: cancel_exit
cancel_exit() {

	lb_display --log
	lb_display_info --log "Cancelled. Exiting..."

	# display notification
	if $notifications ; then
		if [ "$mode" == "backup" ] ; then
			lbg_notify "$(printf "$tr_backup_cancelled_at" $(date +%H:%M:%S))\n$(report_duration)"
		else
			lbg_notify "$tr_restore_cancelled"
		fi
	fi

	# backup mode
	if [ "$mode" == "backup" ] ; then
		# exit with cancel code without shutdown
		clean_exit --no-shutdown 11
	else
		# restore mode
		exit 8
	fi
}


# Delete backup lock
# Usage: remove_lock
# Exit code: 0: OK, 1: could not delete lock
release_lock() {

	lb_display_debug "Deleting lock..."

	rm -f "$backup_lock" &> /dev/null
	if [ $? != 0 ] ; then
		lbg_display_critical --log "$tr_error_unlock"
		return 1
	fi

	return 0
}


# Clean things before exit
# Usage: clean_exit [OPTIONS] [EXIT_CODE]
# Options:
#   --no-unmount   Do not unmount
#   --no-email     Do not send email report
#   --no-rmlog     Do not delete logfile
#   --no-shutdown  Do not halt PC
clean_exit() {

	# get options
	while true ; do
		case "$1" in
			--no-unmount)
				if ! $force_unmount ; then
					unmount=false
				fi
				shift
				;;
			--no-email)
				email_report=false
				email_report_if_error=false
				shift
				;;
			--no-rmlog)
				logs_save=true
				shift
				;;
			--no-shutdown)
				if ! $force_shutdown ; then
					shutdown=false
				fi
				shift
				;;
			*)
				break
				;;
		esac
	done

	# set exit code if specified
	if [ -n "$1" ] ; then
		lb_exitcode=$1
	fi

	lb_display_debug --log "Clean exit."

	# delete backup lock
	release_lock

	# unmount destination
	if $unmount ; then
		if ! unmount_destination ; then
			lbg_display_error --log "$tr_error_unmount"
		fi
	fi

	if $email_report ; then
		email_report_if_error=true
	fi

	# send email report
	if $email_report_if_error ; then

		# if email recipient is set
		if [ -n "$email_recipient" ] ; then

			# if report or error, send email
			if $email_report || [ $lb_exitcode != 0 ] ; then

				# email options
				email_opts=()
				if [ -n "$email_sender" ] ; then
					email_opts+=(--sender "$email_sender")
				fi

				# prepare email content
				email_subject="time2backup - "
				email_content="Dear user,\n\n"

				if [ $lb_exitcode == 0 ] ; then
					email_subject+="Backup succeeded on $(hostname)"
					email_content+="A backup succeeded on $(hostname)."
				else
					email_subject+="Backup failed on $(hostname)"
					email_content+="A backup failed on $(hostname) (exit code: $lb_exitcode)"
				fi

				email_content+="\n\nBackup started on $current_date\n$(report_duration)\n\n"

				# error report
				if [ $lb_exitcode != 0 ] ; then
					email_content+="User: $user\n$report_details\n\n"
				fi

				# if logs are kept,
				email_logs=false
				if $logs_save ; then
					email_logs=true
				else
					if $keep_logs_if_error && [ $lb_exitcode != 0 ] ; then
						email_logs=true
					fi
				fi

				if $email_logs ; then
					email_content+="See the log file for more details.\n\n"
				fi

				email_content+="Regards,\ntime2backup"

				# send email
				if ! lb_email "${email_opts[@]}"-s "$email_subject" "$email_recipient" "$email_report_content" ; then
					lb_log_error "Email could not be sent."
				fi
			fi
		else
			# email not sent
			lb_log_error "Email recipient not set, do not send email report."
		fi
	fi

	# delete log file
	if ! $logs_save ; then

		delete_logs=false

		if [ $lb_exitcode == 0 ] ; then
			delete_logs=true
		else
			if ! $keep_logs_if_error ; then
				delete_logs=true
			fi
		fi

		if $delete_logs ; then
			lb_display_debug "Deleting log file..."

			# delete file
			rm -f "$logfile" &> /dev/null

			# if failed
			if [ $? != 0 ] ; then
				lb_display_debug "...Failed!"
			fi

			# delete logs directory if empty
			if lb_dir_is_empty "$logs_directory" ; then
				lb_display_debug "Deleting log directory..."

				rmdir "$logs_directory" &> /dev/null

				# if failed
				if [ $? != 0 ] ; then
					lb_display_debug "...Failed!"
				fi
			fi
		fi
	fi

	# if shutdown after backup, execute it
	if $shutdown ; then
		haltpc
	fi

	if $debugmode ; then
		echo
		lb_display_debug "Exited with code: $lb_exitcode"
	fi

	lb_exit
}


# Halt PC in 10 seconds
# Usage: haltpc
haltpc() {

	# clear all traps to allow user to cancel countdown
	trap - 1 2 3 15
	trap

	# test shutdown command
	if ! lb_command_exists "${shutdown_cmd[0]}" ; then
		lb_display_error --log "No shutdown command found. PC will not halt."
		return 1
	fi

	# countdown before halt
	lb_print "\nYour computer will halt in 10 seconds. Press Ctrl-C to cancel."
	for ((i=10; i>=0; i--)) ; do
		echo -n "$i "
		sleep 1
	done

	# shutdown
	"${shutdown_cmd[@]}"
	if [ $? != 0 ] ; then
		lb_display_error --log "Error with shutdown command. PC is still up."
		return 1
	fi
}