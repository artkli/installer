#!/bin/bash

###############################################################################
# name: install.sh
# author: Artur Klimek
# created: 2020.02.01
# ver. 1
# for: Raspbian 
#
# usage:
#  sudo ./install.sh 
#  sudo ./install.sh -y
#
###############################################################################

# customize script
readonly ENABLEVNC=true
readonly ENABLESSH=true
readonly ROTATE=false
readonly ARMONLY=true

readonly OWNER="pi"
readonly PRODUCTNAME="PROGRAM"

readonly FORCE=$1
readonly SCRIPTNAME=$0

# system libraries that will be installed
readonly LIBRARIES="\
  python-dev \
  libatlas-base-dev \
  libncurses5-dev \
  libncursesw5-dev \
  unclutter \
  sharutils \
  dos2unix \
  x11-xserver-utils \
  build-essential \
  qt5-default \
  pyqt5-dev \
  pyqt5-dev-tools \
  python3-scipy \
  python3-numba \
  "

# file, path names
readonly INSTALLPATH=$(pwd|sed 's/ /?/g')
readonly OWNERPATH="/home/pi"
readonly DSTPATH="/home/pi/program"
readonly INSTALLFILES="install.zip"
readonly SRCFILES="program/*"
readonly CFGFILE="program.cfg"
readonly STARTSCRIPTFILE="program.sh"
readonly REQUIREMENTSFILE="requirements.txt"
readonly BOOTCONFIGFILE="/boot/config.txt"


# functions
prompt() {
  # ask for confirmation on the screen
  
  read -r -p "$@ [y/N] " text < /dev/tty
  if [[ $text =~ ^(yes|tak|y|Y|t|T)$ ]]; then
    true
  else
    false
  fi
}

confirm() {
  # check confirmation
  
  if [[ "$FORCE" == '-y' ]]; then
    true
  else
    prompt "$@"
  fi
}

error() {
  echo -e "$(tput setaf 1)$@$(tput sgr0)"
}

success() {
  echo -e "$(tput setaf 2)$@$(tput sgr0)"
}

warning() {
  echo -e "$(tput setaf 3)$@$(tput sgr0)"
}

inform() {
  echo -e "$(tput setaf 6)$@$(tput sgr0)"
}

run_check() {
  # run the command given as a parameter and check the status of the output
  
  text="\nRuning '$@':\n"
  inform "$text"

  "$@";
  if [[ $? > 0 ]]; then
    error "\nThe command failed, exiting.\n"
    exit 1
  fi
}

sudo_check() {
  # check if script was run as root
  
  if [[ $(id -u) != 0 ]]; then
    error "\nInstall must be run as root. Try 'sudo ${SCRIPTNAME}'\n"
    exit 1
  fi
}

rapberry_check() {
  # check if it run on raspberry and raspbian
  
  israpberry=false
  isrightrelease=false
  isarm=false

  if [ -f /etc/rpi-issue ]; then
    if cat /etc/rpi-issue | grep "Raspberry" > /dev/null; then
      israpberry=true
    fi
  fi

  if [ -f /etc/os-release ]; then
    if cat /etc/os-release | grep "buster" > /dev/null; then
      isrightrelease=true
    elif cat /etc/os-release | grep "stretch" > /dev/null; then
      isrightrelease=true
    fi
  fi
  
  if uname -m | grep "armv.l" > /dev/null; then
    isarm=true
  fi
  
  if ! ($israpberry && $isrightrelease && ($isarm || ! $ARMONLY)); then
    error "\nThis script is intended for Raspbian on a Raspberry Pi!\n"
    exit 1
  fi
}

network_check() {
  # check internet access

  if ! ping -q -c 1 -W 1 google.com >/dev/null 2>&1; then
    error "\nPlease connect to the Internet before run this script\n"
    exit 1
  fi
}

sleep_off() {
  # disable Wi-Fi sleep mode and screen saver
  
  if $ARMONLY; then
    interface=$(ip r|grep default|awk {'print $5'})
    if [[ $interface =~ ^wlan ]]; then
      run_check iw $interface set power_save off
    fi
  fi

  run_check dpkg --configure -a
  run_check apt-get install x11-xserver-utils -y --fix-missing
  if xset q >/dev/null 2>&1; then
    run_check xset s off
    run_check xset -dpms
    run_check xset s noblank 
  fi
}

system_upgrade() {
  # upgrade system
  
  run_check dpkg --configure -a
  run_check apt-get clean 
  run_check apt-get autoclean
  run_check apt-get autoremove -y
  run_check apt-get update --fix-missing
  run_check apt-get dist-upgrade -y --allow-unauthenticated --fix-missing
  run_check apt-get upgrade -y --allow-unauthenticated --fix-missing
  run_check apt-get clean 
  run_check apt-get autoclean
  run_check apt-get autoremove -y
}

system_lib_install() {
  # install the libraries given as parameters
  
  for pkg in $@; do
    if dpkg -s $pkg >/dev/null 2>&1; then
	  inform "\n${pkg} is already installed\n"
	else
      run_check apt-get install $pkg -y --fix-missing
	fi
  done
}

system_reboot() {
  # ask and do the system reboot
  
  warning "\nSystem must be rebooted to take effect.\n"

  if prompt "Would you like to reboot now?"; then
    sync && reboot
  fi
}

python_lib_install() {
  # install the Python libraries given in the requirements file
  
  if [ -f $REQUIREMENTSFILE ]; then
    run_check pip3 install -r $REQUIREMENTSFILE
  else
    error "\nMissing Python library requirements file (${REQUIREMENTSFILE})\n"
    exit 1    
  fi
  run_check pip3 install --upgrade colorama
}

unpack_files() {
  # unpack and check that all files are correct
  
  run_check mkdir $DSTPATH -p
  
  if [ -f $INSTALLFILES ]; then
    run_check unzip -o $INSTALLFILES
  else
    error "\nMissing ${INSTALLFILES}.\n"
    exit 1    
  fi
  
  if [ -f $CFGFILE ]; then
    run_check cp $CFGFILE $DSTPATH
  else
    error "\nMissing ${CFGFILE}."
    exit 1    
  fi
  
  run_check cp -r $SRCFILES $DSTPATH
}

prepare_to_run() {
  # set file permissions and set program autostart in X11
  
  run_check chown -R $OWNER:$OWNER $DSTPATH
  run_check cd $DSTPATH
  run_check dos2unix *.py
  run_check cd $INSTALLPATH
  if [ -f $STARTSCRIPTFILE ]; then
    run_check cp $STARTSCRIPTFILE $OWNERPATH/.Xsession
    run_check dos2unix $OWNERPATH/.Xsession
    run_check chmod +x $OWNERPATH/.Xsession
    run_check chown $OWNER:$OWNER $OWNERPATH/.Xsession
  else
    error "\nMissing ${STARTSCRIPTFILE} script\n"
    exit 1    
  fi
}

system_config() {
  # set network services and rotate LCD
  
  if $ENABLEVNC; then
    run_check systemctl enable vncserver-x11-serviced.service
    run_check sed -i "s|ExecStart=/usr/bin/vncserver-x11-serviced -fg|ExecStart=/usr/bin/vncserver-x11-serviced|g" /usr/lib/systemd/system/vncserver-x11-serviced.service
    run_check systemctl start vncserver-x11-serviced.service
  fi

  if $ENABLESSH; then
    run_check systemctl enable ssh
    run_check systemctl start ssh
  fi
  
  if $ROTATE; then  
    if grep -q "^lcd_rotate=" $BOOTCONFIGFILE >/dev/null 2>&1; then
      run_check sed -i "s/lcd_rotate=./lcd_rotate=2/g" $BOOTCONFIGFILE
    else
      echo "" >> $BOOTCONFIGFILE
      echo "lcd_rotate=2" >> $BOOTCONFIGFILE
    fi
  fi
}


###############################################################################
# MAIN
###############################################################################

# check
sudo_check
rapberry_check
network_check

# Introduction
inform "\nThis script will install everything needed to use:\n"
success "${PRODUCTNAME}\n"

# start
if confirm "Do you wish to continue?"; then
  sleep_off
  system_upgrade
  system_lib_install $LIBRARIES
  unpack_files
  python_lib_install
  system_config
  prepare_to_run
  
# end
  success "\nAll done!\n\n${PRODUCTNAME} installed.\n"
  system_reboot
else
  error "\nAborting.\n"
fi

exit 0
