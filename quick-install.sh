#!/bin/bash

# Быстрая установка с параметрами по умолчанию
# Использование: ./quick-install.sh [VM_ID]

VM_ID=${1:-200}

export VM_ID=$VM_ID
export VM_NAME="local-ai-$VM_ID"
export VM_CORES=8
export VM_MEMORY=16384
export VM_DISK_SIZE=100
export VM_STORAGE="local-lvm"
export VM_BRIDGE="vmbr0"
export USE_GPU=false

echo "Быстрая установка Local AI VM"
echo "VM ID: $VM_ID"
echo ""
read -p "Продолжить? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash install-local-ai-vm.sh
fi
