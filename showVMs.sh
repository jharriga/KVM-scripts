#!/bin/bash
#
# showVMs.sh
#
# List to stdout table of KVM guests and info on them
#	- VM Name
#	- IP Address
#	- Memory
#	- VCPUs
#	- State (running OR shutoff)
#############################################################################

FUNCTIONS="./virtFunctions.sh"

# Bring in the VIRT functions 
if [ ! -e $FUNCTIONS ]; then
  echo "cannot find functions file ${FUNCTIONS}"
  exit 1
fi

source $FUNCTIONS

#--------------------------------------------------------------------
# FUNCTION: showInventory()
#
showInventory() {
echo "-----------------------------------------------------------------";
printf "%-20s%-17s%-12s%-8s%-30s\n" "VM Name" "IP Address" "Memory" "VCPUs" "State";
#    virsh -c qemu:///system list --all | grep -o -E '[-]?[0-9]* [-._0-9a-zA-Z]+.*(running|shut off)' | while read -r line;
virsh list --all | grep -o -E '[-]?[0-9]* [-._0-9a-zA-Z]+.*(running|shut off)' | while read -r line;
  do
    line_cropped=$(echo "$line" | sed -r 's/([-]|[0-9]+)[ ]+([-._0-9a-zA-Z]*)[ ]+(running|shut off)/\2/' );
    state=$(echo "$line" | awk '{if ($3 == "shut") {print $3 $4} else print $3}' );
    vmsource=$(virsh dumpxml $line_cropped)
    printf "%-20s%-17s%-12s%-8s%-30s\n" "$line_cropped" $( virt_ADDR "$line_cropped" "$vmsource" ) $( virt_MEM "$line_cropped" "$vmsource" ) $( virt_VCPU "$line_cropped" "$vmsource" ) "${state}";
  done;
echo "-----------------------------------------------------------------";
}

#####################################################################
# MAIN
#
showInventory

virt_ADDRS

exit 0


