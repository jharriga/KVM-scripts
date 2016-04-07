#!/bin/bash
#
# cfg_Server - prepares a local or remote CentOS server to execute 
#              'buildVMs.sh' and 'runPBK.sh' scripts
# USAGE: $ cfg_Server.sh <SvrIPaddress> <rootPasswd>
#          <SvrIPaddress> is required. Use 127.0.0.1 for localhost.
#          <rootPasswd> is required. Root password for Server.
# 
# Installs ANSIBLE (if needed) and then runs cfgServer.yaml playbook
#    'cfgServer.yaml':
#	- add users 'ansible & 'perfkit' with <rootPasswd>
#       - generate sshkeys
#	    - ssh-keygen -t rsa -b 4096 -C "random-string-of-chars"
#	    - chown and chmod 600
#	- installs necessary pkgs on the server (RHELpkgs, DEBpkgs)
#       - copies req'd files to remote server (REMOTEfiles)
#####################################################################

# These files could be placed under ./tmpfiles dir
# FILES and DIRECTORIES
TMPDIR="./tmpfiles/"
PLAYBOOK="${TMPDIR}cfgServer.yaml"
INVFILE="${TMPDIR}cfgServer.inv"

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

#--------------------------------------------------------------------
# FUNCTION: exit_Usage
#   prints USAGE msg and exits
#
exit_Usage() {
  echo "USAGE: cfgServer.sh <SvrIPaddr> <RootPasswd>"
  echo "> Must provide an IP address or hostname for the server - ARG1"
  echo "> Must provide the root password for the server - ARG2"
  echo "Aborting"
  exit 1
}
#--------------------------------------------------------------------

#####################################################################
# First off - Check for ARGs: SvrIPaddress=ARG1; RootPasswd=ARG2

if [[ -z "$1" || -z "$2" ]]; then
  exit_Usage
fi

SvrIPaddr=$1
RootPasswd=$2

# Warn the user about the intent of this script
echo
echo "This script will prepare a remote Linux server for the buildVMs.sh script."
echo "It will install: virtualization packages; ansible and add these users"
echo "(perfkit, ansible) with SUDO access."
echo "Their password's will be set to ARG2, <RootPasswd>"
echo "The server must already be running CentOS 6/7 and you must have root access."
echo
echo "Do you wish to continue?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) break;;
        No ) exit;;
    esac
done

#--------------------------------------------------------------------
# Create the ansible hosts inventory file
if [ -e $INVFILE ]; then
  rm $INVFILE
  chk_Success $? "could not remove ${INVFILE} file. Aborting..."
fi

cat <<EOF1 > $INVFILE
#---
# Ansible HOSTS file - a.k.a. inventory
#-
[servers]
EOF1

# changed for ansible 2.0
echo "${SvrIPaddr} ansible_ssh_user=root ansible_ssh_pass=${RootPasswd}" >> $INVFILE

#--------------------------------------------------------------------
# Verify specified server (ARG1) is pingable, using ansible with 
# provided RootPasswd (ARG2)
#
# need to set 'host_key_checking' flag
# which can also be set inside the PLAYBOOK
#    environment:
#	ANSIBLE_HOST_KEY_CHECKING: False
#
echo "Testing ansible connection capability - running PING test..."
export ANSIBLE_HOST_KEY_CHECKING=False
ansible servers -v -i $INVFILE -m ping

chk_Success $? "ansible could not connect. Aborting..."

echo "SUCCESS: now running full ansible playbook..."

#--------------------------------------------------------------------
# Build the PLAYBOOK file for ansible
# see this for SSH security features
#   https://github.com/geerlingguy/ansible-role-security/blob/master/tasks/ssh.yml
if [ -e $PLAYBOOK ]; then
  rm $PLAYBOOK
  chk_Success $? "could not remove ${PLAYBOOK} file. Aborting..."
fi

cat <<EOF > $PLAYBOOK
---
# Ansible Playbook created by 'cfgServer.sh'
#  'passwd' passed in cmdline using: --extra-vars "passwd=$RootPasswd"
- hosts: all
  sudo: True

  vars:
# PITA: build up version number vars
    not_ver6: "{{ ansible_distribution_major_version | int != 6 }}"
    not_ver7: "{{ ansible_distribution_major_version | int != 7 }}"
    is_ver6: "{{ ansible_distribution_major_version | int == 6 }}"
    is_ver7: "{{ ansible_distribution_major_version | int == 7 }}"
    is_centos: "{{ansible_distribution == 'CentOS'}}"
    not_centos: "{{ansible_distribution != 'CentOS'}}"
    not_rhel: "{{ansible_distribution != 'RHEL'}}"
    is_rhel: "{{ansible_distribution == 'RHEL'}}"
    is_centos7: is_centos|bool and is_ver7|bool
    is_rhel7: is_rhel|bool and is_ver7|bool
    is_ubuntu: "{{ansible_distribution == 'Ubuntu'}}"
    is_debian: "{{ansible_distribution == 'Debian'}}"
    not_ansible2: "{{ ansible_version.major | int != 2 }}"

    users:
      user1:
        name: perfkit
        groups: root
        password: '{{ passwd }}'
        directory: /home/perfkit
      user2:
        name: ansible
        groups: root
        password: '{{ passwd }}'
        directory: /home/ansible
    RHELpkgs:
      - { key: 'one', value: sudo }
      - { key: 'two', value: python }
      - { key: 'three', value: python-paramiko }
      - { key: 'four', value: net-tools }
      - { key: 'five', value: qemu-kvm }
      - { key: 'six', value: libvirt }
      - { key: 'seven', value: virt-install }
      - { key: 'eight', value: libguestfs }
      - { key: 'nine', value: libguestfs-tools }
    RHELsvcs:
      - { key: 'one', value: libvirtd }
    DEBpkgs:
      - { key: 'one', value: sudo }
      - { key: 'two', value: ansible }
      - { key: 'three', value: python }
    REMOTEfiles:
      file1:
        local: ../buildVMs.sh
        remote: buildVMs.sh
      file2:
        local: ../fio.job
        remote: fio.job
      file3:    
        local: ../runPKB.sh
        remote: runPKB.sh
      file4:
        local: ../showVMs.sh
        remote: showVMs.sh
      file5:
        local: ../virtFunctions.sh
        remote: virtFunctions.sh

  tasks:
  - name: Test if server is running RHEL or CentOS, if not *exit*
    fail: msg="Requires RHEL/CentOS. Server running {{ansible_distribution}} - aborting"
    when: not_centos and not_rhel

  - name: Test if server is running RHEL/CentOS ver6 or ver7, if not *exit*
    fail: msg="Requires RHEL/CentOS ver6/7. Server running {{ansible_distribution_major_version}} - aborting"
    when: not_ver6 and not_ver7

  - name: Finally chk for ansible 2.0
    fail: msg="Running ansible {{ansible_version}}. Requires ansible 2.0 or later - aborting"
    when: not_ansible2

  - name: Add the users
    user:
      name={{ item.value.name }}
      groups={{ item.value.groups }}
      home={{ item.value.directory }}
      state=present
      system=yes
      shell=/bin/bash
      generate_ssh_key=yes
      ssh_key_bits=2048
      ssh_key_file=.ssh/id_rsa
      append=true
    with_dict: "{{ users }}"

  - name: set their passwords
    shell: echo {{ item.value.name }}:{{ item.value.password }} | sudo chpasswd
    no_log: True
    with_dict: "{{ users }}"

  - name: Add them to passwordless sudoers
    lineinfile:
      dest: /etc/sudoers
      regexp: '^{{ item.value.name }}'
      line: '{{ item.value.name }} ALL=(ALL) NOPASSWD: ALL'
      state: present
      validate: 'visudo -cf %s'
    with_dict: "{{ users }}"

#********************************************************************
# Install required software: ansible; python; libguestfs-tools
# Using distro specific lists here to allow distro specific pkg names
# Lists created with 'keys' to enforce order of pkg installation
# - WHEN: can also test "ansible_distribution_version" if needed
#********************************************************************
  - debug: msg="Installing software packages takes some time - Please wait..."

  - name: Add EPEL repository
    get_url: dest=/tmp/epel-release.rpm  url=https://dl.fedoraproject.org/pub/epel/epel-release-latest-{{ ansible_distribution_major_version }}.noarch.rpm
    when: is_rhel or is_centos

  - name: install epel-repo rpm
    yum: pkg=/tmp/epel-release.rpm state=installed
    when: is_rhel or is_centos

  - name: install software pkgs, conditional to distribution type RHEL|CentOS
    yum:
      name={{ item.value }}
      state=present
    with_items: "{{ RHELpkgs }}"
    when: is_rhel or is_centos

  - easy_install: name=pip state=latest
    when: is_rhel or is_centos

# Install the same version of ansible on the remote host as running here
  - pip: name=ansible state=present version={{ ansible_version.full }}
    when: is_rhel or is_centos

  - name: start services, conditional to distribution type RHEL|CentOS
    service:
      name={{ item.value }}
      state=started
      enabled=yes
    with_items: "{{ RHELsvcs }}"
    when: is_rhel or is_centos

  - name: install software pkgs, conditional to distribution type DEBIAN
    apt:
      name={{ item.value }}
      state=present
    with_items: "{{ DEBpkgs }}"
    when: is_debian or is_ubuntu

#****************************
# Note that the current directory is TMPDIR, since that is where PLAYBOOK
# and INVFILE live (vars set above)
  - name: Copy 'files' to perfkit users home directory (created above)
    copy: src={{ item.value.local }} dest=/home/perfkit/{{ item.value.remote }}
      owner=perfkit
      group=root
      mode=0755
    with_dict: "{{ REMOTEfiles }}"

EOF
chk_Success $? "could not create ${PLAYBOOK} file. Aborting..."

#--------------------------------------------------------------------
# Execute the ansible playbook
#
#  - set the 'passwd' var via shell cmdline
#
# Be certain to set 'host_key_checking' flag (done above)
# export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook $PLAYBOOK -v -i $INVFILE --extra-vars "passwd=$RootPasswd"
chk_Success $? "ansible-playbook ${PLAYBOOK} failed. Aborting..."

echo; echo "SUCCESS: Complete"; echo
echo " SSH as user 'perfkit' using supplied <rootPasswd>"
echo "    $ ssh perfkit@${SvrIPaddr}"
echo " Then run 'buildVMs.sh' on the remote host"; echo
exit 0

