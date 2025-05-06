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
