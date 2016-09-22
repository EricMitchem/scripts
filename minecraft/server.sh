#!/bin/bash
# Minecraft server script

# tmux Settings
tmuxSession="minecraft"
tmuxWindow="mcwindow"
tmuxSend="tmux send -t ${tmuxWindow}.0 "
	  
# Ram Disk Settings
RamDiskMntPath="/mnt/minecraft"
RamDiskSizeMB=1024

# Minecraft Settings
McPath="/home/eric/.minecraft"
McWorldSavePath="$McPath/world.save"
ForgeJar="$McPath/forge-1.10.2-12.18.1.2011-universal.jar"
ForgeOpts="nogui"

# Java Settings
JavaHeapSizeMB=2048
JavaHeapMaxSizeMB=2048
JavaHeapNurserySizeMB=512
JavaHeapPolicy="-XX:-UseAdaptiveSizePolicy"
JavaGC="-XX:+UseConcMarkSweepGC"
JavaOpts="\
	-Xms${JavaHeapSizeMB}M \
	-Xmx${JavaHeapMaxSizeMB}M \
	-Xmn${JavaHeapNurserySizeMB}M \
	$JavaHeapPolicy \
	$JavaGC"
	
# Crontab Settings
CronCmd="$McPath/server.sh save"
CronJob="*/10 * * * * $CronCmd"

start_tmux_session()
{
	tmux has -t $tmuxSession > /dev/null 2>&1
	
	if [ $? -eq 0 ]; then
		tmux kill-session -t $tmuxSession
	fi
	
	tmux new -d -s $tmuxSession -n $tmuxWindow
}

attach_tmux_session()
{
	tmux attach -t $tmuxSession > /dev/null 2>&1
}

tmux_status()
{
	tmux has -t $tmuxSession > /dev/null 2>&1
	return $?
}

stop_tmux_session()
{
	tmux kill-session -t $tmuxSession
}

check_ram_disk()
{
	local mcdu=$(du -Lsm $McWorldSavePath | cut -f 1)
	
	if [ $mcdu -ge $RamDiskSizeMB ]; then
		echo "echo The minecraft installation is too large to mount as a ram disk" >&2
		exit 1
	elif [ $mcdu -ge $((RamDiskSizeMB / 10 * 9)) ]; then
		echo "echo Warning: Your ram disk is above 90% capacity"
		echo "echo Press enter to continue"
		read
	fi
}

mount_ram_disk()
{
	mkdir $RamDiskMntPath
	mount -t tmpfs -o defaults,size=${RamDiskSizeMB}m tmpfs $RamDiskMntPath
}

load_ram_disk()
{
	cp -a $McWorldSavePath/* $RamDiskMntPath
}

umount_ram_disk()
{
	umount -f $RamDiskMntPath
	rm -d $RamDiskMntPath
}

start_server()
{
	$tmuxSend "ln -s $RamDiskMntPath $McPath/world" Enter
	$tmuxSend "clear" Enter
	$tmuxSend "java $JavaOpts -jar $ForgeJar $ForgeOpts" Enter
}

server_closed()
{
	rm $McPath/world
	sleep 5s
}

minecraft_status()
{
	ps -eo args | fgrep java | fgrep $ForgeJar
	return $?
}

save()
{
	if ! tmux_status ; then
		return 1
	fi
	
	if ! minecraft_status ; then
		return 1
	fi
	
	local McUptime=$(ps -eo etimes,args | fgrep java | fgrep $ForgeJar | tr -s [:blank:] | cut -d ' ' -f 2)
	
	if [ $McUptime -lt 600 ]; then
		return 1
	fi
	
	$tmuxSend "say Save sequence begins in 30 seconds.." Enter
	sleep 30s

	$tmuxSend "save-off" Enter
	sleep 5s
	$tmuxSend "save-all" Enter
	sleep 5s
	
	local CanonicalWorld=$(readlink $McPath/world.save | tr -cd [:digit:])
	local NewWorld=
	
	if [ $CanonicalWorld -eq 1 ]; then
		NewWorld=$McPath/world.save2
	else
		NewWorld=$McPath/world.save1
	fi
	
	cp -au $RamDiskMntPath/* $NewWorld
	ln -s $NewWorld $McPath/world.save.new
	mv -T $McPath/world.save.new $McPath/world.save
	
	$tmuxSend "save-on" Enter
	sleep 5s
	$tmuxSend "say Save sequence finished" Enter
	return 0
}

add_save_cronjob()
{	
	( crontab -l | fgrep -v "$CronCmd" ; echo "$CronJob" ) | crontab -
}

remove_save_cronjob()
{
	( crontab -l | fgrep -v "$CronCmd" ) | crontab -
}

# Check for superuser
if [ $(id -u) -ne 0 ]; then
	echo "You must be the superuser to run this script" >&2
	exit 1
fi

case "$1" in
	start)
		if tmux_status || minecraft_status ; then
			echo "Server is already running" >&2
			exit 1
		fi
	
		$(start_tmux_session)
		$(check_ram_disk)
		$(mount_ram_disk)
		$(load_ram_disk)
		$(start_server)
		$(add_save_cronjob)
		$(attach_tmux_session)
		$(remove_save_cronjob)
		$(server_closed)
		$(umount_ram_disk)
		$(stop_tmux_session)
		exit 0
	;;
	save)
		$(save)
		exit $?
	;;
	*)
		echo "No argument given. Try 'start'" >&2
		exit 1
esac
