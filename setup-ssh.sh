#!/bin/sh

mkdir -p /home/jenkins/.ssh
echo $SSH_PUBLIC_KEY >> /home/jenkins/.ssh/authorized_keys
echo 'Host * StrictHostKeyChecking no' > /home/jenkins/.ssh/config

chown -R jenkins /home/jenkins/.ssh
chmod 700 /home/jenkins/.ssh
chmod 600 /home/jenkins/.ssh/authorized_keys
chmod 600 ~/.ssh/config

rc-update --update
rc-update add sshd
/etc/init.d/sshd start
touch /run/openrc/softlevel
/etc/init.d/sshd restart
rc-status
