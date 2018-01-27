#
# time2backup init variables and configuration default values
#
# This file is part of time2backup (https://time2backup.org)
#
# MIT License
# Copyright (c) 2017-2018 Jean Prunneaux
#

###########################
#  VARIABLES DECLARATION  #
###########################

debug_mode=false
new_config=false
custom_config=false
sources=()
mounted=false
rsync_cmd=()
success=()
warnings=()
errors=()
default_verbose_level=INFO
default_log_level=INFO
force_unmount=false
quiet_mode=false
remote_destination=false
backup_date_format="[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]"
mirror_mode=false


#########################
#  DEFAULT CORE CONFIG  #
#########################

cmd_alias=/usr/bin/time2backup
default_rsync_path=rsync
disable_custom_commands=false

if [ "$lb_current_os" == Windows ] ; then
  enable_recurrent=false
  default_shutdown_cmd=(shutdown /s)
  preserve_permissions=false
else
  enable_recurrent=true
  default_shutdown_cmd=(shutdown -h now)
  preserve_permissions=true
fi


####################
#  DEFAULT CONFIG  #
####################

destination_subdirectories=true
test_destination=true

keep_limit=-1
clean_old_backups=true
clean_keep=0

recurrent=false
frequency=daily

mount=true
exec_before_block=false

unmount=false
unmount_auto=true
shutdown=false
exec_after_block=false

keep_logs=on_error
log_level=$default_log_level

notifications=true
email_report=none

files_progress=false
console_mode=false

network_compression=false

server_sudo=false

hard_links=true
force_hard_links=false
verbose_level=$default_verbose_level

resume_cancelled=true
resume_failed=false
