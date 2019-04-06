#!/bin/bash

if ([[ -z $1 ]] || [[ $1 == "help" ]] || [[ $1 == "--help" ]] || [[ $1 == "-h" ]]); then
  echo "Must pass the disk labels as an string argument with spaces"
  echo "Exmaple: ./wipe-ceph-disks.sh \"b c d e\""
  exit 1
fi

read -p "Are you sure you wish to proceed format disks $1?" input
case $input in
    [Yy]*)
        for disk in $@; do
           sudo parted -s /dev/sd$disk mklabel gpt
        done
        sudo rm -rf /var/lib/openstack-helm/ceph
        sudo rm -rf /var/lib/ceph/journal/*
        ;;
     *)
        echo Exitting.
        exit 1
esac

