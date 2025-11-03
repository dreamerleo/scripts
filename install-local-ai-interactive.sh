#!/bin/bash

#############################################
# Интерактивная установка VM для Local AI
#############################################

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Local AI VM - Интерактивная установка     ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo ""

# Проверка Proxmox
if ! command -v qm &> /dev/null; then
    echo "Ошибка: Этот скрипт должен быть запущен на хосте Proxmox"
    exit 1
fi

# Функция запроса значения
ask() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    read -p "$prompt [$default]: " value
    eval $var_name="${value:-$default}"
}

# Получение списка storage
echo "Доступные хранилища:"
pvesm status | tail -n +2 | awk '{print "  - " $1}'
echo ""

# Запрос параметров
ask "VM ID" "200" VM_ID
ask "Имя VM" "local-ai" VM_NAME
ask "Количество ядер CPU" "8" VM_CORES
ask "Объем RAM (MB)" "16384" VM_MEMORY
ask "Размер диска (GB)" "100" VM_DISK_SIZE
ask "Хранилище" "local-lvm" VM_STORAGE
ask "Сетевой мост" "vmbr0" VM_BRIDGE

echo ""
read -p "Использовать GPU passthrough? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    USE_GPU=true
    echo "Доступные GPU:"
    lspci | grep -i vga
    lspci | grep -i nvidia
    echo ""
    ask "PCI ID GPU (например: 0000:01:00)" "0000:01:00" GPU_ID
else
    USE_GPU=false
fi

echo ""
echo -e "${GREEN}Конфигурация:${NC}"
echo "  VM ID: $VM_ID"
echo "  Имя: $VM_NAME"
echo "  CPU: $VM_CORES ядер"
echo "  RAM: $VM_MEMORY MB"
echo "  Диск: $VM_DISK_SIZE GB"
echo "  Хранилище: $VM_STORAGE"
echo "  GPU: $USE_GPU"
echo ""

read -p "Продолжить? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Установка отменена"
    exit 0
fi

# Экспорт переменных и запуск основного скрипта
export VM_ID VM_NAME VM_CORES VM_MEMORY VM_DISK_SIZE VM_STORAGE VM_BRIDGE USE_GPU GPU_ID

# Здесь можно вызвать основной скрипт или выполнить установку
bash install-local-ai-vm.sh
