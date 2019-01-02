#!/bin/bash
sed -i -- "s/region_placeholder/${AWS_DEFAULT_REGION}/g" inventory/ec2.ini
ansible-inventory -i inventory/ec2.py --list tag_kitchen_type_windows --export -y > ./inventory/hosts
echo "Ansible hosts updated successfully"