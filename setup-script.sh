#!/bin/bash

# Script pour configurer le projet MicroK8s Stress Test simplifié
# Ce script crée tous les fichiers nécessaires et configure l'environnement

set -e  # Arrêter en cas d'erreur

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Répertoire de base
BASE_DIR=$(pwd)/microk8s-stress-test

echo -e "${YELLOW}Création des répertoires de base dans ${BASE_DIR}...${NC}"
mkdir -p ${BASE_DIR}/alpine-lab
mkdir -p ${BASE_DIR}/observer

echo -e "${BLUE}Création des fichiers pour alpine-lab...${NC}"

# 1.1 Dockerfile pour alpine-lab
cat > ${BASE_DIR}/alpine-lab/Dockerfile << 'ENDFILE'
FROM alpine:latest

# Installation des outils de base et des outils de stress
RUN apk update && apk add --no-cache \
    stress-ng \
    curl \
    wget \
    htop \
    procps \
    bash \
    coreutils \
    util-linux \
    python3 \
    py3-pip \
    openssh \
    tmux

# Configuration SSH pour la surveillance à distance
RUN ssh-keygen -A && \
    echo "root:password" | chpasswd && \
    sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config && \
    sed -i "s/#PasswordAuthentication yes/PasswordAuthentication yes/" /etc/ssh/sshd_config

# Création d'un utilisateur non-root pour le hardening
RUN adduser -D -u 1000 stressuser && \
    echo "stressuser:password" | chpasswd

# Création d'un répertoire pour les scripts de stress
WORKDIR /stress-scripts

# Copie des scripts de stress
COPY stress-cpu.sh /stress-scripts/
COPY stress-memory.sh /stress-scripts/
COPY stress-io.sh /stress-scripts/
COPY stress-network.sh /stress-scripts/
COPY stress-all.sh /stress-scripts/

# Rendre les scripts exécutables
RUN chmod +x /stress-scripts/*.sh

# Changer la propriété des scripts pour l'utilisateur non-root
RUN chown -R stressuser:stressuser /stress-scripts

# Exposition du port pour le SSH
EXPOSE 22

# Script de démarrage modifié pour lancer SSH et maintenir le conteneur actif
COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/alpine-lab/Dockerfile${NC}"

# 1.2 start.sh pour alpine-lab
cat > ${BASE_DIR}/alpine-lab/start.sh << 'ENDFILE'
#!/bin/sh
# Démarrer le service SSH
/usr/sbin/sshd

# Garder le conteneur en vie
tail -f /dev/null
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/alpine-lab/start.sh${NC}"

# 1.3 stress-cpu.sh
cat > ${BASE_DIR}/alpine-lab/stress-cpu.sh << 'ENDFILE'
#!/bin/bash

echo "Démarrage du stress test CPU..."
echo "Utilisation de stress-ng pour stresser tous les CPU disponibles"

# Détermine le nombre de CPU
NUM_CPU=$(nproc)
echo "Nombre de CPU détectés: $NUM_CPU"

# Stress CPU
stress-ng --cpu $NUM_CPU --cpu-method all --timeout 300s --metrics-brief

echo "Test de stress CPU terminé."
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/alpine-lab/stress-cpu.sh${NC}"

# 1.4 stress-memory.sh
cat > ${BASE_DIR}/alpine-lab/stress-memory.sh << 'ENDFILE'
#!/bin/bash

echo "Démarrage du stress test mémoire..."

# Récupération de la mémoire totale en MB
TOTAL_MEM=$(free -m | grep Mem | awk '{print $2}')
echo "Mémoire totale détectée: $TOTAL_MEM MB"

# Calcule 80% de la mémoire disponible
STRESS_MEM=$((TOTAL_MEM * 80 / 100))
echo "Stressage de $STRESS_MEM MB de mémoire (80% du total)"

# Stress mémoire
stress-ng --vm 2 --vm-bytes ${STRESS_MEM}M --vm-keep --timeout 300s --metrics-brief

echo "Test de stress mémoire terminé."
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/alpine-lab/stress-memory.sh${NC}"

# 1.5 stress-io.sh
cat > ${BASE_DIR}/alpine-lab/stress-io.sh << 'ENDFILE'
#!/bin/bash

echo "Démarrage du stress test I/O..."

# Création d'un répertoire temporaire pour les tests I/O
mkdir -p /tmp/stress-io-test

# Stress I/O avec 4 workers et 2GB d'écritures par worker
stress-ng --io 4 --hdd 2 --hdd-bytes 2G --timeout 300s --metrics-brief

# Nettoyage
rm -rf /tmp/stress-io-test

echo "Test de stress I/O terminé."
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/alpine-lab/stress-io.sh${NC}"

# 1.6 stress-network.sh
cat > ${BASE_DIR}/alpine-lab/stress-network.sh << 'ENDFILE'
#!/bin/bash

echo "Démarrage du stress test réseau..."

# Génération de trafic réseau
for i in {1..1000}; do
  curl -s https://www.google.com > /dev/null &
  if [ $((i % 50)) -eq 0 ]; then
    echo "Requêtes réseau générées: $i"
    sleep 1
  fi
done

# On attend que tous les processus curl se terminent
wait

echo "Test de stress réseau terminé."
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/alpine-lab/stress-network.sh${NC}"

# 1.7 stress-all.sh
cat > ${BASE_DIR}/alpine-lab/stress-all.sh << 'ENDFILE'
#!/bin/bash

echo "Démarrage du stress test combiné (CPU, mémoire, I/O, réseau)..."

# Détermine le nombre de CPU
NUM_CPU=$(nproc)
echo "Nombre de CPU détectés: $NUM_CPU"

# Récupération de la mémoire totale en MB
TOTAL_MEM=$(free -m | grep Mem | awk '{print $2}')
echo "Mémoire totale détectée: $TOTAL_MEM MB"

# Calcule 70% de la mémoire disponible pour le stress
STRESS_MEM=$((TOTAL_MEM * 70 / 100))
echo "Stressage de $STRESS_MEM MB de mémoire (70% du total)"

# Stress combiné
stress-ng --cpu $NUM_CPU --cpu-method all \
          --vm 2 --vm-bytes ${STRESS_MEM}M --vm-keep \
          --io 2 --hdd 1 --hdd-bytes 1G \
          --timeout 600s --metrics-brief &

# ID du processus stress-ng
STRESS_PID=$!

# Génération de trafic réseau en parallèle
for i in {1..500}; do
  curl -s https://www.google.com > /dev/null &
  if [ $((i % 50)) -eq 0 ]; then
    echo "Requêtes réseau générées: $i"
    sleep 2
  fi
done

# Attente que le stress-ng se termine
wait $STRESS_PID

echo "Test de stress combiné terminé."
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/alpine-lab/stress-all.sh${NC}"

echo -e "${BLUE}Création des fichiers pour observer...${NC}"

# 2.1 Dockerfile pour observer
cat > ${BASE_DIR}/observer/Dockerfile << 'ENDFILE'
FROM ubuntu:latest

# Installation des outils de base et htop
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    htop \
    net-tools \
    python3 \
    python3-pip \
    vim \
    jq \
    dnsutils \
    iputils-ping \
    iproute2 \
    openssh-client \
    sshpass \
    tmux \
    kubectl

# Installation des dépendances Python pour les scripts d'observation
RUN pip3 install --break-system-packages kubernetes

# Création d'un utilisateur non-root pour le hardening
RUN useradd -m -u 1000 obsuser

# Création d'un répertoire pour les scripts de monitoring
WORKDIR /monitoring-scripts

# Copier les scripts de monitoring
COPY monitor-htop.sh /monitoring-scripts/
COPY remote-monitor.py /monitoring-scripts/

# Rendre les scripts exécutables
RUN chmod +x /monitoring-scripts/*.sh
RUN chmod +x /monitoring-scripts/*.py

# Changer la propriété des scripts pour l'utilisateur non-root
RUN chown -R obsuser:obsuser /monitoring-scripts

# Commande par défaut (maintenir le conteneur actif)
CMD ["tail", "-f", "/dev/null"]
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/observer/Dockerfile${NC}"

# 2.2 monitor-htop.sh
cat > ${BASE_DIR}/observer/monitor-htop.sh << 'ENDFILE'
#!/bin/bash

# Script pour surveiller les performances de alpine-lab en utilisant htop
# Ce script doit être exécuté dans le pod observer

POD_NAME=$(kubectl get pods -n stress-test -l app=alpine-lab -o jsonpath="{.items[0].metadata.name}")
NAMESPACE="stress-test"

echo "Surveillance du pod alpine-lab ($POD_NAME) dans le namespace $NAMESPACE"

# Fonction pour afficher htop dans une session tmux en arrière-plan
monitor_with_htop() {
    # Créer une session tmux pour la surveillance continue
    tmux new-session -d -s monitor "kubectl exec -n $NAMESPACE $POD_NAME -- htop -d 5"
    echo "Session de surveillance htop démarrée en arrière-plan"
    echo "Pour vous y attacher: tmux attach -t monitor"
}

# Fonction pour capturer un instantané des métriques
capture_metrics_snapshot() {
    echo "Capture d'un instantané des métriques à $(date)"
    
    echo "== CPU et charge =="
    kubectl exec -n $NAMESPACE $POD_NAME -- top -b -n 1 | head -20
    
    echo "== Mémoire =="
    kubectl exec -n $NAMESPACE $POD_NAME -- free -m
    
    echo "== Espace disque =="
    kubectl exec -n $NAMESPACE $POD_NAME -- df -h
    
    echo "== Processus les plus gourmands =="
    kubectl exec -n $NAMESPACE $POD_NAME -- ps aux --sort=-%cpu | head -10
    
    echo "== Instantané htop =="
    kubectl exec -n $NAMESPACE $POD_NAME -- top -b -n 1 -o PID,USER,%CPU,%MEM,TIME,COMMAND | head -20
    
    echo "Instantané complet enregistré dans /tmp/metrics_$(date +%Y%m%d_%H%M%S).log"
    
    # Enregistrer les métriques dans un fichier pour référence
    (
        echo "=== RAPPORT DE MÉTRIQUES POUR $POD_NAME À $(date) ==="
        echo ""
        echo "== CPU et charge =="
        kubectl exec -n $NAMESPACE $POD_NAME -- top -b -n 1 | head -20
        echo ""
        echo "== Mémoire =="
        kubectl exec -n $NAMESPACE $POD_NAME -- free -m
        echo ""
        echo "== Espace disque =="
        kubectl exec -n $NAMESPACE $POD_NAME -- df -h
        echo ""
        echo "== Processus les plus gourmands =="
        kubectl exec -n $NAMESPACE $POD_NAME -- ps aux --sort=-%cpu | head -10
        echo ""
        echo "== Instantané htop =="
        kubectl exec -n $NAMESPACE $POD_NAME -- top -b -n 1 -o PID,USER,%CPU,%MEM,TIME,COMMAND | head -20
    ) > "/tmp/metrics_$(date +%Y%m%d_%H%M%S).log"
}

# Fonction pour surveillance continue avec intervalles réguliers
continuous_monitoring() {
    interval=$1
    duration=$2
    count=$((duration / interval))
    
    echo "Surveillance continue pendant $duration secondes (toutes les $interval secondes)"
    
    for ((i=1; i<=$count; i++)); do
        capture_metrics_snapshot
        echo "Instantané $i/$count - Attente de $interval secondes..."
        sleep $interval
    done
    
    echo "Surveillance terminée!"
}

# Menu principal
echo "Options de surveillance:"
echo "1. Surveillance htop en arrière-plan (tmux)"
echo "2. Capture d'un instantané des métriques"
echo "3. Surveillance continue à intervalles réguliers"
echo "4. Exécuter stress-cpu.sh et surveiller"
echo "5. Exécuter stress-memory.sh et surveiller"
echo "6. Exécuter stress-io.sh et surveiller"
echo "7. Exécuter stress-network.sh et surveiller"
echo "8. Exécuter stress-all.sh et surveiller"
echo "9. Quitter"

read -p "Entrez votre choix: " choice

case $choice in
    1)
        monitor_with_htop
        ;;
    2)
        capture_metrics_snapshot
        ;;
    3)
        read -p "Intervalle entre les captures (secondes): " interval
        read -p "Durée totale de surveillance (secondes): " duration
        continuous_monitoring $interval $duration
        ;;
    4)
        echo "Exécution de stress-cpu.sh et surveillance..."
        kubectl exec -n $NAMESPACE $POD_NAME -- /stress-scripts/stress-cpu.sh &
        continuous_monitoring 10 320
        ;;
    5)
        echo "Exécution de stress-memory.sh et surveillance..."
        kubectl exec -n $NAMESPACE $POD_NAME -- /stress-scripts/stress-memory.sh &
        continuous_monitoring 10 320
        ;;
    6)
        echo "Exécution de stress-io.sh et surveillance..."
        kubectl exec -n $NAMESPACE $POD_NAME -- /stress-scripts/stress-io.sh &
        continuous_monitoring 10 320
        ;;
    7)
        echo "Exécution de stress-network.sh et surveillance..."
        kubectl exec -n $NAMESPACE $POD_NAME -- /stress-scripts/stress-network.sh &
        continuous_monitoring 10 320
        ;;
    8)
        echo "Exécution de stress-all.sh et surveillance..."
        kubectl exec -n $NAMESPACE $POD_NAME -- /stress-scripts/stress-all.sh &
        continuous_monitoring 10 620
        ;;
    9)
        echo "Au revoir!"
        exit 0
        ;;
    *)
        echo "Choix invalide!"
        ;;
esac
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/observer/monitor-htop.sh${NC}"

# 2.3 remote-monitor.py
cat > ${BASE_DIR}/observer/remote-monitor.py << 'ENDFILE'
#!/usr/bin/env python3

import time
import subprocess
import json
import os
from datetime import datetime
from kubernetes import client, config

# Configuration pour accéder à l'API Kubernetes
try:
    config.load_incluster_config()  # Quand le script est exécuté dans un Pod
except:
    config.load_kube_config()  # Pour les tests locaux

v1 = client.CoreV1Api()

# Fonction pour récupérer les informations du Pod via l'API Kubernetes
def get_pod_info(pod_name_prefix="alpine-lab"):
    try:
        pods = v1.list_pod_for_all_namespaces(watch=False)
        lab_pods = [pod for pod in pods.items if pod.metadata.name.startswith(pod_name_prefix)]
        
        pod_info = []
        for pod in lab_pods:
            pod_data = {
                "name": pod.metadata.name,
                "namespace": pod.metadata.namespace,
                "status": pod.status.phase,
                "host_ip": pod.status.host_ip,
                "pod_ip": pod.status.pod_ip,
                "creation_timestamp": pod.metadata.creation_timestamp.isoformat(),
                "containers": []
            }
            
            for container in pod.spec.containers:
                container_data = {
                    "name": container.name,
                    "image": container.image,
                    "resources": {}
                }
                
                if container.resources:
                    if container.resources.limits:
                        container_data["resources"]["limits"] = container.resources.limits
                    if container.resources.requests:
                        container_data["resources"]["requests"] = container.resources.requests
                
                pod_data["containers"].append(container_data)
            
            pod_info.append(pod_data)
        
        return pod_info
    except Exception as e:
        print(f"Erreur lors de la récupération des informations du Pod: {e}")
        return None

# Fonction pour exécuter une commande dans le pod cible
def execute_command_in_pod(pod_name, namespace, command):
    try:
        cmd = ["kubectl", "exec", "-n", namespace, pod_name, "--", "sh", "-c", command]
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.stdout.strip()
    except Exception as e:
        print(f"Erreur lors de l'exécution de la commande '{command}': {e}")
        return None

# Fonction pour collecter des métriques système
def collect_metrics(pod_name, namespace):
    metrics = {
        "timestamp": datetime.now().isoformat(),
        "cpu": {},
        "memory": {},
        "disk": {},
        "processes": []
    }
    
    # Collecte des métriques CPU
    cpu_info = execute_command_in_pod(pod_name, namespace, "top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}'")
    if cpu_info:
        metrics["cpu"]["usage_percent"] = float(cpu_info)
    
    load_avg = execute_command_in_pod(pod_name, namespace, "cat /proc/loadavg")
    if load_avg:
        parts = load_avg.split()
        metrics["cpu"]["load_1min"] = float(parts[0])
        metrics["cpu"]["load_5min"] = float(parts[1])
        metrics["cpu"]["load_15min"] = float(parts[2])
    
    # Collecte des métriques mémoire
    mem_info = execute_command_in_pod(pod_name, namespace, "free -m | grep Mem:")
    if mem_info:
        parts = mem_info.split()
        metrics["memory"]["total_mb"] = int(parts[1])
        metrics["memory"]["used_mb"] = int(parts[2])
        metrics["memory"]["free_mb"] = int(parts[3])
        metrics["memory"]["usage_percent"] = (int(parts[2]) / int(parts[1])) * 100
    
    # Collecte des métriques disque
    disk_info = execute_command_in_pod(pod_name, namespace, "df -h / | tail -1")
    if disk_info:
        parts = disk_info.split()
        metrics["disk"]["filesystem"] = parts[0]
        metrics["disk"]["size"] = parts[1]
        metrics["disk"]["used"] = parts[2]
        metrics["disk"]["available"] = parts[3]
        metrics["disk"]["usage_percent"] = float(parts[4].replace("%", ""))
    
    # Collecte des processus consommant le plus de ressources
    top_processes = execute_command_in_pod(pod_name, namespace, "ps aux --sort=-%cpu | head -6")
    if top_processes:
        lines = top_processes.split('\n')
        header = lines[0]
        for line in lines[1:]:
            if line.strip():
                parts = line.split(None, 10)
                process = {
                    "user": parts[0],
                    "pid": int(parts[1]),
                    "cpu_percent": float(parts[2]),
                    "memory_percent": float(parts[3]),
                    "vsz": int(parts[4]),
                    "rss": int(parts[5]),
                    "command": parts[10] if len(parts) > 10 else ""
                }
                metrics["processes"].append(process)
    
    return metrics

# Fonction principale pour le monitoring
def monitor_alpine_lab(interval=30):
    print(f"Démarrage du monitoring avec un intervalle de {interval} secondes...")
    
    metrics_history = []
    
    try:
        while True:
            print(f"\n=== Collecte des données à {datetime.now().isoformat()} ===")
            
            # Récupérer les informations du Pod
            pod_info = get_pod_info()
            
            if not pod_info or not pod_info[0]:
                print("Aucun pod alpine-lab trouvé!")
                time.sleep(interval)
                continue
            
            pod = pod_info[0]
            pod_name = pod["name"]
            namespace = pod["namespace"]
            
            print(f"Monitoring du pod {pod_name} dans le namespace {namespace}")
            
            # Collecter les métriques
            metrics = collect_metrics(pod_name, namespace)
            metrics_history.append(metrics)
            
            # Afficher un résumé des métriques
            print(f"CPU: {metrics['cpu'].get('usage_percent', 'N/A')}%, Load: {metrics['cpu'].get('load_1min', 'N/A')}")
            print(f"Mémoire: {metrics['memory'].get('used_mb', 'N/A')}/{metrics['memory'].get('total_mb', 'N/A')} MB ({metrics['memory'].get('usage_percent', 'N/A'):.1f}%)")
            print(f"Disque: {metrics['disk'].get('used', 'N/A')}/{metrics['disk'].get('size', 'N/A')} ({metrics['disk'].get('usage_percent', 'N/A')}%)")
            
            print("\nProcessus les plus gourmands:")
            for process in metrics["processes"][:3]:
                print(f"  {process['pid']} ({process['user']}): CPU {process['cpu_percent']}%, MEM {process['memory_percent']}% - {process['command'][:50]}...")
            
            # Sauvegarder les métriques dans un fichier JSON
            if len(metrics_history) % 5 == 0:
                with open(f"/tmp/metrics_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json", "w") as f:
                    json.dump(metrics_history[-5:], f, indent=2)
                print(f"Métriques enregistrées dans /tmp/metrics_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json")
            
            time.sleep(interval)
    
    except KeyboardInterrupt:
        print("\nMonitoring interrompu par l'utilisateur.")
        
        # Sauvegarder toutes les métriques collectées
        with open(f"/tmp/all_metrics_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json", "w") as f:
            json.dump(metrics_history, f, indent=2)
        print(f"Toutes les métriques ont été enregistrées dans /tmp/all_metrics_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json")

if __name__ == "__main__":
    monitor_alpine_lab(interval=30)
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/observer/remote-monitor.py${NC}"

echo -e "${BLUE}Création des fichiers Kubernetes...${NC}"

# 3.1 rbac-config.yaml
cat > ${BASE_DIR}/rbac-config.yaml << 'ENDFILE'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: observer-account
  namespace: stress-test
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: observer-role
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/proxy", "services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: ["extensions"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["configmaps", "namespaces"]
  verbs: ["get"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods", "nodes"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: observer-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: observer-role
subjects:
- kind: ServiceAccount
  name: observer-account
  namespace: stress-test
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/rbac-config.yaml${NC}"

# 3.2 alpine-lab-deployment.yaml
cat > ${BASE_DIR}/alpine-lab-deployment.yaml << 'ENDFILE'
apiVersion: v1
kind: Namespace
metadata:
  name: stress-test
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alpine-lab
  namespace: stress-test
  labels:
    app: alpine-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alpine-lab
  template:
    metadata:
      labels:
        app: alpine-lab
    spec:
      containers:
      - name: alpine-lab
        image: localhost:32000/alpine-lab:latest
        imagePullPolicy: Always
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: false
          runAsNonRoot: true
          runAsUser: 1000
          capabilities:
            drop:
            - ALL
        resources:
          limits:
            cpu: "2"
            memory: "2Gi"
          requests:
            cpu: "500m"
            memory: "500Mi"
        ports:
        - containerPort: 22
          name: ssh
        volumeMounts:
        - name: stress-scripts-volume
          mountPath: /stress-scripts
        - name: tmp-volume
          mountPath: /tmp
      volumes:
      - name: stress-scripts-volume
        emptyDir: {}
      - name: tmp-volume
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: alpine-lab
  namespace: stress-test
spec:
  selector:
    app: alpine-lab
  ports:
  - port: 22
    targetPort: 22
    name: ssh
  type: ClusterIP
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/alpine-lab-deployment.yaml${NC}"

# 3.3 observer-deployment.yaml
cat > ${BASE_DIR}/observer-deployment.yaml << 'ENDFILE'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: observer
  namespace: stress-test
  labels:
    app: observer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: observer
  template:
    metadata:
      labels:
        app: observer
    spec:
      serviceAccountName: observer-account
      containers:
      - name: observer
        image: localhost:32000/observer:latest
        imagePullPolicy: Always
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: false
          runAsNonRoot: true
          runAsUser: 1000
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: monitoring-scripts-volume
          mountPath: /monitoring-scripts
        - name: tmp-volume
          mountPath: /tmp
        - name: kube-config
          mountPath: /var/run/secrets/kubernetes.io/serviceaccount
          readOnly: true
      volumes:
      - name: monitoring-scripts-volume
        emptyDir: {}
      - name: tmp-volume
        emptyDir: {}
      - name: kube-config
        projected:
          sources:
          - serviceAccountToken:
              expirationSeconds: 3600
              path: token
          - configMap:
              name: kube-root-ca.crt
              items:
              - key: ca.crt
                path: ca.crt
          - downwardAPI:
              items:
              - path: namespace
                fieldRef:
                  fieldPath: metadata.namespace
---
apiVersion: v1
kind: Service
metadata:
  name: observer
  namespace: stress-test
spec:
  selector:
    app: observer
  ports:
  - port: 22
    targetPort: 22
    name: ssh
  type: ClusterIP
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/observer-deployment.yaml${NC}"

# 3.4 README.md
cat > ${BASE_DIR}/README.md << 'ENDFILE'
# MicroK8s Stress Test avec Hardening

Ce projet fournit un environnement de test de stress pour MicroK8s, conçu pour évaluer les performances et la résilience d'un cluster Kubernetes tout en appliquant les meilleures pratiques de sécurité (hardening).

## Vue d'ensemble

L'architecture se compose de deux pods principaux déployés dans un namespace dédié:

1. **Pod alpine-lab**: Exécute différents tests de stress (CPU, mémoire, I/O, réseau)
2. **Pod observer**: Surveille les métriques de performance du pod alpine-lab en utilisant htop et des scripts personnalisés

Ces pods sont déployés avec des mesures de sécurité renforcées, notamment:
- Limites de ressources strictes
- Contextes de sécurité restreints
- Réduction des privilèges
- Contrôle d'accès basé sur les rôles (RBAC)

## Prérequis

- Un système Linux compatible avec snap
- Docker installé
- Droits administrateur pour installer et configurer les composants

## Installation et mise en place

### 1. Installation de MicroK8s

```bash
# Installation de MicroK8s
sudo snap install microk8s --classic

# Vérification de l'installation
microk8s status --wait-ready

# Activation des addons nécessaires
microk8s enable dns storage metrics-server rbac

# Configuration de l'alias kubectl pour simplifier les commandes
echo 'alias kubectl="microk8s kubectl"' >> ~/.bashrc
source ~/.bashrc
```

### 2. Construction et déploiement des images Docker

```bash
# Construction de l'image alpine-lab
cd ~/microk8s-stress-test/alpine-lab
docker build -t localhost:32000/alpine-lab:latest .
docker push localhost:32000/alpine-lab:latest

# Construction de l'image observer
cd ~/microk8s-stress-test/observer
docker build -t localhost:32000/observer:latest .
docker push localhost:32000/observer:latest
```

### 3. Déploiement dans Kubernetes

```bash
# Création du namespace
kubectl create namespace stress-test

# Application des configurations RBAC
kubectl apply -f ~/microk8s-stress-test/rbac-config.yaml

# Déploiement des applications
kubectl apply -f ~/microk8s-stress-test/alpine-lab-deployment.yaml
kubectl apply -f ~/microk8s-stress-test/observer-deployment.yaml

# Vérification des déploiements
kubectl get all -n stress-test
```

## Utilisation

### Exécution des tests de stress

```bash
# Obtention du nom du pod observer
POD_NAME=$(kubectl get pods -n stress-test -l app=observer -o jsonpath="{.items[0].metadata.name}")

# Accès au pod observer
kubectl exec -it -n stress-test $POD_NAME -- bash

# Exécution du script de monitoring
cd /monitoring-scripts
./monitor-htop.sh
```

Le script `monitor-htop.sh` offre plusieurs options:
1. Surveillance htop en arrière-plan
2. Capture d'un instantané des métriques
3. Surveillance continue à intervalles réguliers
4. Exécution des différents scripts de stress avec surveillance

### Analyse des résultats

Les résultats des tests sont enregistrés dans des fichiers de log:

```bash
# Visualiser les résultats
ls -la /tmp/metrics_*.log
cat /tmp/metrics_20250505_120000.log
```

Ces logs contiennent:
- L'utilisation CPU en pourcentage et la charge système
- L'utilisation de la mémoire (totale, utilisée, disponible)
- L'activité du disque
- Les processus consommant le plus de ressources

## Nettoyage

```bash
# Supprimer les déploiements
kubectl delete -f ~/microk8s-stress-test/observer-deployment.yaml
kubectl delete -f ~/microk8s-stress-test/alpine-lab-deployment.yaml
kubectl delete -f ~/microk8s-stress-test/rbac-config.yaml

# Supprimer le namespace
kubectl delete namespace stress-test
```

## Mesures de hardening implémentées

1. **Contextes de sécurité (SecurityContext)**:
   - Exécution en tant qu'utilisateur non-root
   - Désactivation de l'escalade de privilèges
   - Suppression de toutes les capacités Linux par défaut

2. **Limites de ressources**:
   - Limites strictes sur CPU et mémoire
   - Ressources minimales garanties

3. **RBAC (Contrôle d'accès basé sur les rôles)**:
   - ServiceAccount dédié avec permissions minimales
   - Application du principe du moindre privilège

4. **Isolation des ressources**:
   - Namespace dédié
   - Volumes temporaires isolés

Pour plus d'informations sur l'efficacité du hardening et les risques de ne pas l'implémenter, consultez le rapport complet fourni avec ce projet.
ENDFILE
echo -e "${GREEN}✓ Fichier créé: ${BASE_DIR}/README.md${NC}"

# Rendre les scripts exécutables
chmod +x ${BASE_DIR}/alpine-lab/*.sh
chmod +x ${BASE_DIR}/observer/*.sh
chmod +x ${BASE_DIR}/observer/*.py

echo -e "${GREEN}Configuration terminée!${NC}"
echo -e "Tous les fichiers nécessaires ont été créés dans ${BASE_DIR}"
echo -e "${YELLOW}Étapes suivantes:${NC}"
echo -e "1. Vérifier que MicroK8s est installé: ${BLUE}sudo snap install microk8s --classic${NC}"
echo -e "2. Activer les addons nécessaires: ${BLUE}microk8s enable dns storage metrics-server rbac${NC}"
echo -e "3. Construire les images Docker: ${BLUE}cd ${BASE_DIR}/alpine-lab && docker build -t localhost:32000/alpine-lab:latest .${NC}"
echo -e "4. Puis: ${BLUE}cd ${BASE_DIR}/observer && docker build -t localhost:32000/observer:latest .${NC}"
echo -e "5. Pousser les images au registre local: ${BLUE}docker push localhost:32000/alpine-lab:latest && docker push localhost:32000/observer:latest${NC}"
echo -e "6. Créer le namespace: ${BLUE}microk8s kubectl create namespace stress-test${NC}"
echo -e "7. Appliquer les configurations RBAC: ${BLUE}microk8s kubectl apply -f ${BASE_DIR}/rbac-config.yaml${NC}"
echo -e "8. Déployer les applications: ${BLUE}microk8s kubectl apply -f ${BASE_DIR}/alpine-lab-deployment.yaml -f ${BASE_DIR}/observer-deployment.yaml${NC}"
echo -e "9. Exécuter les tests: ${BLUE}OBSERVER_POD=\$(microk8s kubectl get pods -n stress-test -l app=observer -o jsonpath='{.items[0].metadata.name}') && microk8s kubectl exec -it -n stress-test \$OBSERVER_POD -- bash -c 'cd /monitoring-scripts && ./monitor-htop.sh'${NC}"

# Créer un script d'installation simple (une étape)
cat > ${BASE_DIR}/install.sh << 'ENDFILE'
#!/bin/bash

# Script d'installation automatique pour MicroK8s Stress Test
set -e

# Vérifier si on est root
if [ "$EUID" -ne 0 ]; then
  echo "Ce script doit être exécuté en tant que root (sudo)."
  exit 1
fi

echo "Installation de MicroK8s (si nécessaire)..."
if ! command -v microk8s &> /dev/null; then
  snap install microk8s --classic
  usermod -a -G microk8s $SUDO_USER
  chown -f -R $SUDO_USER ~/.kube
  echo "MicroK8s installé!"
else
  echo "MicroK8s déjà installé."
fi

echo "Activation des addons nécessaires..."
microk8s status --wait-ready
microk8s enable dns storage metrics-server rbac

echo "Construction et déploiement des images Docker..."
cd $(dirname "$0")

echo "Construction de l'image alpine-lab..."
cd alpine-lab
docker build -t localhost:32000/alpine-lab:latest .
docker push localhost:32000/alpine-lab:latest

echo "Construction de l'image observer..."
cd ../observer
docker build -t localhost:32000/observer:latest .
docker push localhost:32000/observer:latest

cd ..

echo "Déploiement des applications dans Kubernetes..."
microk8s kubectl create namespace stress-test || true
microk8s kubectl apply -f rbac-config.yaml
microk8s kubectl apply -f alpine-lab-deployment.yaml
microk8s kubectl apply -f observer-deployment.yaml

echo "Attente du démarrage des pods..."
sleep 10

echo "Vérification de l'état des pods..."
microk8s kubectl get pods -n stress-test

echo "Installation terminée! Vous pouvez maintenant exécuter les tests avec:"
echo "OBSERVER_POD=\$(microk8s kubectl get pods -n stress-test -l app=observer -o jsonpath='{.items[0].metadata.name}')"
echo "microk8s kubectl exec -it -n stress-test \$OBSERVER_POD -- bash -c 'cd /monitoring-scripts && ./monitor-htop.sh'"
ENDFILE
chmod +x ${BASE_DIR}/install.sh
echo -e "${GREEN}✓ Script d'installation automatique créé: ${BASE_DIR}/install.sh${NC}"
echo -e "${YELLOW}Pour une installation rapide en une seule étape, exécutez: ${BLUE}sudo ${BASE_DIR}/install.sh${NC}"