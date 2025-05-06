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
