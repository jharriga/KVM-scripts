#!/bin/bash
# buildVMs.sh script
#
# It is expected that you have already run 'cfgServer.sh' which prepares
# the kvm host system for execution of this script. Specifically that
# script installs ansible, python, libguestfs and adds the users ansible
# and perfkit with passwordless ssh access configured
#--------------------------------------------------------------------
# Upon completion you should have VMCNT guests running DISTROBUILD, each
# configured through ANSIBLE with access to the EPEL repo and passwordless
# SSH for the users 'ansible' and 'perfkit', each in group 'root'
#-----------------------------------------------------------------------
# WARNING: do not run this as root - it SHOULD fail!
#
# SSH Setup
#     http://www.hashbangcode.com/blog/ansible-ssh-setup-playbook
#
#
# John Harrigan    March 2016
#
# NEEDS:  
#    * more robust destroy images if they exist
#    * variable for perfkit remote user (currently as 'jharriga')
#    * test if running as root, then exit
########################################################################

# FILES and DIRECTORIES
TMPDIR="./tmpfiles/"
HOSTSFILE="${TMPDIR}buildVMs.inv"
PLAYBOOK="${TMPDIR}buildVMs.yaml"
IMAGEDIR="./Images/"
SSHCONFIG="$HOME/.ssh/config"
SSHHOLD="${SSHCONFIG}.ORIG"

# RUNTIME vars
IPTIMEOUT=30                 # maximum number of secs to wait for Guest IPaddress
DOMAINNAME="localdomain"
ROOTPASSWD="password:redhat"
#VMCNT=3                     # passed on cmdline as arg1

#DISTROBUILD="centos-6"
#DISTROINSTALL="centos6"
DISTROBUILD="centos-7.2"
DISTROINSTALL="centos72"
OSVARIANT="linux"
NUMVCPUS=1
MEMSZ=1024
#DISKSZ=6G

#--------------------------------------------------------------------
# FUNCTION: get_ABS_filename
#   Gets absolute full pathed filename
#   USAGE:
#     myabsfile=$(get_abs_filename "../../foo/bar/file.txt")
#     $1 : relative filename
get_ABS_filename() {
  echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

#--------------------------------------------------------------------
# FUNCTION: chk_Success
#   checks return value from most recently called command
#   USAGE:
#     chk_Success $? "error msg"
#     $1 : return code from cmd
#     $2 : message to echo to stdout
chk_Success() {
  returncode=$1
  message=$2
  if [ $returncode -ne 0 ]; then
    echo "FAILED: ${message}. Aborting..."
    exit 1
  fi
}

#------------------------------------------------------------------
# FUNCTION: virt_Addr
#   Returns the IP address of a running KVM guest VM
#   Assumes a working KVM/libvirt environment
#   USAGE:
#     IPADDR=$( virt_addr "${KVMNAME}" )
#     $1 : KVM domainname of Guest machine
#     NOTE: be sure to delay long enough for Guest to hit network
#           experience indicates that 20 seconds is minimum
virt_Addr() {
  VM="$1"
  address=""                 # starts as empty string

#  echo ">> Acquiring IPaddress for ${KVMNAME}: "
  clock=0
  sleepincr=5                # number of seconds to sleep

# Using retry logic here
# if address is NULL, sleep 5 and retry - maximum of IPTIME before bailing
  while [[ -z "$address" && $clock -lt $IPTIMEOUT ]]; do
    search=$(virsh dumpxml $VM | grep "mac address" | sed "s/.*'\(.*\)'.*/\1/g")
    address=$(arp -an | grep "$search" | awk '{ gsub(/[\(\)]/,"",$2); print $2 }')
    sleep "${sleepincr}"
    clock=$(( $clock + $sleepincr ))    # incr loop counter
  done

  if [[ -z "$address" ]]; then
    echo "-"                 # failed to find IPaddress
  else
    echo "$address"          # Success!
  fi
}

#--------------------------------------------------------------------
# FUNCTION: exit_Usage
#   prints USAGE msg and exits
#
exit_Usage() {
  echo "USAGE: buildVMs.sh <VMCNT>"
  echo "> Must the number of VMs to create - ARG1"
  echo "Aborting"
  exit 1
}

#####################################################################
# First off - Check for ARGs: numVMs=ARG1

if [[ -z "$1" ]]; then
  exit_Usage
fi
VMCNT=$1

#####################################################################
# Verify PACKAGES are installed and configured before proceeding
#
# this should be put in a loop with an array
echo "Testing for pre-requisites"
virsh --version > /dev/null 2>&1
chk_Success $? "LIBGUESTFS not installed - have you run 'cfgServer.sh' ?"
python --version > /dev/null 2>&1
chk_Success $? "PYTHON not installed - have you run 'cfgServer.sh' ?"
virt-install --version > /dev/null 2>&1
chk_Success $? "virt-install not installed - have you run 'cfgServer.sh' ?"

#************************************************************
# Notify user = FAIL: must execute 'cfgServer' first
#************************************************************


#--------------------------------------------------------------------
# DestroyVMs with matching domainnames, if they already exist
#
LIST_VM=`virsh list --all | grep ${DISTROINSTALL}  | awk '{print $2}'`
#**************************************************************
# DEBUG - if VMCNT=1 "[: centos6_1: unary operator expected"
# is this loop even needed?
#if [ $LIST_VM ]; then
#  echo "VMs found named ${DISTROINSTALL}: ${LIST_VM}"
#else
#  echo "no VMs found named ${DISTROINSTALL}"
#fi

x=0
for existingvm in $LIST_VM; do
  echo "** Attempting to destroy/shutdown, then undefine ${existingvm} guest"
  virsh destroy $existingvm 2> /dev/null
  virsh undefine $existingvm 2> /dev/null
  chk_Success $? "virsh undefine ${existingvm}"

  x=$(( $x + 1 ))            # incr loop counter
done

if [ $x -gt 0 ]; then
  echo "** Destroyed and undefined ${x} guests matching ${DISTROINSTALL}"; echo
  sleep 5                    # delay to avoid (image file permission) race condition
fi

#####################################################################
#--------------------------------------------------------------------
# Remove old files from TMPDIR
if [ -e $TMPDIR ]; then
  rm -rf $HOSTSFILE $PLAYBOOK
  chk_Success $? "could not remove file from existing ${TMPDIR} directory"
else
# FAIL: must execute 'cfgServer' first
  mkdir $TMPDIR
  chk_Success $? "could not create new ${TMPDIR} directory"
fi

#--------------------------------------------------------------------
# Create a fresh copy of IMAGEDIR
if [ -e $IMAGEDIR ]; then
  rm -rf $IMAGEDIR
  chk_Success $? "could not remove existing ${IMAGEDIR} directory"
fi
mkdir $IMAGEDIR
chk_Success $? "could not create new ${IMAGEDIR} directory"

#--------------------------------------------------------------------
# Build the hosts INVENTORY file for ansible
cat <<EOF1 > $HOSTSFILE
#---
# Ansible HOSTS file - a.k.a. inventory
#-
[kvmhosts]
EOF1
chk_Success $? "could not create ${HOSTSFILE} file"


#--------------------------------------------------------------------
# Build the PLAYBOOK file for ansible
# see this for SSH security features
#   https://github.com/geerlingguy/ansible-role-security/blob/master/tasks/ssh.yml
if [ -e $PLAYBOOK ]; then
  rm $PLAYBOOK
  chk_Success $? "could not remove ${PLAYBOOK} file. Aborting..."
fi

cat <<EOF3 > $PLAYBOOK
---
# Ansible Playbook created by 'buildVMs.sh'
- hosts: kvmhosts
  sudo: True

  vars:
    users:
      user1:
        name: ansible
        groups: root
        password: redhat
      user2:
        name: perfkit
        groups: root
        password: redhat
      user3:
        name: jharriga
        groups: root
        password: redhat
    is_ver6: "{{ ansible_distribution_major_version | int == 6 }}"
    is_ver7: "{{ ansible_distribution_major_version | int == 7 }}"
    is_centos: "{{ansible_distribution == 'CentOS'}}"
    is_rhel: "{{ansible_distribution == 'RHEL'}}"
    is_centos7: is_centos|bool and is_ver7|bool
    is_rhel7: is_rhel|bool and is_ver7|bool

  tasks:
  - name: Check that the VM is running
    action: ping

  - name: Add the users
    user:
      name={{ item.value.name }}
      groups={{ item.value.groups }}
      state=present
      system=yes
      append=true
    with_dict: "{{users}}"

  - name: Set their passwords
    shell: echo {{ item.value.name }}:{{ item.value.password }} | sudo chpasswd
    no_log: True
    with_dict: "{{users}}"

  - name: install selinux bindings
    yum: name=libselinux-python state=present
    when: ansible_distribution == 'RedHat' or ansible_distribution == 'CentOS'

  - name: set SELinux to disabled
    selinux:
      state: disabled
    when: ansible_distribution == 'RedHat' or ansible_distribution == 'CentOS'

  - name: Add the users to passwordless sudoers
    lineinfile:
      dest: /etc/sudoers
      regexp: '^{{ item.value.name }}'
      line: '{{ item.value.name }} ALL=(ALL) NOPASSWD: ALL'
      state: present
      validate: 'visudo -cf %s'
    with_dict: "{{users}}"

  - name: Add EPEL repository
    get_url: dest=/tmp/epel-release.rpm  url=https://dl.fedoraproject.org/pub/epel/epel-release-latest-{{ ansible_distribution_major_version }}.noarch.rpm
    when: ansible_distribution == 'RedHat' or ansible_distribution == 'CentOS'

  - name: install epel-repo rpm
    yum: pkg=/tmp/epel-release.rpm state=installed
    when: ansible_distribution == 'RedHat' or ansible_distribution == 'CentOS'

  - name: install FIO bmark utility
    yum: name=fio state=latest

  - name: install IPERF bmark utility
    yum: name=iperf state=latest

# DEBUG: this works on RHEL 7 not RHEL 6. The compound when/test isn't working
  - name: Disable and Stop firewallD for iperf tests
    service: name=firewalld enabled=no state=stopped
    when: is_centos7

#************************* DEBUG REQD
# SHOULD echo which users had the SSH keys copied and NOT
#
  - name: determine which users have SSH key files
    local_action: stat path=/home/{{ item.value.name }}/.ssh/id_rsa.pub
    with_dict: "{{users}}"
    register: key_file

  - name: add SSH keys ONLY IF user key file exists
    authorized_key: 
      user: "{{ item.item.value.name }}"
      key: "{{ lookup('file', '{{ item.invocation.module_args.path }}') }}"
      manage_dir: no
    with_items: "{{key_file.results}}"
    when:
      - item.stat.exists == true

  - debug: msg="** SSH key found & copied for user {{ item.item.value.name }}"
    with_items: "{{key_file.results}}"
    when:
      - item.stat.exists == true
EOF3
chk_Success $? "could not create ${PLAYBOOK} file. Aborting..."


#####################################################################
#--------------------------------------------------------------------
# VIRT-BUILDER LOOP
echo; echo "Starting VIRT-BUILDER and VIRT-INSTALL loop"
i=1
while [[ $i -le $VMCNT ]]; do
  KVMNAME="${DISTROINSTALL}_${i}"
  HOSTNAME="${KVMNAME}.${DOMAINNAME}"
  IMGNAME="${KVMNAME}.img"
  IMGPATH="${IMAGEDIR}${IMGNAME}"
#  IMGABS=$(get_abs_filename $IMGPATH)

# Build the Guest image
  echo "+++++++++++++++++++++++++++++++++++++++++"
  echo "** Building instance with Hostname: ${HOSTNAME} ..."

# virt-builder: 
#   Specify DISTRO, ROOTPASSWD, HOSTNAME and IMAGEPATH
  virt-builder $DISTROBUILD --root-password $ROOTPASSWD --hostname $HOSTNAME -o $IMGPATH
#     --no-check-signatures --size $DISKSZ \
#     --update --edit '/etc/yum.conf: s/gpgcheck=1/gpgcheck=0/' \
#     --firstboot $SCRIPTADDUSER

  chk_Success $? "virt-builder cmd for loop # ${i}"
  echo ">> SUCCESS virt-builder: ${HOSTNAME}"

# virt-install: Import the disk image into libvirt
#   Specify domainname, memory size, imagepath, numcpus and osvariant
#   create guest with no graphics and no console (to avoid interactive console creation)
  echo "** Installing image with Hostname: ${HOSTNAME} ..."
  virt-install --import --name $KVMNAME --ram $MEMSZ --disk $IMGPATH --vcpus $NUMVCPUS \
    --network bridge=virbr0 --graphics none --noautoconsole --os-variant $OSVARIANT
  
  chk_Success $? "virt-install cmd for loop # ${i}"

  echo ">> SUCCESS virt-install: ${HOSTNAME} with ${DISTROBUILD}"

# Add IPaddr to Ansible hosts inventory
# Call virt_Addr function with Guest domainname to get the IPaddress
  echo ">> Acquiring IPaddress for ${KVMNAME} : waiting..."
  IPADDR=$( virt_Addr "${KVMNAME}" )
  if [ $IPADDR = "-" ]; then
      echo "Failed to get IPaddr from ${KVMNAME}. Aborting."
      exit 1
  else
      echo "**** IPaddress from ${KVMNAME} is ${IPADDR}"
# changed for ansible 2.0
      echo "${IPADDR} ansible_ssh_pass=redhat" >> $HOSTSFILE 
#      echo "${IPADDR} ansible_ssh_user=root ansible_ssh_pass=redhat" >> $HOSTSFILE
  fi

  i=$(( $i + 1 ))            #incr loop counter
  echo
done

echo "Completed VIRT-BUILDER and VIRT-INSTALL loop"
buildcnt=$(( $i - 1 ))
echo "Built and installed ${buildcnt} Guest system(s)"
echo "+++++++++++++++++++++++++++++++++++++++++"

#####################################################################
#--------------------------------------------------------------------
# Execute ANSIBLE playbook:
#  - ping the Guest
#  - add the users (ansible, perfkit) with sudo privs
#  - echo the 'nodename' and ipaddress
#  - disable SELinux
#  - add EPEL repository
#  - install iperf and fio bmarks
#--------------------------------------

echo; echo "Configuring hosts with ansible-playbook..."

#--------------------------------------
# Execute the Playbook
#   disable host key checking via env var
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook $PLAYBOOK -i $HOSTSFILE -u root
chk_Success $? "ansible-playbook ${PLAYBOOK} failed. Aborting..."

# list the Guests
echo "list Guests"
virsh list --all
#echo "list Guests as root"
#sudo virsh --connect qemu://session list --all

#--------------------------------------
echo "SUCCESS: run completed"

echo "${ROOTPASSWD}"
./showVMs.sh

exit 0


