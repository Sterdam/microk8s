#!/bin/bash
# Script d'installation automatique pour MicroK8s Stress Test
set -e

# Codes couleur pour une meilleure lisibilité
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Vérifier si on est root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ce script doit être exécuté en tant que root (sudo).${NC}"
  exit 1
fi

# Définir le chemin complet vers microk8s
MICROK8S="/snap/bin/microk8s"

echo -e "${YELLOW}Configuration de l'environnement pour MicroK8s...${NC}"

# Configurer Docker pour le registre local
echo -e "${YELLOW}Configuration de Docker pour le registre local...${NC}"
mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
  cat > /etc/docker/daemon.json << EOF
{
    "insecure-registries" : ["localhost:32000"]
}
EOF
  systemctl restart docker || true
  echo -e "${GREEN}Configuration de Docker terminée.${NC}"
else
  echo -e "${GREEN}Configuration Docker déjà présente.${NC}"
fi

# Configurer la limite des inotify watches
echo -e "${YELLOW}Configuration de la limite des inotify watches...${NC}"
if [ -f /etc/sysctl.conf ] && grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf; then
  echo -e "${GREEN}Limite inotify déjà configurée.${NC}"
else
  mkdir -p /etc/sysctl.d
  echo "fs.inotify.max_user_watches=1048576" | tee -a /etc/sysctl.d/99-microk8s.conf
  sysctl --system
  echo -e "${GREEN}Limite inotify configurée.${NC}"
fi

# Vérifier l'état de MicroK8s et réinstaller si nécessaire
echo -e "${YELLOW}Vérification de l'état de MicroK8s...${NC}"
REINSTALL=0

if ! command -v $MICROK8S &> /dev/null; then
  echo -e "${YELLOW}MicroK8s n'est pas installé. Installation...${NC}"
  REINSTALL=1
else
  echo -e "${YELLOW}MicroK8s est déjà installé. Vérification de l'état...${NC}"
  if ! $MICROK8S status &> /dev/null; then
    echo -e "${RED}MicroK8s est installé mais ne fonctionne pas correctement. Réinstallation...${NC}"
    REINSTALL=1
  else
    echo -e "${GREEN}MicroK8s fonctionne correctement.${NC}"
  fi
fi

if [ $REINSTALL -eq 1 ]; then
  echo -e "${YELLOW}Suppression de l'installation MicroK8s existante...${NC}"
  snap remove microk8s
  sleep 5
  echo -e "${YELLOW}Installation d'une nouvelle instance de MicroK8s...${NC}"
  snap install microk8s --classic --channel=stable
  usermod -a -G microk8s $SUDO_USER
  chown -f -R $SUDO_USER ~/.kube 2>/dev/null || true
  echo -e "${GREEN}MicroK8s installé.${NC}"
fi

# Attendre que MicroK8s soit prêt avec une meilleure gestion des erreurs
echo -e "${YELLOW}Attente que MicroK8s soit prêt...${NC}"
MAX_TRIES=20
READY=0

for i in $(seq 1 $MAX_TRIES); do
  echo -e "${YELLOW}Tentative $i/$MAX_TRIES...${NC}"
  if $MICROK8S status | grep "microk8s is running" &> /dev/null; then
    echo -e "${GREEN}MicroK8s est prêt!${NC}"
    READY=1
    break
  else
    # En cas d'échec, essayer de démarrer MicroK8s
    echo -e "${YELLOW}MicroK8s n'est pas prêt. Tentative de démarrage...${NC}"
    $MICROK8S stop
    sleep 3
    $MICROK8S start
    sleep 10
  fi
done

if [ $READY -eq 0 ]; then
  echo -e "${RED}MicroK8s n'a pas pu démarrer après $MAX_TRIES tentatives.${NC}"
  echo -e "${YELLOW}Dernier essai avec une réinitialisation...${NC}"
  $MICROK8S reset
  sleep 5
  $MICROK8S start
  sleep 10
  if ! $MICROK8S status | grep "microk8s is running" &> /dev/null; then
    echo -e "${RED}Échec de démarrage de MicroK8s après réinitialisation. Abandon.${NC}"
    exit 1
  else
    echo -e "${GREEN}MicroK8s est prêt après réinitialisation!${NC}"
  fi
fi

echo -e "${YELLOW}Activation des addons nécessaires...${NC}"
$MICROK8S enable dns storage metrics-server rbac

# Étape importante: activer le registry
echo -e "${YELLOW}Activation du registry pour le stockage local des images...${NC}"
$MICROK8S enable registry
sleep 10
echo -e "${GREEN}Registry activé sur localhost:32000${NC}"

echo -e "${YELLOW}Construction et déploiement des images Docker...${NC}"
cd $(dirname "$0")

echo -e "${YELLOW}Construction de l'image alpine-lab...${NC}"
cd alpine-lab
docker build -t localhost:32000/alpine-lab:latest .

# Vérifier si le registry est accessible
echo -e "${YELLOW}Vérification de l'accès au registry local...${NC}"
REGISTRY_READY=false
for i in {1..5}; do
  if curl -s http://localhost:32000/v2/ >/dev/null 2>&1; then
    REGISTRY_READY=true
    break
  else
    echo -e "${YELLOW}Attente du registry (tentative $i/5)...${NC}"
    sleep 5
  fi
done

if [ "$REGISTRY_READY" = true ]; then
  echo -e "${GREEN}Registry accessible. Envoi des images...${NC}"
  docker push localhost:32000/alpine-lab:latest
  
  echo -e "${YELLOW}Construction de l'image observer...${NC}"
  cd ../observer
  docker build -t localhost:32000/observer:latest .
  docker push localhost:32000/observer:latest
  
  cd ..
  
  echo -e "${YELLOW}Déploiement des applications dans Kubernetes...${NC}"
  $MICROK8S kubectl create namespace stress-test || true
  $MICROK8S kubectl apply -f rbac-config.yaml
  $MICROK8S kubectl apply -f alpine-lab-deployment.yaml
  $MICROK8S kubectl apply -f observer-deployment.yaml
  
  echo -e "${YELLOW}Attente du démarrage des pods (30 secondes)...${NC}"
  sleep 30
  
  echo -e "${YELLOW}Vérification de l'état des pods:${NC}"
  $MICROK8S kubectl get pods -n stress-test
  
  # Attendre que les pods soient en état "Running"
  echo -e "${YELLOW}Attente que les pods soient prêts...${NC}"
  MAX_POD_TRIES=10
  for i in $(seq 1 $MAX_POD_TRIES); do
    RUNNING_PODS=$($MICROK8S kubectl get pods -n stress-test -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w)
    TOTAL_PODS=$($MICROK8S kubectl get pods -n stress-test -o jsonpath='{.items[*].metadata.name}' | wc -w)
    if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
      echo -e "${GREEN}Tous les pods sont en état Running!${NC}"
      break
    else
      echo -e "${YELLOW}Attente des pods ($RUNNING_PODS/$TOTAL_PODS prêts)... Tentative $i/$MAX_POD_TRIES${NC}"
      sleep 15
    fi
  done
  
  # Préparer la commande pour l'exécution des tests
  OBSERVER_POD=$($MICROK8S kubectl get pods -n stress-test -l app=observer -o jsonpath='{.items[0].metadata.name}')
  
  echo -e "${GREEN}===========================================${NC}"
  echo -e "${GREEN}Installation terminée avec succès!${NC}"
  echo -e "${GREEN}===========================================${NC}"
  echo -e "${YELLOW}Pour exécuter les tests de stress, copiez et collez la commande suivante:${NC}"
  echo -e "${GREEN}$MICROK8S kubectl exec -it -n stress-test $OBSERVER_POD -- bash -c 'cd /monitoring-scripts && ./monitor-htop.sh'${NC}"
  echo -e "${GREEN}===========================================${NC}"
else
  echo -e "${RED}Le registry local n'est pas accessible. Vérification des services microk8s:${NC}"
  $MICROK8S status
  $MICROK8S inspect
  echo -e "${RED}Impossible de continuer sans accès au registry. Consultez les logs pour plus d'informations.${NC}"
  exit 1
fi