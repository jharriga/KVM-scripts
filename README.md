# KVM-scripts

Here are a collection of scripts to automate KVM/QEMU guest creation
They use virt-builder and virt-install commands to create and start the
Guest and ansible playbooks to configure the Guests.

Script names and purpose:
* cfgServer.sh - configures a bare metal CentOS/RHEL 7 system to run 'buildVM.sh'.
# Installs ansible, python, libguestfs and adds the users with passwordless ssh access configured
* buildVMs.sh - creates the specified number of Guests running DISTROBUILD
# upon completion, prints Guest info including IP addresses. Uses dirs 'tmpfiles' and 'Images'

Utilities:
* showVMs.sh - prints table of Guest VM information including IP address
* virtFunctions.sh - contains code for showVMs.sh
