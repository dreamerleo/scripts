#!/bin/bash

VM_ID=${1:-200}

echo "Проверка статуса VM $VM_ID..."
echo ""

# Проверка статуса VM
if qm status $VM_ID &> /dev/null; then
    STATUS=$(qm status $VM_ID | awk '{print $2}')
    echo "Статус VM: $STATUS"
    
    if [ "$STATUS" = "running" ]; then
        # Получение IP
        VM_IP=$(qm guest exec $VM_ID -- hostname -I 2>/dev/null | awk '{print $1}' || echo "Недоступен")
        echo "IP адрес: $VM_IP"
        
        # Проверка процесса установки
        echo ""
        echo "Лог установки:"
        qm guest exec $VM_ID -- tail -n 20 /var/log/local-ai-setup.log 2>/dev/null || echo "Лог еще недоступен"
        
        # Проверка Docker
        echo ""
        echo "Статус Docker контейнеров:"
        qm guest exec $VM_ID -- docker ps 2>/dev/null || echo "Docker еще не установлен"
        
        # Проверка доступности сервисов
        if [ "$VM_IP" != "Недоступен" ]; then
            echo ""
            echo "Проверка доступности сервисов:"
            curl -s http://$VM_IP:8080 > /dev/null && echo "  Open WebUI: ✓" || echo "  Open WebUI: ✗"
            curl -s http://$VM_IP:11434/api/tags > /dev/null && echo "  Ollama API: ✓" || echo "  Ollama API: ✗"
        fi
    fi
else
    echo "VM с ID $VM_ID не найдена"
fi
