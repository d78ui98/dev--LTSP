#!/bin/bash -x

# Source setting.sh
source /vagrant/settings.sh

# Fetching LAN_IP and network address
if [[ ${STANDALONE,,} != yes ]]; then
   LAN_IP=$(ip addr | grep "inet\b" | cut -d" " -f6 | grep 192 |  cut -d/ -f1)
   sed -i /vagrant/settings.sh \
      -e "/LAN_IP=""/ c LAN_IP=\"$LAN_IP\""
fi
NETWORK="$(echo $LAN_IP | cut -d'.' -f1-3)"

# Adding repository and Updating packages
add-apt-repository ppa:ts.sch.gr --yes
apt update --yes
# Setting type of user interface with a boot parameter - https://www.debian.org/releases/jessie/i386/ch05s03.html 
DEBIAN_FRONTEND=noninteractive apt upgrade --yes

# Installing packages
apt install --yes --install-recommends ltsp-server epoptes
DEBIAN_FRONTEND=noninteractive apt install --yes --install-recommends ltsp-client
apt install --yes ltsp-manager 

# Adding vagrant user to group epoptes
gpasswd -a ${SUDO_USER:-$(logname)} epoptes

# Updating kernel
echo 'IPAPPEND=3' >> /etc/ltsp/update-kernels.conf
/usr/share/ltsp/update-kernels

# Configure dnsmasq
ltsp-config dnsmasq

# enabling password authentication 
sed -i /etc/ssh/sshd_config \
    -e "/PasswordAuthentication no\$/ c PasswordAuthentication yes"
service ssh restart

# Creating lts.conf
ltsp-config lts.conf

# Client reboot issue fix (https://github.com/NetworkBlockDevice/nbd/issues/59)
echo 'INIT_COMMAND_MV_NBD_CHECKUPDATE="mv /usr/share/ldm/rc.d/I01-nbd-checkupdate /usr/share/ldm/rc.d/I01-nbd-checkupdate.orig"' \
    >> /var/lib/tftpboot/ltsp/i386/lts.conf

# Installing additional software
apt install --yes $PACKAGES

# Creating client image
ltsp-update-image --cleanup /

# Setting dhcp-range
sed -i /etc/dnsmasq.d/ltsp-server-dnsmasq.conf \
    -e "/^dhcp-range=.*,8h\$/ c dhcp-range=${NETWORK}.20,${NETWORK}.250,8h"

# Setting mode of operation of ltsp server
if [[ ${STANDALONE,,} == "yes" ]]; then
    echo "LTSP server will be in standalone mode of operation"	
    echo "LTSP server will provide DHCP services.."	
    sed -i /etc/dnsmasq.d/ltsp-server-dnsmasq.conf \
        -e "/.*,proxy\$/ c \ " 
else
    echo "LTSP server will be in Non-standalone mode of operation"	
    echo "There is an existing DHCP server running"
    echo "LTSP server won't provide DHCP services.."
    sed -i /etc/dnsmasq.d/ltsp-server-dnsmasq.conf \
        -e "/192.168.1.0,proxy\$/ c dhcp-range=${NETWORK}.0,proxy"
fi

# Restarting service
service dnsmasq restart
