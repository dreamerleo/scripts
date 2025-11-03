#!/bin/bash

#############################################
# Скрипт автоматической установки VM для Local AI
# Запускать на хосте Proxmox
#############################################

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция вывода
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Конфигурация VM
VM_ID=${VM_ID:-200}
VM_NAME=${VM_NAME:-"local-ai"}
VM_CORES=${VM_CORES:-8}
VM_MEMORY=${VM_MEMORY:-16384}  # MB
VM_DISK_SIZE=${VM_DISK_SIZE:-100}  # GB
VM_STORAGE=${VM_STORAGE:-"local-lvm"}
VM_BRIDGE=${VM_BRIDGE:-"vmbr0"}
VM_ISO_STORAGE=${VM_ISO_STORAGE:-"local"}
UBUNTU_VERSION="22.04"
USE_GPU=${USE_GPU:-false}
GPU_ID=${GPU_ID:-"0000:01:00"}  # Замените на ваш GPU ID

# Проверка, что скрипт запущен на Proxmox
if ! command -v qm &> /dev/null; then
    print_error "Этот скрипт должен быть запущен на хосте Proxmox"
    exit 1
fi

print_info "==================================================="
print_info "Автоматическая установка VM для Local AI"
print_info "==================================================="
print_info "VM ID: $VM_ID"
print_info "VM Name: $VM_NAME"
print_info "Cores: $VM_CORES"
print_info "Memory: ${VM_MEMORY}MB"
print_info "Disk: ${VM_DISK_SIZE}GB"
print_info "Storage: $VM_STORAGE"
print_info "Use GPU: $USE_GPU"
print_info "==================================================="

# Запрос подтверждения
read -p "Продолжить установку? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warn "Установка отменена"
    exit 0
fi

# Проверка существования VM
if qm status $VM_ID &> /dev/null; then
    print_error "VM с ID $VM_ID уже существует!"
    read -p "Удалить существующую VM? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Удаление VM $VM_ID..."
        qm stop $VM_ID || true
        sleep 2
        qm destroy $VM_ID
    else
        exit 1
    fi
fi

# Проверка и скачивание Ubuntu Cloud Image
print_info "Проверка наличия Ubuntu Cloud Image..."
ISO_NAME="ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
ISO_PATH="/var/lib/vz/template/iso/${ISO_NAME}"

if [ ! -f "$ISO_PATH" ]; then
    print_info "Скачивание Ubuntu ${UBUNTU_VERSION} Cloud Image..."
    cd /var/lib/vz/template/iso/
    wget -q --show-progress "https://cloud-images.ubuntu.com/releases/${UBUNTU_VERSION}/release/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
else
    print_info "Ubuntu Cloud Image уже скачан"
fi

# Создание VM
print_info "Создание VM..."
qm create $VM_ID \
    --name $VM_NAME \
    --memory $VM_MEMORY \
    --cores $VM_CORES \
    --net0 virtio,bridge=$VM_BRIDGE \
    --scsihw virtio-scsi-pci

# Импорт диска
print_info "Импорт диска..."
qm importdisk $VM_ID "$ISO_PATH" $VM_STORAGE

# Настройка диска
print_info "Настройка дисков..."
qm set $VM_ID \
    --scsi0 ${VM_STORAGE}:vm-${VM_ID}-disk-0 \
    --boot order=scsi0 \
    --ide2 ${VM_STORAGE}:cloudinit \
    --serial0 socket \
    --vga serial0

# Изменение размера диска
print_info "Увеличение размера диска до ${VM_DISK_SIZE}GB..."
qm resize $VM_ID scsi0 ${VM_DISK_SIZE}G

# Создание Cloud-Init конфигурации
print_info "Настройка Cloud-Init..."

# Генерация SSH ключа если не существует
if [ ! -f /root/.ssh/id_rsa.pub ]; then
    print_info "Генерация SSH ключа..."
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ""
fi

SSH_KEY=$(cat /root/.ssh/id_rsa.pub)

# Настройка Cloud-Init
qm set $VM_ID \
    --ciuser root \
    --cipassword "ChangeMe123!" \
    --sshkeys /root/.ssh/id_rsa.pub \
    --ipconfig0 ip=dhcp

# Настройка CPU
print_info "Настройка CPU..."
qm set $VM_ID --cpu host

# Настройка GPU passthrough если требуется
if [ "$USE_GPU" = true ]; then
    print_info "Настройка GPU Passthrough..."
    qm set $VM_ID --hostpci0 $GPU_ID,pcie=1,rombar=0
fi

# Создание скрипта первоначальной настройки
print_info "Создание скрипта настройки..."
cat > /tmp/setup-local-ai.sh << 'SETUP_SCRIPT'
#!/bin/bash

set -e

# Цвета
GREEN='\033[0;32m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_info "Начало настройки Local AI..."

# Обновление системы
print_info "Обновление системы..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Установка базовых пакетов
print_info "Установка базовых пакетов..."
apt-get install -y \
    git \
    curl \
    wget \
    vim \
    htop \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    build-essential

# Установка Docker
print_info "Установка Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Настройка Docker
print_info "Настройка Docker..."
systemctl enable docker
systemctl start docker

# Проверка наличия GPU
if lspci | grep -i nvidia > /dev/null; then
    print_info "Обнаружена NVIDIA GPU, установка драйверов..."
    
    # Установка драйверов NVIDIA
    apt-get install -y ubuntu-drivers-common
    ubuntu-drivers autoinstall
    
    # Установка NVIDIA Container Toolkit
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    apt-get update
    apt-get install -y nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
fi

# Клонирование Local AI Packaged
print_info "Клонирование Local AI Packaged..."
mkdir -p /opt/local-ai
cd /opt/local-ai
git clone https://github.com/coleam00/local-ai-packaged.git .

# Создание .env файла
print_info "Создание конфигурации..."
cat > /opt/local-ai/.env << 'EOF'
OLLAMA_HOST=0.0.0.0:11434
WEBUI_PORT=3000
OPEN_WEBUI_PORT=8080
OLLAMA_MODELS_DIR=./models
OLLAMA_MAX_LOADED_MODELS=1
OLLAMA_NUM_PARALLEL=1
EOF

# Проверка наличия GPU для конфигурации
if lspci | grep -i nvidia > /dev/null; then
    echo "OLLAMA_GPU_ENABLED=true" >> /opt/local-ai/.env
    echo "OLLAMA_NUM_GPU=1" >> /opt/local-ai/.env
fi

# Создание директорий
mkdir -p /opt/local-ai/models
mkdir -p /opt/local-ai/data

# Создание systemd сервиса
print_info "Создание systemd сервиса..."
cat > /etc/systemd/system/local-ai.service << 'SVCEOF'
[Unit]
Description=Local AI Packaged
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/local-ai
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable local-ai.service

# Настройка файрвола
print_info "Настройка файрвола..."
ufw --force enable
ufw allow 22/tcp
ufw allow 8080/tcp
ufw allow 11434/tcp
ufw allow 3000/tcp

# Запуск Local AI
print_info "Запуск Local AI..."
cd /opt/local-ai
docker compose pull
docker compose up -d

# Создание скрипта управления
cat > /usr/local/bin/local-ai << 'MGMTEOF'
#!/bin/bash

case "$1" in
    start)
        cd /opt/local-ai && docker compose up -d
        ;;
    stop)
        cd /opt/local-ai && docker compose down
        ;;
    restart)
        cd /opt/local-ai && docker compose restart
        ;;
    logs)
        cd /opt/local-ai && docker compose logs -f
        ;;
    status)
        cd /opt/local-ai && docker compose ps
        ;;
    update)
        cd /opt/local-ai
        git pull
        docker compose pull
        docker compose up -d --build
        ;;
    *)
        echo "Использование: local-ai {start|stop|restart|logs|status|update}"
        exit 1
        ;;
esac
MGMTEOF

chmod +x /usr/local/bin/local-ai

# Вывод информации
VM_IP=$(hostname -I | awk '{print $1}')

print_info "=================================================="
print_info "Установка завершена!"
print_info "=================================================="
print_info "IP адрес: $VM_IP"
print_info "Open WebUI: http://$VM_IP:8080"
print_info "Ollama API: http://$VM_IP:11434"
print_info ""
print_info "Управление:"
print_info "  local-ai start   - Запустить"
print_info "  local-ai stop    - Остановить"
print_info "  local-ai restart - Перезапустить"
print_info "  local-ai logs    - Просмотр логов"
print_info "  local-ai status  - Статус"
print_info "  local-ai update  - Обновление"
print_info "=================================================="

# Создание файла с информацией
cat > /root/local-ai-info.txt << INFOEOF
Local AI Installation Info
==========================
IP Address: $VM_IP
Open WebUI: http://$VM_IP:8080
Ollama API: http://$VM_IP:11434

Default Password: ChangeMe123!
Please change it after first login!

Management Commands:
  local-ai start|stop|restart|logs|status|update

Installation Directory: /opt/local-ai
INFOEOF

print_info "Информация сохранена в /root/local-ai-info.txt"

SETUP_SCRIPT

# Копирование скрипта в VM через Cloud-Init
print_info "Подготовка скрипта автозапуска..."
qm set $VM_ID --cicustom "user=local:snippets/local-ai-setup.yml"

# Создание Cloud-Init конфигурации
mkdir -p /var/lib/vz/snippets
cat > /var/lib/vz/snippets/local-ai-setup.yml << 'CLOUDINIT'
#cloud-config
hostname: local-ai
manage_etc_hosts: true
package_upgrade: true
timezone: Europe/Moscow

runcmd:
  - |
    cat > /tmp/setup.sh << 'INNERSCRIPT'
INNERSCRIPT

cat /tmp/setup-local-ai.sh >> /var/lib/vz/snippets/local-ai-setup.yml

cat >> /var/lib/vz/snippets/local-ai-setup.yml << 'CLOUDINIT2'
INNERSCRIPT
  - chmod +x /tmp/setup.sh
  - /tmp/setup.sh > /var/log/local-ai-setup.log 2>&1
  - rm /tmp/setup.sh

final_message: "Local AI setup completed after $UPTIME seconds"
CLOUDINIT2

# Запуск VM
print_info "Запуск VM..."
qm start $VM_ID

print_info "Ожидание запуска VM (30 секунд)..."
sleep 30

# Получение IP адреса
print_info "Получение IP адреса..."
VM_IP=""
for i in {1..20}; do
    VM_IP=$(qm guest exec $VM_ID -- hostname -I 2>/dev/null | awk '{print $1}' || echo "")
    if [ -n "$VM_IP" ]; then
        break
    fi
    sleep 5
done

print_info "==================================================="
print_info "VM успешно создана и запущена!"
print_info "==================================================="
print_info "VM ID: $VM_ID"
print_info "VM Name: $VM_NAME"
if [ -n "$VM_IP" ]; then
    print_info "IP Address: $VM_IP"
    print_info "Open WebUI: http://$VM_IP:8080"
    print_info "Ollama API: http://$VM_IP:11434"
else
    print_warn "IP адрес еще не получен, подождите несколько минут"
    print_info "Используйте: qm guest exec $VM_ID -- hostname -I"
fi
print_info ""
print_info "SSH подключение: ssh root@$VM_IP"
print_info "Пароль по умолчанию: ChangeMe123!"
print_info ""
print_info "Установка Local AI занимает 10-15 минут"
print_info "Прогресс можно отслеживать:"
print_info "  ssh root@$VM_IP 'tail -f /var/log/local-ai-setup.log'"
print_info "==================================================="

# Сохранение информации
cat > /root/local-ai-vm-info.txt << EOF
Local AI VM Information
=======================
VM ID: $VM_ID
VM Name: $VM_NAME
IP Address: $VM_IP
SSH: ssh root@$VM_IP
Default Password: ChangeMe123!

Open WebUI: http://$VM_IP:8080
Ollama API: http://$VM_IP:11434

Created: $(date)
EOF

print_info "Информация сохранена в /root/local-ai-vm-info.txt"
