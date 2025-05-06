# MicroK8s Stress Test avec Hardening

Ce projet fournit un environnement complet de test de stress pour MicroK8s, conçu pour évaluer les performances et la résilience d'un cluster Kubernetes tout en appliquant les meilleures pratiques de sécurité (hardening).

## Vue d'ensemble

L'architecture se compose de deux pods principaux déployés dans un namespace dédié et isolé:

1. **Pod alpine-lab**: Exécute différents tests de stress (CPU, mémoire, I/O, réseau)
2. **Pod observer**: Surveille les métriques de performance du pod alpine-lab

Ces pods sont déployés avec des mesures de sécurité renforcées, notamment:
- Limites de ressources strictes (CPU, mémoire)
- Contextes de sécurité restreints
- Suppression des privilèges et capacités système
- Contrôle d'accès basé sur les rôles (RBAC)
- Utilisation d'utilisateurs non-root

## Prérequis

- Un système Linux compatible avec snap
- Docker installé
- Droits administrateur pour installer et configurer MicroK8s

## Installation et mise en place

### 1. Installation de MicroK8s

```bash
# Installation de MicroK8s
sudo snap install microk8s --classic

# Vérification de l'installation
microk8s status --wait-ready

# Activation des addons nécessaires
microk8s enable dns storage metrics-server rbac registry

# Configuration de l'alias kubectl pour simplifier les commandes
echo 'alias kubectl="microk8s kubectl"' >> ~/.bashrc
source ~/.bashrc
```

### 2. Installation rapide avec le script automatisé

```bash
# Cloner ce dépôt
git clone https://github.com/votre-nom/microk8s-stress-test.git
cd microk8s-stress-test

# Rendre le script d'installation exécutable
chmod +x install.sh

# Exécuter l'installation
sudo ./install.sh
```

Le script d'installation va:
- Vérifier/installer MicroK8s
- Activer les addons nécessaires
- Construire et déployer les images Docker
- Configurer le namespace et les droits RBAC
- Déployer les pods alpine-lab et observer

### 3. Installation manuelle (si vous préférez)

```bash
# Construction de l'image alpine-lab
cd ~/microk8s-stress-test/alpine-lab
docker build -t localhost:32000/alpine-lab:latest .
docker push localhost:32000/alpine-lab:latest

# Construction de l'image observer
cd ~/microk8s-stress-test/observer
docker build -t localhost:32000/observer:latest .
docker push localhost:32000/observer:latest

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

## Utilisation des tests de stress

### Accéder au pod observer et exécuter les tests

```bash
# Obtention du nom du pod observer
POD_NAME=$(kubectl get pods -n stress-test -l app=observer -o jsonpath="{.items[0].metadata.name}")

# Accès au pod observer
kubectl exec -it -n stress-test $POD_NAME -- bash

# Exécution du script de monitoring
cd /monitoring-scripts
./monitor-htop.sh
```

### Options de tests disponibles

Le script `monitor-htop.sh` offre plusieurs options:

1. **Surveillance htop en arrière-plan** - Lance htop dans une session tmux
2. **Capture d'un instantané des métriques** - Génère un rapport ponctuel
3. **Surveillance continue** - Capture des métriques à intervalles réguliers
4. **Test de stress CPU** - Charge maximale sur tous les CPU disponibles
5. **Test de stress mémoire** - Utilise jusqu'à 80% de la mémoire disponible
6. **Test de stress I/O** - Génère une charge intensive d'entrées/sorties disque
7. **Test de stress réseau** - Crée un trafic réseau important avec des requêtes HTTP
8. **Test de stress combiné** - Exécute simultanément tous les types de stress

### Analyse des résultats

Les résultats des tests sont automatiquement enregistrés dans des fichiers de log:

```bash
# Visualiser les résultats disponibles
ls -la /tmp/metrics_*.log

# Examiner un fichier de résultats spécifique
cat /tmp/metrics_20250506_183912.log
```

Chaque rapport contient:
- L'utilisation CPU en pourcentage et la charge système
- L'utilisation de la mémoire (totale, utilisée, disponible)
- L'activité du disque et l'espace disponible
- Les processus consommant le plus de ressources

## Mesures de hardening implémentées

### 1. Contextes de sécurité (SecurityContext)

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false
  runAsNonRoot: true
  runAsUser: 1000
  capabilities:
    drop:
    - ALL
```

Ces paramètres assurent que:
- Les conteneurs s'exécutent en tant qu'utilisateur non-root (UID 1000/1001)
- L'escalade de privilèges est désactivée
- Toutes les capacités Linux sont supprimées par défaut
- Les conteneurs ont des permissions minimales

### 2. Limites de ressources

```yaml
resources:
  limits:
    cpu: "2"
    memory: "2Gi"
  requests:
    cpu: "500m"
    memory: "500Mi"
```

Ces limites:
- Garantissent un minimum de ressources (requests)
- Plafonnent l'utilisation maximale (limits)
- Évitent qu'un pod ne consomme toutes les ressources du nœud
- Protègent contre les attaques par déni de service

### 3. RBAC (Contrôle d'accès basé sur les rôles)

```yaml
serviceAccountName: observer-account
```

Le système RBAC:
- Crée un compte de service dédié
- Accorde uniquement les permissions minimales nécessaires
- Applique le principe du moindre privilège
- Limite la portée des actions possibles

### 4. Isolation des ressources

```yaml
namespace: stress-test
```

L'isolation permet de:
- Séparer complètement l'environnement de test
- Contrôler l'accès aux ressources
- Limiter l'impact en cas de compromission
- Créer des volumes temporaires isolés

## Nettoyage

```bash
# Supprimer les déploiements
kubectl delete -f ~/microk8s-stress-test/observer-deployment.yaml
kubectl delete -f ~/microk8s-stress-test/alpine-lab-deployment.yaml
kubectl delete -f ~/microk8s-stress-test/rbac-config.yaml

# Supprimer le namespace
kubectl delete namespace stress-test
```

## Justification et bénéfices du hardening

L'implémentation de ces mesures de sécurité offre plusieurs avantages:

1. **Protection contre les attaques par déni de service**  
   Les limites de ressources empêchent un pod compromis de consommer toutes les ressources du nœud.

2. **Réduction de la surface d'attaque**  
   L'exécution en tant qu'utilisateur non-root et la suppression des capacités Linux limitent considérablement ce qu'un attaquant peut faire en cas de compromission.

3. **Confinement des menaces**  
   L'isolation par namespace contient l'impact d'une éventuelle compromission.

4. **Principe du moindre privilège**  
   Chaque composant dispose uniquement des permissions minimales nécessaires à son fonctionnement.

5. **Démonstration de la compatibilité sécurité-performance**  
   Les tests de stress démontrent que l'application des mesures de sécurité n'impacte pas significativement les performances.

Ce projet montre qu'il est possible de déployer des applications Kubernetes à la fois performantes et sécurisées, prouvant que le hardening peut être mis en œuvre sans compromettre les fonctionnalités essentielles.