#!/bin/sh
# Démarrer le service SSH
/usr/sbin/sshd

# Garder le conteneur en vie
tail -f /dev/null
