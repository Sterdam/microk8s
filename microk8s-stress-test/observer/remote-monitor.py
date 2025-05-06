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
