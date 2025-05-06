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
    tmux

# Installation directe de kubectl en téléchargeant le binaire
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Installation des dépendances Python pour les scripts d'observation
RUN pip3 install --break-system-packages kubernetes

# Création d'un utilisateur non-root pour le hardening (avec UID 1001 au lieu de 1000)
RUN useradd -m -u 1001 obsuser

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