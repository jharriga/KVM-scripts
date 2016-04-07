#!/bin/bash
#
# showVMs.sh
#
# Contains a number of Functions for inquiring characteristics of existing
# virtual machines/guests.
#	- virt_ADDR: Returns the IP address of a running KVM guest VM
#	- virt_ADDRS
#	- virt_UUID
#	- virt_MEM
#	- virt_VCPU
#############################################################################

#----------------------------------------------------------------------------
# virt_ADDR
#   returns IPaddr of a single kvm guest, arg=KVMdomainname
# Usage: 
#   $ virt_ADDR vm-name
#   192.0.2.16
#
virt_ADDR() {
    VM="$1"
    search=$( virsh dumpxml $VM | grep "mac address" | sed "s/.*'\(.*\)'.*/\1/g")

    address=$(arp -an | grep "$search" | awk '{ gsub(/[\(\)]/,"",$2); print $2 }')

    if [[ -z "$address" ]]; then
        echo "-"
    else
        echo "$address"
    fi
}

#----------------------------------------------------------------------------
# virt_ADDRS
#   returns IPaddr of all found KVM guests
# Usage: 
#   $ virt_ADDRS
# 
#
virt_ADDRS() {
    echo; echo "----------------------------------------------";
    printf "%-30s %s\n" "VM Name" "IP Address";
#    virsh -c qemu:///system list --all | grep -o '[0-9]* [a-z]*.*running' | while read -r line;
# DEBUG: The sed line breaks when the vmcnt goes double digit, like this
#        echo " 12    centos72_1                     running" | sed ...
    virsh list --all | grep -o '[0-9]* [a-z]*.*running' | while read -r line;
    do
        line_cropped=$(echo "$line" | sed 's/[0-9][ ]*\([-._0-9a-zA-Z]*\)[ ]*running/\1/' );
        printf "%-30s %s\n" "$line_cropped" $( virt_ADDR "$line_cropped" );
    done;
    echo "----------------------------------------------";
}

#----------------------------------------------------------------------------
# virt_UUID
#   returns UUID of a single kvm guest, arg=domainname
# Usage: 
#   $ virt_UUID vm-name
#   NOT SURE 
#
virt_UUID() {
    VM="$1"
    uuid=$(echo $2 | grep "<uuid" | sed "s/.*<uuid>\(.*\)<\/uuid>.*/\1/g" );
    echo $uuid
}

#----------------------------------------------------------------------------
# virt_MEM
#   returns IPaddr of a single kvm guest, arg=domainname
# Usage: 
#   $ virt_MEM vm-name
#   8mb
#
virt_MEM() {
    VM="$1"
    mem=$(echo $2 | grep "<memory" | sed "s/.*<memory unit='KiB'>\(.*\)<\/memory>.*/\1/g" );
    echo "$( expr $mem / 1024 )mb"
}

virt_CURRMEM() {
    VM="$1"
    mem=$(echo $2 | grep "<currentMemory" | sed "s/.*<currentMemory unit='KiB'>\(.*\)<\/currentMemory>.*/\1/g" );
    echo "$( expr $mem / 1024 )mb"
}

virt_VCPU() {
    VM="$1"
    vcpu=$(echo $2 | grep "<vcpu" | sed "s/.*<vcpu[^>]*>\(.*\)<\/vcpu>.*/\1/g" );
    echo $vcpu
}

virt_store() {
    VM="$1"

}

virt_INFO() {
    echo "------------------------------------------------------------------------------------------------------------------------";
    printf "%-30s%-17s%-12s%-12s%-8s%-40s\n" "VM Name" "IP Address" "Memory" "Current" "VCPUs" "UUID";
#    virsh -c qemu:///system list --all | grep -o -E '[-]?[0-9]* [-._0-9a-zA-Z]+.*(running|shut off)' | while read -r line;
    virsh list --all | grep -o -E '[-]?[0-9]* [-._0-9a-zA-Z]+.*(running|shut off)' | while read -r line;
    do
        line_cropped=$(echo "$line" | sed -r 's/([-]|[0-9]+)[ ]+([-._0-9a-zA-Z]*)[ ]+(running|shut off)/\2/' );
        vmsource=$(virsh dumpxml $line_cropped)
        printf "%-30s%-17s%-12s%-12s%-8s%-40s\n" "$line_cropped" $( virt_ADDR "$line_cropped" "$vmsource" ) $( virt_MEM "$line_cropped" "$vmsource" ) $( virt_CURRMEM "$line_cropped" "$vmsource" ) $( virt_VCPU "$line_cropped" "$vmsource" ) $( virt_UUID "$line_cropped" "$vmsource" );
    done;
    echo "------------------------------------------------------------------------------------------------------------------------";
}

