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
    
    # Utiliser la version simplifiée de top sans l'option -o qui cause l'erreur
    echo "== Instantané des processus =="
    kubectl exec -n $NAMESPACE $POD_NAME -- top -b -n 1 | head -20
    
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
        echo "== Instantané des processus =="
        kubectl exec -n $NAMESPACE $POD_NAME -- top -b -n 1 | head -20
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