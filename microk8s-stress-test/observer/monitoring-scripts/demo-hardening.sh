#!/bin/bash
# demo-hardening.sh - Script de démonstration visuelle du hardening MicroK8s

# Couleurs pour une meilleure lisibilité
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

POD_NAME=$(kubectl get pods -n stress-test -l app=alpine-lab -o jsonpath="{.items[0].metadata.name}")
NAMESPACE="stress-test"

clear
echo -e "${BOLD}${BLUE}======================================================${RESET}"
echo -e "${BOLD}${BLUE}=    DÉMONSTRATION DU HARDENING MICROK8S            =${RESET}"
echo -e "${BOLD}${BLUE}======================================================${RESET}"
echo

# Fonction pour dessiner une barre de progression colorée
draw_progress_bar() {
    local percent=$1
    local label=$2
    local color=$3
    local width=50
    local filled=$(echo "scale=0; $percent * $width / 100" | bc)
    
    printf "${BOLD}%-15s${RESET} [" "$label"
    for ((i=0; i<width; i++)); do
        if [ "$i" -lt "$filled" ]; then
            printf "${color}█${RESET}"
        else
            printf "░"
        fi
    done
    printf "] ${BOLD}%3d%%${RESET}\n" "$percent"
}

# Fonction pour afficher les limites de ressources du pod
show_limits() {
    echo -e "\n${BOLD}${CYAN}LIMITES DE RESSOURCES DÉFINIES PAR LE HARDENING:${RESET}"
    echo -e "${CYAN}------------------------------------------------${RESET}"
    
    CPU_LIMIT=$(kubectl get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.spec.containers[0].resources.limits.cpu}')
    MEM_LIMIT=$(kubectl get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.spec.containers[0].resources.limits.memory}')
    
    echo -e "${BOLD}CPU:${RESET}     ${GREEN}$CPU_LIMIT cores${RESET} (maximum autorisé)"
    echo -e "${BOLD}Mémoire:${RESET} ${GREEN}$MEM_LIMIT${RESET} (maximum autorisé)"
    
    # Convertir les limites en valeurs numériques
    if [[ "$CPU_LIMIT" =~ ^[0-9]+$ ]]; then
        CPU_LIMIT_M=$((CPU_LIMIT * 1000))
    else
        CPU_LIMIT_M=$(echo $CPU_LIMIT | sed 's/m//')
    fi
    
    if [[ "$MEM_LIMIT" == *"Gi"* ]]; then
        MEM_LIMIT_MI=$(echo $MEM_LIMIT | sed 's/Gi//' | awk '{print $1 * 1024}')
    else
        MEM_LIMIT_MI=$(echo $MEM_LIMIT | sed 's/Mi//')
    fi
    
    echo -e "${CYAN}------------------------------------------------${RESET}"
    echo -e "${YELLOW}Ces limites empêchent le pod de consommer trop de ressources${RESET}"
    echo -e "${YELLOW}même sous une charge extrême, démontrant l'efficacité du hardening.${RESET}"
}

# Fonction pour mesurer et afficher l'utilisation actuelle des ressources
measure_usage() {
    local label=$1
    local full_output=$2
    
    echo -e "\n${BOLD}${MAGENTA}$label${RESET}"
    
    # Récupérer l'utilisation actuelle
    kubectl top pod -n $NAMESPACE $POD_NAME > /tmp/top_output.txt
    CPU_USAGE=$(tail -n 1 /tmp/top_output.txt | awk '{print $2}' | sed 's/m//')
    MEM_USAGE=$(tail -n 1 /tmp/top_output.txt | awk '{print $3}' | sed 's/Mi//')
    
    # Calculer les pourcentages
    CPU_PERCENT=$(echo "scale=0; $CPU_USAGE*100/$CPU_LIMIT_M" | bc)
    MEM_PERCENT=$(echo "scale=0; $MEM_USAGE*100/$MEM_LIMIT_MI" | bc)
    
    # Définir les couleurs selon l'utilisation
    if [ "$CPU_PERCENT" -lt 50 ]; then
        CPU_COLOR=$GREEN
    elif [ "$CPU_PERCENT" -lt 80 ]; then
        CPU_COLOR=$YELLOW
    else
        CPU_COLOR=$RED
    fi
    
    if [ "$MEM_PERCENT" -lt 50 ]; then
        MEM_COLOR=$GREEN
    elif [ "$MEM_PERCENT" -lt 80 ]; then
        MEM_COLOR=$YELLOW
    else
        MEM_COLOR=$RED
    fi
    
    # Dessiner les barres de progression
    draw_progress_bar "$CPU_PERCENT" "CPU" "$CPU_COLOR"
    draw_progress_bar "$MEM_PERCENT" "MÉMOIRE" "$MEM_COLOR"
    
    # Afficher plus de détails si demandé
    if [ "$full_output" = "true" ]; then
        echo
        echo -e "${BOLD}Détails d'utilisation:${RESET}"
        echo -e "CPU: ${CPU_USAGE}m / ${CPU_LIMIT_M}m"
        echo -e "Mémoire: ${MEM_USAGE}Mi / ${MEM_LIMIT_MI}Mi"
        
        echo
        echo -e "${BOLD}Processus en cours:${RESET}"
        kubectl exec -n $NAMESPACE $POD_NAME -- ps aux --sort=-%cpu | head -5
    fi
}

# Fonction pour exécuter un test de stress et afficher les résultats
run_stress_test() {
    local test_name=$1
    local script_name=$2
    local duration=$3
    local interval=$4
    local measurements=$((duration / interval))
    
    clear
    echo -e "${BOLD}${BLUE}======================================================${RESET}"
    echo -e "${BOLD}${BLUE}=    TEST DE STRESS: ${test_name}${RESET}"
    echo -e "${BOLD}${BLUE}======================================================${RESET}"
    
    # Afficher les limites de ressources
    show_limits
    
    # Mesurer l'utilisation avant le test
    measure_usage "AVANT LE TEST (Système au repos)" "true"
    
    # Lancer le test de stress
    echo -e "\n${BOLD}${RED}DÉMARRAGE DU TEST DE STRESS...${RESET}"
    kubectl exec -n $NAMESPACE $POD_NAME -- /stress-scripts/$script_name > /dev/null 2>&1 &
    STRESS_PID=$!
    
    # Surveiller l'utilisation pendant le test
    for ((i=1; i<=$measurements; i++)); do
        sleep $interval
        clear
        echo -e "${BOLD}${BLUE}======================================================${RESET}"
        echo -e "${BOLD}${BLUE}=    TEST DE STRESS: ${test_name}${RESET}"
        echo -e "${BOLD}${BLUE}======================================================${RESET}"
        show_limits
        
        # Afficher le temps écoulé et le progrès
        elapsed=$((i * interval))
        percent=$((elapsed * 100 / duration))
        echo -e "\n${BOLD}${RED}TEST EN COURS: ${elapsed}s / ${duration}s${RESET}"
        draw_progress_bar "$percent" "Progression" "${YELLOW}"
        
        # Mesurer l'utilisation actuelle
        measure_usage "PENDANT LE TEST (Système sous stress)" "true"
        
        # Afficher un message sur les limites de hardening
        if [ "$i" -gt 2 ]; then
            if [ "$CPU_PERCENT" -lt 100 ] && [ "$MEM_PERCENT" -lt 100 ]; then
                echo -e "\n${BOLD}${GREEN}✓ HARDENING EFFICACE:${RESET} ${GREEN}Malgré la charge intensive, le pod reste confiné dans les limites définies!${RESET}"
            elif [ "$CPU_PERCENT" -ge 100 ]; then
                echo -e "\n${BOLD}${YELLOW}! LIMITE CPU ATTEINTE:${RESET} ${YELLOW}Le pod tente d'utiliser plus de CPU mais est limité par le hardening!${RESET}"
            elif [ "$MEM_PERCENT" -ge 100 ]; then
                echo -e "\n${BOLD}${YELLOW}! LIMITE MÉMOIRE ATTEINTE:${RESET} ${YELLOW}Le pod tente d'utiliser plus de mémoire mais est limité par le hardening!${RESET}"
            fi
        fi
    done
    
    # Arrêter le test
    kill $STRESS_PID 2>/dev/null
    sleep 5
    
    # Mesurer l'utilisation après le test
    clear
    echo -e "${BOLD}${BLUE}======================================================${RESET}"
    echo -e "${BOLD}${BLUE}=    RÉSULTATS DU TEST: ${test_name}${RESET}"
    echo -e "${BOLD}${BLUE}======================================================${RESET}"
    show_limits
    measure_usage "APRÈS LE TEST (Retour au repos)" "true"
    
    echo -e "\n${BOLD}${GREEN}TEST TERMINÉ!${RESET}"
    echo -e "${BOLD}${GREEN}======================================================${RESET}"
    echo -e "${BOLD}Appuyez sur ENTRÉE pour continuer...${RESET}"
    read
}

# Menu principal
while true; do
    clear
    echo -e "${BOLD}${BLUE}======================================================${RESET}"
    echo -e "${BOLD}${BLUE}=    DÉMONSTRATION VISUELLE DU HARDENING MICROK8S    =${RESET}"
    echo -e "${BOLD}${BLUE}======================================================${RESET}"
    echo
    echo -e "${BOLD}Pod cible:${RESET} $POD_NAME"
    echo -e "${BOLD}Namespace:${RESET} $NAMESPACE"
    echo
    echo -e "${BOLD}${YELLOW}Choisissez un test à exécuter:${RESET}"
    echo -e "1. ${CYAN}Aperçu rapide des ressources actuelles${RESET}"
    echo -e "2. ${CYAN}Test de stress CPU${RESET} (démontre les limites de CPU)"
    echo -e "3. ${CYAN}Test de stress mémoire${RESET} (démontre les limites de mémoire)"
    echo -e "4. ${CYAN}Test de stress I/O${RESET} (démontre la protection contre les surcharges I/O)"
    echo -e "5. ${CYAN}Test de stress réseau${RESET} (démontre l'isolation réseau)"
    echo -e "6. ${CYAN}Test de stress combiné${RESET} (démontre toutes les protections)"
    echo -e "7. ${RED}Quitter${RESET}"
    echo
    read -p "Votre choix: " choice
    
    case $choice in
        1)
            clear
            echo -e "${BOLD}${BLUE}======================================================${RESET}"
            echo -e "${BOLD}${BLUE}=    APERÇU DES RESSOURCES ACTUELLES                =${RESET}"
            echo -e "${BOLD}${BLUE}======================================================${RESET}"
            show_limits
            measure_usage "UTILISATION ACTUELLE" "true"
            echo -e "\n${BOLD}Appuyez sur ENTRÉE pour continuer...${RESET}"
            read
            ;;
        2)
            run_stress_test "STRESS CPU" "stress-cpu.sh" 60 5
            ;;
        3)
            run_stress_test "STRESS MÉMOIRE" "stress-memory.sh" 60 5
            ;;
        4)
            run_stress_test "STRESS I/O" "stress-io.sh" 60 5
            ;;
        5)
            run_stress_test "STRESS RÉSEAU" "stress-network.sh" 60 5
            ;;
        6)
            run_stress_test "STRESS COMBINÉ" "stress-all.sh" 120 10
            ;;
        7)
            echo -e "${BOLD}${GREEN}Merci d'avoir utilisé la démonstration de hardening!${RESET}"
            exit 0
            ;;
        *)
            echo -e "${BOLD}${RED}Choix invalide!${RESET}"
            sleep 2
            ;;
    esac
done
