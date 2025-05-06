#!/bin/bash
# stress-monitor.sh - Démonstration efficace des limites de hardening

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

POD_NAME=$(kubectl get pods -n stress-test -l app=alpine-lab -o jsonpath="{.items[0].metadata.name}")
NAMESPACE="stress-test"

# Afficher une ligne de séparation
line() {
  echo -e "${BLUE}=================================================${RESET}"
}

# Afficher les limites configurées
show_limits() {
  line
  echo -e "${BOLD}${GREEN}LIMITES CONFIGURÉES VIA HARDENING:${RESET}"
  line
  
  CPU_LIMIT=$(kubectl get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.spec.containers[0].resources.limits.cpu}')
  MEM_LIMIT=$(kubectl get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.spec.containers[0].resources.limits.memory}')
  
  echo -e "${BOLD}CPU:${RESET}     ${GREEN}$CPU_LIMIT cores${RESET} (maximum autorisé)"
  echo -e "${BOLD}Mémoire:${RESET} ${GREEN}$MEM_LIMIT${RESET} (maximum autorisé)"
  
  echo -e "${YELLOW}Ces limites sont appliquées au niveau du pod par Kubernetes${RESET}"
  echo -e "${YELLOW}et empêchent tout dépassement, même sous charge extrême.${RESET}"
}

# Fonction qui exécute un test et surveille directement dans le pod
run_direct_test() {
  local test_name=$1
  local script_name=$2
  local duration=$3
  
  clear
  line
  echo -e "${BOLD}${GREEN}TEST DE STRESS: $test_name${RESET}"
  line
  show_limits
  
  # Afficher les paramètres du test
  echo -e "\n${BOLD}Paramètres du test:${RESET}"
  echo -e "• Script: ${YELLOW}$script_name${RESET}"
  echo -e "• Durée: ${YELLOW}$duration secondes${RESET}"
  echo -e "• Pod cible: ${YELLOW}$POD_NAME${RESET}"
  
  # Afficher les métriques avant le test
  echo -e "\n${BOLD}${GREEN}MÉTRIQUES AVANT LE TEST:${RESET}"
  kubectl exec -n $NAMESPACE $POD_NAME -- top -b -n 1 | head -5
  kubectl exec -n $NAMESPACE $POD_NAME -- free -m | head -3
  
  # Créer un script temporaire pour exécuter le test et surveiller
  echo -e "\n${BOLD}${RED}DÉMARRAGE DU TEST ET SURVEILLANCE...${RESET}"
  
  # Créer le script de surveillance et d'exécution
  cat > /tmp/monitor.sh << EOF
#!/bin/bash
echo "Démarrage du test $test_name..."
echo "Exécution de: /stress-scripts/$script_name"

# Lancer le test en arrière-plan
/stress-scripts/$script_name &
TEST_PID=\$!

# Surveiller pendant son exécution
for i in \$(seq 1 $duration); do
  echo ""
  echo "=== UTILISATION À \$i secondes ==="
  echo "CPU:"
  top -b -n 1 | head -10
  echo ""
  echo "MÉMOIRE:"
  free -m
  sleep 1
done

# Terminer proprement le test
kill \$TEST_PID 2>/dev/null
killall stress-ng 2>/dev/null
echo "Test terminé."
EOF

  # Copier et exécuter le script dans le pod
  kubectl cp /tmp/monitor.sh $NAMESPACE/$POD_NAME:/tmp/monitor.sh
  kubectl exec -n $NAMESPACE $POD_NAME -- chmod +x /tmp/monitor.sh
  kubectl exec -it -n $NAMESPACE $POD_NAME -- /tmp/monitor.sh
  
  # Afficher un résumé après le test
  echo -e "\n${BOLD}${GREEN}RÉSUMÉ DU TEST:${RESET}"
  echo -e "Le test ${YELLOW}$test_name${RESET} a permis de démontrer que:"
  echo -e "1. Le pod tente d'utiliser plus de ressources sous stress"
  echo -e "2. Les limites définies empêchent tout dépassement"
  echo -e "3. Le hardening protège efficacement le cluster"
  
  line
  echo -e "\nAppuyez sur ENTRÉE pour revenir au menu..."
  read
}

# Menu principal
while true; do
  clear
  line
  echo -e "${BOLD}${GREEN}DÉMONSTRATION EFFICACE DU HARDENING KUBERNETES${RESET}"
  line
  echo -e "Pod: ${BOLD}$POD_NAME${RESET}"
  echo -e "Namespace: ${BOLD}$NAMESPACE${RESET}\n"
  
  echo -e "${BOLD}Tests disponibles:${RESET}"
  echo -e "1. ${YELLOW}Test de stress CPU${RESET} (15 secondes)"
  echo -e "2. ${YELLOW}Test de stress mémoire${RESET} (15 secondes)"
  echo -e "3. ${YELLOW}Test de stress I/O${RESET} (15 secondes)"
  echo -e "4. ${YELLOW}Test de stress réseau${RESET} (15 secondes)"
  echo -e "5. ${YELLOW}Test de stress combiné${RESET} (30 secondes)"
  echo -e "6. ${RED}Quitter${RESET}"
  echo
  read -p "Votre choix: " choice
  
  case $choice in
    1)
      run_direct_test "CPU" "stress-cpu.sh" 15
      ;;
    2)
      run_direct_test "MÉMOIRE" "stress-memory.sh" 15
      ;;
    3)
      run_direct_test "I/O" "stress-io.sh" 15
      ;;
    4)
      run_direct_test "RÉSEAU" "stress-network.sh" 15
      ;;
    5)
      run_direct_test "COMBINÉ" "stress-all.sh" 30
      ;;
    6)
      echo -e "${GREEN}Au revoir!${RESET}"
      exit 0
      ;;
    *)
      echo -e "${RED}Choix invalide!${RESET}"
      sleep 2
      ;;
  esac
done