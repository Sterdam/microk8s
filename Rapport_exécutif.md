Rapport de Tests de Hardening MicroK8s
Résumé exécutif
Les tests de stress effectués démontrent l'efficacité des mesures de hardening implémentées dans l'environnement MicroK8s. Le système a maintenu son intégrité et sa stabilité face à des charges extrêmes, prouvant que les mécanismes de sécurité fonctionnent comme prévu.
Mesures de Hardening Implémentées

Limites de Ressources:

CPU: 2 cores maximum
Mémoire: 2Gi maximum
Ces limites sont appliquées au niveau du pod par Kubernetes


Isolation et Sécurité:

Exécution sous utilisateur non-root (stressuser)
Namespace dédié (stress-test)
RBAC avec permissions minimales
SecurityContext restrictif (capabilities DROP: ALL)
Désactivation de l'escalade de privilèges



Résultats des Tests
Test de Stress Combiné
Le test combiné a démontré:

Utilisation CPU:

Malgré une tentative d'utiliser 22 CPU, chaque processus a été limité à ~10% d'utilisation
La charge totale est restée sous contrôle


Utilisation Mémoire:

Augmentation progressive de l'utilisation mémoire
À ~4 secondes, tentative d'allocation de ~11.8Go
Le pod a été terminé avec un code 137 (OOM killer) lorsqu'il a atteint sa limite de 2Gi


Opérations I/O et Réseau:

Génération de trafic réseau contenue
Opérations I/O limitées sans impact sur la stabilité du système



Conclusions

Efficacité du Hardening:

Les limites de ressources ont correctement empêché la surallocation de CPU
Le mécanisme OOM de Kubernetes a terminé le processus lorsque la limite mémoire a été atteinte
L'exécution sous un utilisateur non privilégié a fonctionné comme prévu


Protection du Cluster:

Les tentatives d'utilisation intensive des ressources ont été confinées au pod
Aucun impact visible sur le reste du cluster


Recommandations:

Le hardening actuel est efficace pour les charges normales
Pour les applications nécessitant plus de ressources, ajuster les limites tout en maintenant les autres mesures de sécurité
Continuer à surveiller les performances sous charge pour s'assurer que les limites restent appropriées



Le test démontre que les mesures de hardening ont efficacement protégé l'environnement Kubernetes contre une utilisation excessive des ressources tout en garantissant l'isolation et la sécurité du système.