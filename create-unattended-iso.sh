#!/usr/bin/env bash


##################
## Initializing ##
##################
# file names & paths
working_dir=`pwd -P`
currentuser="$(whoami)"
seed_file="preseed.cfg"
preseed_host="http://10.0.2.2:8000"
#
# command line args
input_preseed_file=$1
username=${2-"cloudinn"}
password=${3-"cloudinn"}
hostname=${4-"proxy"}
timezone=${5-"Etc/UTC"}
menu_lang=${6-"en"}
ipaddress=${7-"192.168.1.42"}
netmask=${8-"255.255.255.0"}
gateway=${9-"192.168.1.1"}
nameserver=${10-"8.8.8.8,8.8.4.4"}
#
if [ -z $input_preseed_file ] || [ $1 = '-h' ] || [ $1 = '--help' ]; then
  echo " no preseed file was given"
  echo "Usage: $0 <preseed_file> [username[password[hostname[timezone[menu_language[ipaddress[netmask[gateway[nameserver]]]]]]]]]"
  echo
  exit 1
else
  input_preseed_file=`realpath $input_preseed_file`
fi
#
# check if the script is running without sudo or root priveleges
if [ $currentuser != "root" ]; then
    echo " you need sudo privileges to run this script, or run it as root"
    exit 1
fi


##########################
## Function definations ##
##########################
#
# define spinner function for slow tasks
# courtesy of http://fitnr.com/showing-a-bash-spinner.html
spinner()
{
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}
#
# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}
#
# define function to check if program is installed
# courtesy of https://gist.github.com/JamieMason/4761049
function program_is_installed {
    # set to 1 initially
    local return_=1
    # set to 0 if not found
    type $1 >/dev/null 2>&1 || { local return_=0; }
    # return value
    echo $return_
}


#########################
## Distro ISO download ##
#########################
#
download_file="mini.iso"  # filename of the downloaded iso
download_location="http://archive.ubuntu.com/ubuntu/dists/xenial/main/installer-amd64/current/images/netboot/"  # location of the file to be downloaded
output_iso_name="ubuntu-cloudinn.iso"
#
mkdir -p $working_dir
if [[ ! -f $working_dir/$download_file ]]; then
    echo -n " downloading $download_file: "
    download "$download_location$download_file"
fi
if [[ ! -f $working_dir/$download_file ]]; then
	echo "Error: Failed to download ISO: $download_location$download_file"
	echo "This file may have moved or may no longer exist."
	echo
	echo "You can download it manually and move it to $working_dir/$download_file"
	echo "Then run this script again."
	exit 1
fi


###########################
## Dependencies download ##
###########################
#
installing_apps=''
#
if [ $(program_is_installed "mkpasswd") -eq 0 ] || [ $(program_is_installed "mkisofs") -eq 0 ]; then
  installing_apps=$installing_apps' genisoimage'
fi
#
if [ $(program_is_installed "mkpasswd") -eq 0 ]; then
  installing_apps=$installing_apps' mkpasswd'
fi
#
if [ $(program_is_installed "isohybrid") -eq 0 ]; then
  installing_apps=$installing_apps' syslinux syslinux-utils'
fi
#
if [ $(program_is_installed "7z") -eq 0 ]; then
  installing_apps=$installing_apps' p7zip-full'
fi
#
if [ ! -z "$installing_apps" ]; then
  echo "Installing system dependencies: $installing_apps"
  (apt-get -y update > /dev/null 2>&1) &
  spinner $!
  (apt-get -y install $installing_apps > /dev/null 2>&1) &
  spinner $!
fi

######################
## Working on image ##
######################
#
# create working directories
echo " remastering your iso file"
tmp_iso_dir=$working_dir/iso_new
mkdir -p $tmp_iso_dir
#
# unpacking image
(7z x -y -o$tmp_iso_dir $working_dir/$download_file > /dev/null) &
spinner $!
#
# set the language for the installation menu
# doesn't work for 16.04
echo $menu_lang > $tmp_iso_dir/lang
#
# 16.04
# syslinux auto proceed
# taken from https://github.com/fries/prepare-ubuntu-unattended-install-iso/blob/master/make.sh
sed -i -r 's/timeout\s+[0-9]+/timeout 1/g' $tmp_iso_dir/isolinux.cfg
# sed -i -r 's/prompt\s+[0-9]+/prompt 2/g' $tmp_iso_dir/isolinux.cfg
#
# copy the preseed file to the iso
new_seed_path=$working_dir/preseed/$seed_file
mkdir -p $working_dir/preseed
cp -rT $input_preseed_file $new_seed_path
#
# generate the password hash
pwhash=$(echo $password | mkpasswd -s -m sha-512)
#
# update preseed file
sed -i "s@{{username}}@$username@g" $new_seed_path
sed -i "s@{{pwhash}}@$pwhash@g" $new_seed_path
sed -i "s@{{hostname}}@$hostname@g" $new_seed_path
sed -i "s@{{timezone}}@$timezone@g" $new_seed_path
#
# calculate checksum for seed file
seed_checksum=$(md5sum $new_seed_path | cut -d\  -f1)
#
# remove default menu selection
sed -i "/menu default/d" $tmp_iso_dir/txt.cfg
#
install_params="\
console-setup/layoutcode=us \
passwd/user-fullname=$username \
passwd/username=$username \
passwd/user-password-crypted=$pwhash \
hostname=$hostname \
domain=$hostname \
time/zone=$timezone \
mirror/country=auto \
mirror/http/mirror=us.archive.ubuntu.com \
mirror/http/proxy= \
netcfg/choose_interface=eth1 \
netcfg/get_ipaddress=$ipaddress \
netcfg/get_netmask=$netmask \
netcfg/get_gateway=$gateway \
netcfg/get_nameservers=$nameserver \
netcfg/confirm_static=true \
user-setup/encrypt-home=false \
partman-auto/init_automatically_partition=biggest_free \
partman-md/confirm=true \
partman-partitioning/confirm_write_new_label=true \
partman/choose_partition=finish \
partman/confirm=true \
partman/confirm_nooverwrite=true \
"
# clock-setup/ntp=true \
# finish-install/reboot_in_progress=true \
# console-setup/ask_detect=false \
# partman-lvm/confirm=false \
# partman-md/confirm=false \
#
# add our new option to the menu as default
sed -i "/label install/ilabel autoinstall\n\
  menu label ^Proxy auto-install\n\
  menu default\n\
  kernel linux\n\
  append\
  preseed/url=$preseed_host/preseed/$seed_file\
  initrd=initrd.gz\
  auto=true\
  priority=high\
  language=en\
  country=US\
  locale=en_US\
  --" $tmp_iso_dir/txt.cfg
#  $install_params\
# creating the remastered iso
cd $tmp_iso_dir || exit
(mkisofs -D -r -V "CLOUDINN_UBUNTU" -cache-inodes -J -l -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $working_dir/$output_iso_name . > /dev/null 2>&1) &
spinner $!
#
# make iso bootable (for dd'ing to USB stick)
isohybrid $working_dir/$output_iso_name
#
# cleaning
# rm -rf $tmp_iso_dir  # XXX uncomment this
#
# print info to user
echo
echo " -----"
echo " finished remastering your ubuntu iso file"
echo " the new file is located at: $working_dir/$output_iso_name"
echo " your username is: $username"
echo " your password is: $password"
echo " your hostname is: $hostname"
echo " your timezone is: $timezone"
echo

# unset vars
unset username
unset password
unset hostname
unset timezone
unset pwhash
unset download_file
unset download_location
unset new_iso_name
unset tmp
unset seed_file
unset working_dir
