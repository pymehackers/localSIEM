# Manuel d'utilisation de localSIEM

Ce MANUAL est également disponible en :\
[de-DE](MANUAL.de-DE.md), [en-GB](MANUAL.en-GB.md), [en-US](MANUAL.md), [es-AR](MANUAL.es-AR.md), [es-ES](MANUAL.es-ES.md), fr-FR, [he-IL](MANUAL.he-IL.md), [hi-IN](MANUAL.hi-IN.md), [it-IT](MANUAL.it-IT.md), [ja-JP](MANUAL.ja-JP.md), [ko-KR](MANUAL.ko-KR.md), [pt-BR](MANUAL.pt-BR.md), [pt-PT](MANUAL.pt-PT.md), [ru-RU](MANUAL.ru-RU.md), [zh-CN](MANUAL.zh-CN.md)

[Installation](README.fr-FR.md) · [Référence du code](CODE.fr-FR.md)

## Sommaire

1. [Ce que fait localSIEM](#what)
2. [Installation](#installation)
3. [Prérequis d'Apache et de ModSecurity](#requirements)
4. [Le diagnostic](#doctor)
5. [Connexion au SOC](#soc)
6. [Connexion et comptes](#signin)
7. [Les deux tableaux de bord](#dashboards)
8. [Vue d'ensemble](#overview)
9. [Recherche](#search)
10. [La fiche de la requête et les pivots](#card)
11. [Vue en direct](#live)
12. [Alertes](#alerts)
13. [Modules](#modules)
14. [Administration](#administration)
15. [Avertissements de santé et que faire](#health)
16. [Rétention et disque](#retention)
17. [Ligne de commande](#cli)

<a id="what"></a>
## 1. Ce que fait localSIEM

localSIEM surveille les services du serveur sur lequel il est installé au moyen de **modules**, un par service. Il ne lit que les journaux de ce serveur : il ne reçoit aucun journal d'autres machines. Le module **Apache + ModSecurity** surveille le site web Apache : pour chaque requête, il réunit trois enregistrements, la ligne de `access.log`, les lignes de `error.log` et l'enregistrement du journal d'audit de ModSecurity, à l'aide de l'`UNIQUE_ID` de la requête. Tout est conservé pour la recherche. Ensuite, localSIEM décide de ce qui doit aller au SOC.

localSIEM fonctionne sur le même serveur Debian ou Alpine qu'il protège, à côté de son site web, sous la forme de deux services de l'utilisateur système `localsiem`. Sa propre interface web écoute sur le port 10443 : elle n'utilise jamais les ports 80 ni 443 et ne touche jamais au site web du serveur. Outre le SOC (facultatif, section 5), il peut vous envoyer les alertes les plus importantes via **Telegram** (section 14) et il offre à l'analyste du SOC un **outil de recherche**, un champ de recherche et une plage horaire (section 9). Il ne laisse jamais sortir du serveur les mots de passe, les cookies, les jetons ni les corps des requêtes, il utilise peu de mémoire (environ 100 Mo en usage normal, environ 200 Mo en pointe) et il ne remplit jamais le disque (section 16).

**Seul ce que personne n'a encore traité va au SOC.**

| Situation | Va au SOC ? |
|---|---|
| ModSecurity a bloqué la requête en phases 1–2 (avant que l'application ne la reçoive) | **Non.** Elle reste dans localSIEM, consultable par la recherche, et apparaît comme un décompte dans la prochaine alerte de cette IP. |
| ModSecurity a bloqué la réponse en phases 3–4 (l'application avait déjà exécuté la requête) | Oui |
| Correspondances de règles avec ModSecurity en `DetectionOnly` (rien n'est bloqué) | Oui |
| Correspondances de règles sous le seuil de blocage | Oui, avec la gravité `low` |
| Signaux des règles de localSIEM (force brute, web shell, fichier sensible, énumération, erreur de base de données) | Oui |
| Problèmes de santé et possible effacement de traces | Oui |

**Gravité de ce qui va au SOC**

| Situation | Gravité |
|---|---|
| Correspondances de règles non bloquées, réponse 3xx, 4xx ou 5xx | moyenne |
| Correspondances de règles non bloquées, réponse 2xx | élevée |
| Bloquée en phases 3–4 | élevée |
| Signes de réussite : règle de fuite de données ou de web shell (950–955) non bloquée, erreur SQL juste après, POST avec 2xx vers un nouveau `.php` | critique |
| Sous le seuil de blocage (souvent des faux positifs de l'application) | faible (configurable dans Paramètres) |

**Regroupement.** Une alerte par module, vhost, IP, catégorie et gravité dans une fenêtre de 10 minutes. Une alerte critique part immédiatement ; les autres attendent 60 secondes pour regrouper la rafale et partent avec le décompte. Un scanner qui envoie des milliers de requêtes produit quelques alertes, pas des milliers. Si la gravité augmente (par exemple, la même attaque reçoit désormais des réponses 200), c'est une autre alerte.

**Ce qui ne va jamais au SOC :** les corps des requêtes ou des réponses, les cookies, les en-têtes `Authorization`, les mots de passe ou les jetons — même masqués — et ce qui a déjà été bloqué en phases 1–2 (seulement sous forme de décompte). localSIEM masque les valeurs sensibles (`password`, `pass`, `pwd`, `passwd`, `token`, `secret`, `api_key`, `apikey`, `auth`, `session` et les en-têtes `Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, `Proxy-Authorization`) par `***` avant de conserver quoi que ce soit.

**Modules.** Le noyau de localSIEM (stockage, recherche, règles, regroupement, envoi au SOC, santé) est le même pour tous les services ; chaque module ajoute ce qui est propre à un service. Le module Apache + ModSecurity (`apache2`) provient du dépôt `localSIEM-modules` (GitHub) et s'installe, se met à jour et se désinstalle uniquement depuis l'interface web, jamais avec l'installateur de localSIEM ; l'installer n'installe jamais Apache ni ModSecurity. Tous les modules s'installent, se mettent à jour et se désinstallent de la même façon, depuis l'interface web. La section 13 explique comment les installer et les mettre à jour, consulter leur état, les activer et les désactiver, et les configurer.

<a id="installation"></a>
## 2. Installation

L'installation se fait en deux étapes : le noyau de localSIEM, puis ses modules (étape 2 ci-dessous). Exécutez en tant que root, directement depuis GitHub :

```bash
# Debian 13
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
# Alpine 3.24 (d'abord : apk add bash curl)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
```

L'interface web de localSIEM écoute toujours sur le **port 10443 en HTTPS** : l'installateur vérifie que le port est libre et s'arrête si un autre service l'utilise. L'action et les options se placent après `bash -s --`. L'installateur vérifie ce dont il a besoin (Python 3.13 avec `venv`, OpenSSL, les certificats des CA, les outils ACL, logrotate, curl, tar) et installe ce qui manque. Exécuté ainsi, via un pipe, il télécharge la branche `main` de `https://github.com/PYMEHackers/localSIEM` ; exécuté depuis une copie du projet (`bash deploy/install-update-reinstall-debian.sh --install`), il installe cette copie.

**L'action.** L'installateur a toujours besoin d'une action ; sans action, il s'arrête et les énumère :

| Action | Usage |
|---|---|
| `--install` | Installe localSIEM sur un serveur qui ne l'a pas. S'il trouve quoi que ce soit de localSIEM (`/opt/localsiem`, ses services ou son utilisateur `localsiem`, y compris d'une installation qui a échoué à mi-chemin), il s'arrête et renvoie à `--update` et `--reinstall`. |
| `--update` | Met à jour le localSIEM installé : il conserve ses données, ses comptes, ses paramètres, ses modules et les options données auparavant (ci-dessous). |
| `--reinstall [--yes]` | Supprime le localSIEM installé avec toutes ses données, comme le fait `--uninstall` (ci-dessous), et le réinstalle à partir de zéro, avec de nouveaux mots de passe. Il vous demande d'abord de taper `yes` (`--yes` ne le demande pas ; cette option est nécessaire sans terminal) et ne supprime rien tant que la nouvelle copie n'est pas téléchargée et que les options ne sont pas vérifiées. Les options de l'installation précédente ne sont pas conservées : donnez-les de nouveau. |
| `--uninstall [--yes]` | Supprime localSIEM et toutes ses données du serveur (ci-dessous). Elle s'utilise seule. |

`--update` et `--reinstall` s'arrêtent si localSIEM n'est pas installé : utilisez `--install`.

Options de `--install`, `--update` et `--reinstall` :

| Option | Usage |
|---|---|
| `--allow-from LIST` | IP et CIDR autorisés à ouvrir l'interface web, séparés par des virgules : le SOC et vos administrateurs |
| `--soc-url URL` | Par défaut `https://soc.pymehackers.com` |
| `--soc-token TOKEN` | Jeton d'ingestion de ce client dans le SOC. Facultatif : sans SOC, localSIEM fonctionne de manière autonome (section 5) |
| `--soc-ca-file PATH` | Uniquement pour un SOC avec un certificat privé (serveurs de test) |
| `--domain NAME` | Nom du serveur, pour le certificat et l'adresse du SIEM (par défaut : son nom d'hôte) |
| `--certificate PATH --private-key PATH` | Certificat à utiliser. Sans ces options, localSIEM copie le certificat Let's Encrypt de `--domain` s'il en existe un (et le copie de nouveau à chaque renouvellement), ou en crée un autosigné. |
| `--retention-days N`, `--max-disk SIZE` | Rétention (section 16) |
| `--enable-mfa`, `--disable-mfa` | Vérification en deux étapes activée (obligatoire pour tous les comptes) ou désactivée. Sans ces options, une nouvelle installation l'a désactivée et une mise à jour conserve ce qui a été choisi dans Administration › Paramètres (section 14). |
| `--rotate-credentials` | Crée un nouveau secret de signature JWT et l'écrit dans `/root/webapp-credentials.txt` |
| `--ref REF` | Branche ou tag de localSIEM à télécharger (par défaut `main`) |
| `--source-url URL` | Archive (`.tar.gz`) de localSIEM à installer à la place de celle de GitHub (un miroir) |
| `--modules-repository URL`, `--modules-ref REF` | Dépôt (ou archive `.tar.gz`) et branche ou tag depuis lesquels l'interface web installe et met à jour les modules (section 13). Par défaut : `https://github.com/PYMEHackers/localSIEM-modules`, branche `main`. |

**Toujours la dernière version.** GitHub conserve les fichiers de `raw.githubusercontent.com` dans un cache jusqu'à 5 minutes après chaque modification ; les commandes ci-dessus lisent donc l'installateur via l'API de GitHub, qui n'a pas de cache ; l'installateur demande ensuite à cette API à quel commit correspond la branche et télécharge exactement ce commit, et il demande à chaque serveur intermédiaire de ne pas répondre avec une copie en cache. Sans jeton, GitHub autorise 60 requêtes d'API par heure depuis chaque adresse IP : s'il refuse, la commande échoue avec `403` (attendez et relancez-la) ; si seule la question de l'installateur échoue, l'installateur le signale et télécharge la branche.

Les options sont mémorisées, dans `/opt/localsiem/config/install.env` : `--update` sans options les conserve. Pour mettre à jour :

```bash
# Debian 13 (Alpine : install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --update
```

Le journal de l'installateur est `/root/webapp-install.log` et les mots de passe qu'il crée se trouvent dans `/root/webapp-credentials.txt` (tous deux en mode 600). Il affiche sa progression en étapes numérotées (`[3/12] Getting localSIEM`), avec `✓` pour ce qui est fait, `!` pour les avertissements, `✗` pour les échecs et `·` pour les informations, en couleur dans un terminal (`NO_COLOR=1` ou `LOCALSIEM_COLOR=never` désactivent les couleurs). La sortie d'apt-get ou d'apk, de curl, de tar et de pip ne va que dans le journal ; quand l'un d'eux échoue, l'écran affiche ses 20 dernières lignes. Le journal reçoit les mêmes lignes, sans couleurs, avec les heures au format d'enregistrement. À la fin, il exécute le diagnostic de chaque module activé (section 4) et affiche un résumé : l'adresse de l'interface web, qui est aussi l'adresse du SIEM à communiquer au SOC, le fichier des identifiants, le journal et l'état du SOC, suivis des prochaines étapes. S'il échoue, il indique à quelle étape il s'est arrêté.

**Désinstallation.** `--uninstall` supprime localSIEM du serveur : il arrête et retire ses services et supprime `/opt/localsiem` (code, paramètres, la base de données avec tous les événements et toutes les alertes, certificats et modules), l'utilisateur `localsiem`, l'accès en lecture aux journaux que `setup-modules` a donné, la configuration d'Apache (`localsiem.conf`) qu'ajoutait l'option `--configure-apache` des anciennes versions du module Apache (1.2.0 ou antérieures), avec un configtest et un rechargement d'Apache, le fichier logrotate, le hook Let's Encrypt et les entrées de localSIEM de `/root/webapp-credentials.txt` (le fichier est supprimé quand il n'y reste plus rien d'autre). Il vous demande d'abord de taper `yes` (`--yes` ne le demande pas ; cette option est nécessaire sans terminal). S'il ne trouve rien de localSIEM sur le serveur, il affiche «Nothing of localSIEM was found on this server.». Le journal de l'installateur, les paquets que l'installateur a ajoutés, `mod_unique_id` (Debian) et les journaux d'Apache restent en place, y compris le `localsiem_access.log` que ce fichier faisait écrire à Apache et `modsec_audit.log` : localSIEM ne modifie ni ne supprime jamais un journal d'Apache. Pour désinstaller :

```bash
# Debian 13 (Alpine : install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --uninstall
```

**Réinstallation.** Pour repartir de zéro en une seule étape, `--reinstall` supprime tout de la même façon et réinstalle localSIEM (donnez de nouveau les options) :

```bash
# Debian 13 (Alpine : install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --reinstall --allow-from 203.0.113.10 --soc-token TOKEN
```

**2. Les modules.** L'installateur de localSIEM n'installe **aucun module** : il laisse localSIEM prêt à les recevoir, et une mise à jour conserve ceux déjà installés (et l'accès en lecture à leurs journaux). Les modules s'installent **uniquement depuis l'interface web** : Modules › Installables (section 13), qui liste les modules du dépôt `localSIEM-modules` qui ne sont pas encore installés ; ce dépôt n'a pas d'installateur propre. localSIEM y télécharge le module, copie son dossier (`mod-<name>/` dans le dépôt) dans `/opt/localsiem/modules/<name>/` (les dossiers `tests/` ne sont pas copiés ; un module réinstallé retrouve les paramètres qu'il avait) et redémarre le collecteur. Les modules se mettent aussi à jour et se désinstallent depuis l'interface web : **Mettre à jour**, quand le dépôt propose une version plus récente, et **Désinstaller**, tous deux dans Modules › Installés (section 13).

La lecture des journaux d'un module nécessite root ; une fois le module installé, l'interface web affiche donc dans une boîte de dialogue la commande à exécuter en tant que root sur le serveur :

```bash
/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py setup-modules
```

Elle donne à l'utilisateur `localsiem` l'accès en lecture aux dossiers de journaux que déclare chaque module installé (`/var/log/apache2` pour le module Apache ; section 3.7), y compris aux fichiers des prochaines rotations, redémarre localSIEM et exécute le diagnostic en tant que `localsiem`. Elle peut être relancée à tout moment. Cet accès en lecture, que donne localSIEM, est tout ce que root fait pour les modules.

**L'installation d'un module n'installe jamais le logiciel qu'il surveille**, ni quoi que ce soit d'autre : un module fonctionne avec ce que le serveur a déjà et ne modifie jamais rien en dehors de `/opt/localsiem/`. Un nouveau module démarre activé ou désactivé selon ce qu'a décidé son auteur, sauf quand il manque au serveur ce dont il a besoin (pour le module Apache : Apache et ModSecurity 2) : il est alors installé **désactivé**, l'interface web indique ce qui manque et son interrupteur reste verrouillé jusqu'à ce que **Reconfigurer** le trouve (section 13). Son état figure dans **Modules › Installés** (section 13).

<a id="requirements"></a>
## 3. Prérequis d'Apache et de ModSecurity

Voici les prérequis du module Apache + ModSecurity. Apache et ModSecurity 2 eux-mêmes doivent être installés au préalable : sans eux, le module ne peut pas être activé (section 13). localSIEM ne modifie jamais de lui-même la configuration d'Apache, ni les journaux d'Apache, leur format ou la façon dont ils sont écrits : le module lit les journaux que le serveur écrit déjà et s'y adapte. Le diagnostic du module (section 4) vérifie chaque prérequis : pour ModSecurity avec son CRS et `SecRuleEngine` (point 1), `mod_unique_id` (point 2) et l'accès en lecture (point 7), il affiche l'extrait ou la commande exacte pour chacun de ceux qui manquent, à appliquer par vous-même ; les journaux (points 3 à 6), il se contente de les décrire, sans proposer de les modifier.

1. **ModSecurity 2 avec l'OWASP CRS**, avec `SecRuleEngine On` ou `DetectionOnly`. Les deux fonctionnent : avec `DetectionOnly`, rien n'est bloqué, donc toutes les correspondances vont au SOC.
2. **`mod_unique_id`**, dont ModSecurity 2 a besoin pour fonctionner (sans lui, il n'inspecte rien ; Alpine ne le charge pas par défaut) et qui permet de réunir les trois enregistrements de chaque requête.
3. **Un journal d'accès**, tel qu'Apache l'écrit. Tout format convient (`combined`, `vhost_combined`, `common`, ou n'importe quel `LogFormat` de la configuration) : chaque ligne est rattachée à sa requête par IP du client, méthode, URI, statut et heure («corrélation faible»), et le vhost provient de `%v` ou, à défaut, de l'en-tête Host et du port de l'enregistrement d'audit. Quand le format contient aussi les millisecondes, `%v` et `%{UNIQUE_ID}e` (comme les lignes `localsiem_combined` que certains serveurs écrivent déjà), chaque ligne est rattachée à sa requête par `UNIQUE_ID`, et avec `%D` localSIEM obtient aussi sa durée. Un journal d'accès dont le format ne contient pas l'IP du client, l'heure, la ligne de requête ou le statut est lu tel quel, mais ses lignes ne peuvent pas être rattachées à leurs requêtes : ces requêtes sont visibles dans le journal d'audit de ModSecurity. Un `CustomLog` dont le format ne contient aucune directive écrit le même texte sur chaque ligne et n'est pas lu.
4. **`mod_remoteip`**, qui détermine quelle IP figure dans les journaux. Si le site web est derrière un proxy ou un répartiteur de charge et qu'Apache ne l'utilise pas, les journaux contiennent l'IP du proxy, de même que les alertes et les règles par IP : le diagnostic et l'avertissement de santé «Real client IP missing» (section 15) le signalent.
5. **Le journal d'audit de ModSecurity**, tel que ModSecurity l'écrit : en série ou concurrent, en JSON ou natif, avec les parties qu'il contient. Sans lui (`SecAuditEngine Off` ou pas de `SecAuditLog`), localSIEM décide à partir de `error.log` seulement, et la fiche de la requête n'a ni en-têtes ni liste de règles. Sans la partie `H`, l'action effectuée ne peut pas y être lue. La partie `E` (le corps de la réponse), si elle est journalisée, ne va jamais au SOC ; la partie `K` (le texte complet de chaque règle exécutée) n'est pas conservée. Avec le type concurrent (un fichier par transaction), ModSecurity crée généralement les fichiers en mode 600, et localSIEM ne les lit que si `localsiem` le peut (point 7).
6. **Masquage à la source** : si ModSecurity ne masque pas le journal d'audit sur le disque (ses actions `sanitise`), ce fichier peut contenir des mots de passe et des cookies ; localSIEM les masque avant de les conserver, et ils ne vont jamais au SOC.
7. **Accès en lecture aux journaux pour l'utilisateur `localsiem`**. La commande pour root de la section 2 (`manage.py setup-modules`) le donne pour les dossiers que déclarent les modules installés (`/var/log/apache2` pour le module Apache), et l'installateur de localSIEM le redonne à chaque mise à jour : sur Debian, il ajoute `localsiem` au groupe `adm` et, comme sur Alpine, donne à `localsiem` l'accès en lecture à ces dossiers au moyen d'ACL, y compris une ACL par défaut pour que les fichiers des prochaines rotations soient eux aussi lisibles. Les journaux que vous ajoutez manuellement dans un autre dossier (section 13) ont aussi besoin de cet accès, par exemple `setfacl -m g:localsiem:rx /srv/logs`, `setfacl -d -m g:localsiem:r /srv/logs` et `setfacl -m g:localsiem:r /srv/logs/*.log`. localSIEM ne fait que lire les journaux : il n'y écrit jamais et ne les fait jamais tourner, ne les tronque, ne les déplace ni ne les supprime. Quand il commence à suivre un journal (au premier démarrage, après l'installation ou l'activation d'un module, ou dès que root lui donne l'accès en lecture), il commence à sa fin : ce que le journal contenait déjà est de l'historique et ne donne jamais lieu à une alerte ; seul le journal d'un vhost créé ultérieurement est lu depuis son début (s'il fait jusqu'à 5 Mo).

<a id="doctor"></a>
## 4. Le diagnostic

Chaque module a son propre diagnostic. Le diagnostic du module Apache vérifie chaque prérequis de la section 3 et affiche l'extrait ou la commande qui corrige chacun de ceux qui manquent ; les journaux (format, `mod_remoteip`, journal d'audit, masquage), il se contente de les décrire, sans proposer de les modifier, et il liste les sources trouvées (et celles qu'il ne peut pas lire, comme les journaux envoyés dans un pipe). Il s'exécute à la fin de chaque installation de localSIEM et de la commande pour root de la section 2, apparaît dans la page de chaque module (**Modules › Installés › Configurer**, section 13, avec le bouton «Redécouvrir et lancer le diagnostic») et peut être exécuté à tout moment pour tous les modules activés :

```bash
runuser -u localsiem -- /opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor   # Debian
su -s /bin/sh localsiem -c "/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor"   # Alpine
```

`✓` signifie que tout va bien, `!` que cela fonctionne avec des limites, `✗` qu'il faut corriger, `·` que cela ne s'applique que dans certaines situations (en couleur dans un terminal ; là où l'UTF-8 ne peut pas être écrit, `+`, `!`, `x` et `-`). Un module qui ne peut pas être chargé apparaît en premier sous la forme `✗ Module <name> not loaded: <reason>`. Un module désactivé n'a pas de diagnostic : s'il a des prérequis (section 13), le diagnostic les affiche à la place, pour que vous sachiez s'il peut être activé.

<a id="soc"></a>
## 5. Connexion au SOC

La connexion de localSIEM à un SOC est facultative. Sans SOC (pas de jeton, ou **Envoyer les alertes au SOC** désactivé), localSIEM fonctionne de manière autonome : il conserve chaque alerte dans l'onglet **Alertes** comme «Non envoyée» et ne les envoie jamais par la suite, même lorsqu'un SOC est configuré ensuite : à partir de ce moment, seules les nouvelles alertes lui sont envoyées. Les canaux (Telegram) fonctionnent avec ou sans SOC.

L'administrateur du SOC :

1. Crée un jeton d'ingestion pour le client (il n'est affiché qu'une seule fois) et vous le remet. Configurez-le avec `--soc-token` ou dans **Administration › SOC**.
2. Définit comme **adresse du SIEM** du client `https://<server>:<port of localSIEM>` (affichée par l'installateur et dans Administration › SOC). L'analyste responsable d'une alerte utilise ce lien pour venir enquêter.
3. Vous communique les IP sortantes du SOC : ajoutez-les aux IP autorisées (`--allow-from` ou Administration › Paramètres) et **n'ouvrez le port dans le pare-feu qu'à elles et à vos administrateurs**.

localSIEM envoie un **signal de vie** toutes les 5 minutes. Si le SOC ne reçoit ni alertes ni signaux de vie pendant un certain temps (60 minutes par défaut), il prévient son équipe. Les alertes attendent dans une file persistante : une coupure réseau ou un redémarrage n'en perd aucune, et renvoyer une alerte ne la duplique jamais dans le SOC. Si le SOC répond que le client a épuisé ses numéros d'alerte, localSIEM cesse d'envoyer, conserve la file et l'indique dans Administration › SOC.

Chaque alerte comporte un nom de règle stable, une description avec la requête exacte à coller dans la recherche de localSIEM, et des détails : vhost, IP du client, méthode, URI (masquée), réponse, user agent, les données de ModSecurity (moteur, action, phase, score, seuil, règles, données correspondantes), le groupe (nombre, première et dernière fois, des `UNIQUE_ID` d'exemple) et le **contexte** de l'IP : requêtes et requêtes bloquées au cours de la dernière heure, règles bloquées et première fois qu'elle a été vue.

<a id="signin"></a>
## 6. Connexion et comptes

Ouvrez `https://<server>:10443/` : la page de connexion n'est que le formulaire, avec le logo, le nom d'utilisateur, le mot de passe, **Continuer** et, en dessous, la langue et le thème. Les comptes sont créés par un administrateur ; il n'y a pas d'inscription libre. Les mots de passe comportent au moins 8 caractères. La **vérification en deux étapes** est désactivée par défaut ; quand un administrateur l'active (Administration › Paramètres, section 14), elle est obligatoire pour tous les comptes : à la connexion suivante, scannez le code QR avec une application d'authentification (Google Authenticator, Microsoft Authenticator, Aegis, FreeOTP... ; elle apparaît sous le nom «PYMEHackers localSIEM») et saisissez son code ; dès lors, chaque connexion demande le code de l'application. Après plusieurs tentatives échouées, la connexion est bloquée pendant quelques minutes.

**Accès direct avec un jeton.** Un administrateur peut remettre à un analyste une URL d'accès, `https://<server>:10443/auth/login/auto?token=...` (Utilisateurs › Jetons d'accès, section 14). L'ouvrir depuis une adresse autorisée connecte immédiatement, sans mot de passe ni second facteur, et ouvre la Vue d'ensemble du tableau de bord utilisateur ; ajoutez `&next=/user/dashboard/search/?q=...` pour ouvrir une autre page du site. Si le jeton ne fonctionne pas, la page de connexion en indique la raison : jeton inconnu, expiré ou révoqué, ou compte désactivé ou qui n'est plus un compte d'analyste. Conservez l'URL comme un mot de passe : quiconque la possède peut se connecter avec ce compte jusqu'à ce qu'elle expire ou soit révoquée. Chaque connexion, avec mot de passe ou avec un jeton, et chaque tentative échouée sont enregistrées (Connexions, section 14).

Après la connexion, vous arrivez sur la **Vue d'ensemble** de votre tableau de bord (section 7). Un lien vers une recherche (par exemple depuis le SOC) ouvre la page de connexion si nécessaire, puis **la même recherche avec ses paramètres**.

Rôles : **analyste** (travaille dans le tableau de bord utilisateur : vue d'ensemble, recherche, vue en direct, alertes, état des modules et compte) et **administrateur** (travaille dans le tableau de bord administrateur : la même chose, plus la configuration des modules et l'administration). La langue (de-DE, en-GB, en-US, es-AR, es-ES, fr-FR, he-IL, hi-IN, it-IT, ja-JP, ko-KR, pt-BR, pt-PT, ru-RU, zh-CN), le thème (celui du système, clair ou sombre) et l'horloge UTC se trouvent dans la barre de titre de chaque page des tableaux de bord ; la page de connexion les propose sous **Continuer** et démarre avec ceux choisis en dernier dans ce navigateur (sans choix, ceux du navigateur et du système). La langue affichée lorsque vous cliquez sur **Continuer** devient la langue de votre compte : les tableaux de bord la conservent, dans n'importe quel navigateur, jusqu'à ce que vous la changiez. Les heures sont toujours en UTC au format natif `2026/10/29@13:59:59.723`. Les fichiers que localSIEM écrit (les exports, `/root/webapp-credentials.txt`, le journal de l'installateur) et les alertes qu'il envoie au SOC utilisent le format d'enregistrement `2026-10-29@13-59-59.723`, également en UTC.

<a id="dashboards"></a>
## 7. Les deux tableaux de bord

Chaque rôle a son propre tableau de bord ; son adresse indique dans lequel vous vous trouvez. La barre latérale comporte le logo en haut, les onglets (une ligne entre chaque groupe) et, en bas, **Se déconnecter**.

| | Tableau de bord administrateur | Tableau de bord utilisateur |
|---|---|---|
| Qui | Administrateurs | Analystes |
| Adresse | `/admin/dashboard/<tab>/` | `/user/dashboard/<tab>/` |
| Onglets | Vue d'ensemble, Recherche, Direct, Alertes ; Modules (Installés et Installables), Utilisateurs (Comptes et Jetons d'accès), SOC, Canaux (Général et Telegram), Paramètres, Audit des recherches, Connexions ; Compte | Vue d'ensemble, Recherche, Direct, Alertes, Modules (état uniquement), Compte |

Chaque onglet a sa propre adresse (par exemple `/admin/dashboard/logins/`), et `/admin/dashboard/` ou `/user/dashboard/` ouvrent la Vue d'ensemble. Les sections d'un onglet ont aussi la leur : `/admin/dashboard/users/` ouvre `/admin/dashboard/users/accounts/` et les jetons d'accès se trouvent dans `/admin/dashboard/users/tokens/` ; `/admin/dashboard/modules/` ouvre `/admin/dashboard/modules/installed/` et les modules installables se trouvent dans `/admin/dashboard/modules/installable/`. Une adresse de l'autre tableau de bord vous mène au même onglet du vôtre : un administrateur qui ouvre un lien vers `/user/dashboard/search/?q=...` (le lien habituel du SOC) obtient la même recherche dans `/admin/dashboard/search/` ; un analyste qui ouvre un onglet d'administration obtient la Vue d'ensemble du tableau de bord utilisateur.

**Ce que voient les analystes.** Tout ce qu'il faut pour enquêter : la vue d'ensemble, les recherches avec leurs fiches de requête, la vue en direct, les alertes et l'état de chaque module (activé ou désactivé, fonctionnel ou non, et ses compteurs). Ils ne peuvent ni activer ou désactiver les modules, ni les configurer, ni voir leur diagnostic ou leurs règles, ni gérer les utilisateurs, les jetons d'accès, la connexion au SOC, les paramètres, l'audit des recherches ou le registre des connexions.

<a id="overview"></a>
## 8. Vue d'ensemble

Le premier onglet des deux tableaux de bord. Il s'actualise toutes les 15 secondes et affiche :

- **Événements (24 h)**, avec le nombre d'entre eux qui ont déclenché une alerte ; **Bloqués (24 h)**, ce que ModSecurity a déjà traité (conservé, sans alerte) ; **Alertes (24 h)**, avec le nombre de celles qui attendent le SOC ; et **Modules en fonctionnement**, les modules activés qui sont «Activé et fonctionnel» sur l'ensemble des modules activés (en vert quand tous fonctionnent).
- **Activité des dernières 24 heures** : événements par heure ; la partie bleue de chaque barre correspond à ce que ModSecurity a bloqué. Cliquez sur une heure pour ouvrir la recherche de ses événements.
- **État des modules** : chaque module avec son état (section 13) et ce qu'il lit ; «Voir les modules» ouvre l'onglet Modules.
- **Système** : si le collecteur est en marche (et sa version), depuis quand, l'état de la connexion au SOC, le dernier signal de vie, les alertes en attente du SOC, l'espace disque libre et la taille de la base de données par rapport à son maximum.
- **Dernières alertes** : les six plus récentes (gravité, règle, IP, nombre, statut, dernière fois) ; «Voir toutes les alertes» ouvre l'onglet Alertes.

<a id="search"></a>
## 9. Recherche

L'onglet **Recherche** comporte un champ de recherche et une plage horaire (15 dernières minutes, dernière heure, 24 dernières heures, 7 derniers jours, 30 derniers jours, ou une plage personnalisée au format natif).

| Syntaxe | Signification |
|---|---|
| `word` | Recherche en texte intégral dans le texte original (masqué), y compris décodé des URL |
| `"exact phrase"` | Expression exacte |
| `field:value` | Champ égal à une valeur (les champs de texte ne tiennent pas compte de la casse) |
| `field:*part*` | Caractères génériques |
| `status:>=500`, `status:400..499`, `status:4xx` | Comparaisons et plages sur les champs numériques |
| `a b` / `a AND b`, `a OR b`, `NOT a` / `-a`, `( )` | Opérateurs et parenthèses |

| Groupe | Champs |
|---|---|
| Réseau | `ip`, `vhost`, `host` |
| Requête | `method`, `uri`, `path`, `query`, `status`, `bytes`, `duration` (microsecondes), `ua`, `referer` |
| Origine | `uid` (UNIQUE_ID), `module`, `source` (`access`/`error`/`audit`) |
| ModSecurity | `rule` (id du CRS, ou `localsiem:<rule>`), `category`, `phase`, `score`, `engine` (`on`/`detection-only`) |
| Alertes | `severity`, `action` (`blocked`/`none`), `alert` (code SOC), `sent` (`yes`/`no`) |
| Qualité | `parse` (`ok`/`partial`/`unparsed`) |

Exemples :

- `ip:203.0.113.7` — tout ce qui concerne une IP
- `rule:942100` — les requêtes qui ont déclenché cette règle du CRS
- `status:200 action:none category:sqli` — les injections SQL qui n'ont pas été bloquées et ont reçu un 200
- `uri:*wp-login*`
- `"union select"`
- `uid:ZTx1kH8AAQEAAB2gTkAAAAAB` — une requête
- `alert:c00007a0001F` — les requêtes d'une alerte du SOC
- `(category:sqli OR category:xss) sent:no -status:404`

Catégories : `sqli`, `xss`, `lfi`, `rfi`, `rce`, `php`, `java`, `fixation`, `generic`, `protocol`, `multipart`, `scanner`, `method`, `data-leakage`, `webshell`, et celles des règles de localSIEM : `bruteforce`, `enumeration`, `sensitive-file`, `db-error`, plus `health-*`.

Une erreur de syntaxe s'affiche sous le champ avec la position de l'erreur. Une recherche qui dépasse sa limite de temps (5 s) vous invite à restreindre la plage.

La page de résultats affiche :

- **L'histogramme** dans le temps ; la partie bleue de chaque barre correspond à ce que ModSecurity a bloqué. Faites glisser sur les barres (ou cliquez sur l'une d'elles) pour restreindre la plage.
- **Résumés** de la requête : IP avec le plus de requêtes, chemins les plus demandés, codes HTTP et règles les plus fréquentes. Cliquez sur une valeur pour l'ajouter à la requête.
- **Le tableau des résultats** (HEURE, SOURCE, IP, MÉTHODE, URI, CODE, ACTION, RÈGLES, ALERTE), du plus récent au plus ancien, avec «Charger plus».
- **Exporter** en CSV ou JSON (données masquées, jusqu'à 10 000 lignes, heures au format d'enregistrement `2026-10-29@13-59-59.723`) et **Copier le lien** (avec des heures absolues). Le format du lien est `/user/dashboard/search/?q=<query>&from=<native time>&to=<native time>` (`/admin/dashboard/search/...` quand il est copié par un administrateur) ; un lien de l'un ou l'autre tableau de bord fonctionne pour les deux rôles.

Chaque recherche et chaque export sont enregistrés (qui, quoi, quand) et visibles par les administrateurs : les journaux contiennent des données personnelles.

<a id="card"></a>
## 10. La fiche de la requête et les pivots

Cliquez sur une ligne pour ouvrir la fiche de la requête : heure, vhost, IP du client, méthode, URI, code, taille, durée, user agent, `UNIQUE_ID`, corrélation, action effectuée, moteur ModSecurity, phase, score et seuil, catégorie, gravité et alertes ; et, pour chaque enregistrement, son contenu analysé : les règles déclenchées avec leur message et leurs données, les en-têtes de la requête et le corps masqué, les en-têtes de la réponse, les lignes d'erreur et la ligne d'origine. Le module de chaque enregistrement ajoute ce qu'il sait afficher (le module Apache reconstitue les en-têtes et le corps à partir de l'enregistrement d'audit).

Remarques dans la fiche : un 403 sans aucune trace de ModSecurity est marqué comme **douteux** (il n'est pas compté comme un blocage) ; **corrélation faible** signifie que la ligne d'accès a été rattachée à sa requête par IP du client, méthode, URI, statut et heure, parce que le journal d'accès n'a pas d'`UNIQUE_ID` ; une **erreur de base de données** est apparue pour la requête.

Pivots : **Cette IP** (toute son activité), **±5 min** (la chronologie autour de la requête), **Règle …** (chaque règle déclenchée), **Cette catégorie**, **Cet UNIQUE_ID**.

<a id="live"></a>
## 11. Vue en direct

L'onglet **Direct** affiche les nouveaux événements dès que le collecteur les enregistre (après la fenêtre de corrélation de 5 secondes), les plus récents en haut. Le filtre utilise la syntaxe de la recherche. **Pause** interrompt les mises à jour ; à la reprise, l'affichage continue à partir de l'événement le plus récent.

<a id="alerts"></a>
## 12. Alertes

L'onglet **Alertes** liste les alertes générées par localSIEM : code SOC, gravité, règle, IP, vhost, nombre, première et dernière fois, et statut :

| Statut | Signification |
|---|---|
| En tampon | Regroupement de la rafale (60 s) avant le départ |
| En file d'attente | En attente du SOC (réseau coupé, SOC qui ne répond pas) |
| Envoyée | Acceptée par le SOC ; son code est affiché |
| Rejetée | Le SOC a refusé cette alerte ; le reste de la file continue. Elle peut être remise en file depuis Administration › SOC. |
| Non envoyée | Aucun SOC n'était configuré, ou l'envoi était désactivé : l'alerte reste dans localSIEM et n'est jamais envoyée par la suite (le SOC est facultatif, section 5) |

Cliquez sur une ligne pour voir la description, les **requêtes de l'alerte** (jusqu'à 50, les plus anciennes en premier, comme dans la recherche : cliquez sur l'une d'elles pour ouvrir sa fiche, avec la requête, ses en-têtes, les règles de ModSecurity et les lignes d'origine), la fenêtre, l'`external_id` et l'alerte exacte envoyée au SOC. **Rechercher** ouvre la recherche du groupe. Tant qu'une alerte est ouverte, la liste n'est pas actualisée.

<a id="modules"></a>
## 13. Modules

Dans le tableau de bord administrateur, l'onglet **Modules** comporte deux sections, chacune avec sa propre adresse : **Installés** (`/admin/dashboard/modules/installed/`), qui s'ouvre par défaut (`/admin/dashboard/modules/` y mène), et **Installables** (`/admin/dashboard/modules/installable/`), où les modules s'installent (ci-dessous). Les analystes n'ont que la liste des modules installés, sans sections (`/user/dashboard/modules/`).

**Installés** liste les modules installés, une ligne par module, sur toute la largeur, disposée comme l'en-tête de la page du module : en haut, le nom, l'id et la version et, en dessous, son **état**, un résumé, les raisons de son état et, s'il est activé, ses compteurs : sources en lecture, lignes de la dernière heure, dernières données, événements et requêtes bloquées des dernières 24 heures et résultat de son diagnostic. Les administrateurs voient aussi l'interrupteur à droite du nom et, en bas de la ligne, ses boutons. La page s'actualise toutes les 10 secondes. Sans aucun module installé, elle affiche «Installez des modules depuis l'onglet Installables.» (aux analystes : «Aucun module installé. Un administrateur les installe dans Modules › Installables.»).

| État | Signification |
|---|---|
| Activé et fonctionnel | Activé, chargé par le collecteur et en train de lire ses sources. Les avertissements du diagnostic sont listés comme des remarques et ne le changent pas. |
| Activé, avec des avertissements | Activé, mais sans sources, avec une source qui n'existe pas encore, ou installé après le démarrage du collecteur (redémarrez le service `localsiem`). |
| Erreur | Il ne se charge pas (la raison est affichée), son diagnostic signale une erreur, ou une source ne peut pas être lue (permissions de l'utilisateur `localsiem`, section 3.7). |
| Application du changement… | Vient d'être activé ou désactivé ; le collecteur applique le changement (quelques secondes). |
| Désactivé | Désactivé : localSIEM ne lit pas ses journaux et n'envoie pas ses alertes. Ce qui est déjà conservé reste. Avec la raison «Il manque à ce serveur ce dont il a besoin : …», il a été installé sans ses prérequis et ne peut pas encore être activé (voir Prérequis et Reconfigurer, ci-dessous). |
| Inconnu | Le collecteur n'est pas en marche (service `localsiem`) : personne ne lit rien. |

Les **analystes** ne voient que cette liste. Les **administrateurs** ont aussi, sur chaque ligne :

- **L'interrupteur** de chaque module, pour l'activer ou le désactiver. La désactivation demande une confirmation. Le changement s'applique immédiatement, sans rien redémarrer. Tant qu'il manque au serveur ce dont un module a besoin, son interrupteur est verrouillé («Désactivé : prérequis manquants»).
- **Configurer**, qui ouvre la page du module (`/admin/dashboard/modules/installed/<name>/` ; l'ancienne adresse `/admin/dashboard/modules/<name>/` y mène) :
  - l'en-tête avec l'état, le dossier où le module est installé, l'interrupteur, «Retour aux modules installés» (il ramène à Installés) et «Redécouvrir et lancer le diagnostic» ; pour un module avec des prérequis, aussi le bouton «Reconfigurer» et, tant que le module est désactivé ou qu'il en manque un, ses **Prérequis** (ci-dessous) ;
  - **Paramètres** : le formulaire des paramètres propres au module ; «Enregistrer les paramètres» les applique immédiatement ;
  - **Sources** : les journaux qu'il lit (type, chemin, vhost, lignes et lignes non analysées de la dernière heure, dernières données, état) et, en dessous, les journaux qu'il a trouvés mais ne lit pas, avec la raison ;
  - **Diagnostic** : ses vérifications des prérequis, avec l'extrait ou la commande qui corrige chacun de ceux qui manquent et un bouton «Copier» (les journaux sont seulement décrits) ;
  - **Règles** : chaque règle du module avec son interrupteur («Activée»), sa gravité, son seuil et sa fenêtre (seuil et fenêtre uniquement pour les règles de seuil et de séquence) ; «Enregistrer les règles» les applique immédiatement.
- **Mettre à jour**, quand le dépôt `localSIEM-modules` propose une version plus récente du module. Chaque fois que vous ouvrez Installés, localSIEM consulte le dépôt : pendant ce temps, il affiche «Recherche de versions plus récentes dans le dépôt…» et, si la vérification échoue, «Impossible de rechercher des versions plus récentes dans le dépôt : <erreur>», et la liste fonctionne normalement. Pour que le dépôt ne soit pas téléchargé à chaque visite, le navigateur réutilise sa réponse pendant 10 minutes ; «Consulter le dépôt», dans Installables, le télécharge toujours de nouveau, et l'installation, la mise à jour ou la désinstallation d'un module écarte la réponse conservée. L'actualisation toutes les 10 secondes ne le télécharge jamais. Un module qui a une version plus récente affiche, sur sa ligne, l'avis «Le dépôt propose la version X (la version installée est la Y).» avec le bouton **Mettre à jour**. Si cette version nécessite un localSIEM plus récent, l'avis n'a pas de bouton et l'indique : «Le dépôt propose la version X, mais elle nécessite localSIEM Z ou ultérieur : mettez à jour localSIEM pour l'installer.» **Mettre à jour** demande une confirmation («Mettre à jour le module») : localSIEM télécharge la nouvelle version depuis le dépôt, la substitue à la version installée et redémarre le collecteur ; ses paramètres sont conservés, et le module reste activé ou désactivé comme il l'était. Pendant l'opération, le bouton affiche «Mise à jour…» ; à la fin, un message indique «<module> mis à jour vers la version X.» Une boîte de dialogue, «<module> mis à jour», ne s'ouvre que s'il reste autre chose à faire : si la nouvelle version lit d'autres journaux, elle affiche la commande pour root (`manage.py setup-modules`, section 2, avec «Copier») ; si le collecteur n'a pas répondu, elle vous demande de redémarrer le service `localsiem`.
- **Désinstaller**, sur la ligne de chaque module installé (y compris d'un module qui ne se charge pas) et sur sa page. Après confirmation, localSIEM supprime `/opt/localsiem/modules/<name>/` et redémarre le collecteur sans lui : il cesse de lire ses journaux et d'envoyer ses alertes. Les événements et les alertes déjà conservés restent consultables par la recherche, et ses paramètres (et les modifications de ses règles) restent dans `settings.json`, si bien qu'ils reviennent si vous le réinstallez. L'accès en lecture que root a donné à `localsiem` sur ses journaux n'est pas retiré ; si aucun autre module ne lit ce dossier, vous pouvez le retirer manuellement, par exemple `setfacl -R -x g:localsiem /var/log/apache2` et `setfacl -d -x g:localsiem /var/log/apache2`.

**Installables** (administrateurs uniquement) comporte la carte «Modules installables» : les modules du dépôt `localSIEM-modules` (par défaut `https://github.com/PYMEHackers/localSIEM-modules`, branche `main` ; les options de l'installateur `--modules-repository` et `--modules-ref` le changent) qui ne sont pas encore installés sur ce serveur. «Consulter le dépôt» le télécharge et liste ces modules, chacun avec son nom, son id, sa version et son résumé, et son bouton ou sa remarque :

| Bouton ou remarque | Signification |
|---|---|
| Prérequis | Affiche ce dont le module a besoin sur le serveur et les commandes qui l'installent (ci-dessous) |
| Installer | Installe le module |
| Nécessite localSIEM X ou ultérieur | Il ne peut pas être installé : mettez d'abord à jour localSIEM |
| Le module du dépôt n'est pas valide | Il ne peut pas être installé |

**Prérequis** ouvre la boîte de dialogue «<module> : prérequis», avec ce dont le module a besoin sur le serveur et les commandes qui l'installent, déclarés par le module lui-même (`install_requirements` de son `module.json`). L'installation d'un module n'installe jamais le logiciel qu'il surveille : exécutez-les donc sur le serveur **avant** d'installer le module. La boîte de dialogue affiche les commandes pour le système de ce serveur («Ce serveur : Debian GNU/Linux 13 (trixie)») deux fois, chacune avec «Copier» : **En tant que root** et **Avec sudo** (les mêmes commandes précédées de `sudo`), pour que vous puissiez les coller dans un terminal du serveur en tant que root ou en tant qu'utilisateur autorisé à utiliser sudo. Les remarques du module viennent en premier (par exemple, qu'Alpine n'a pas de paquet ModSecurity 2). Si le module ne déclare aucune commande pour le système de ce serveur, la boîte de dialogue affiche celles de chaque système qu'il déclare (Debian et Alpine) ; s'il n'en déclare aucune, elle affiche «Ce module ne déclare rien à installer sur le serveur.». localSIEM n'exécute jamais ces commandes.

Si tous les modules du dépôt sont déjà installés, elle l'indique («Tous les modules du dépôt sont déjà installés.»). Les modules déjà installés n'apparaissent jamais dans cette liste : ils se mettent à jour dans Installés (**Mettre à jour**, ci-dessus). L'interface web ne réinstalle pas un module et n'en installe pas une version plus ancienne : pour réinstaller un module, désinstallez-le et installez-le de nouveau ici (ses paramètres sont conservés).

Cette liste est le seul moyen d'installer des modules. localSIEM télécharge le module, vérifie son `module.json`, copie son dossier (`mod-<name>/` dans le dépôt) dans `/opt/localsiem/modules/<name>/` (sans son dossier `tests/` ; un module réinstallé retrouve les paramètres qu'il avait) et redémarre le collecteur, qui le charge en quelques secondes. Le module quitte la liste et une boîte de dialogue, «<module> installé», indique la suite :

- Permettre à `localsiem` de lire les journaux du module nécessite root ; la boîte de dialogue affiche donc **la commande à exécuter en tant que root** sur le serveur, avec un bouton «Copier» : `manage.py setup-modules` (section 2), qui donne l'accès en lecture et redémarre localSIEM. Tant que la commande n'a pas été exécutée, le module peut afficher «Erreur» parce que ses journaux ne peuvent pas être lus.
- Si, lors de sa première installation, il manque au serveur ce dont le module a besoin, le module est installé désactivé et la boîte de dialogue liste ce qui manque à la place de la commande, avec l'indication d'ouvrir le module dans Installés (**Configurer**) et de cliquer sur **Reconfigurer** une fois ce logiciel installé (ci-dessous).

La boîte de dialogue a deux boutons : «Fermer» et «Voir les modules installés», qui ouvre Installés. Le serveur doit pouvoir joindre GitHub (HTTPS) pour cette liste et pour la vérification des versions plus récentes dans Installés.

**Prérequis et Reconfigurer.** L'installation d'un module n'installe jamais le logiciel qu'il surveille. Un module peut déclarer ce que le serveur doit avoir avant de pouvoir l'activer : le module Apache a besoin d'Apache (sa configuration : `apache2.conf`, `httpd.conf` ou le fichier du paramètre **Fichier de configuration d'Apache**) et de ModSecurity 2 chargé (`mod_security2` ; ModSecurity 3 ne compte pas). S'ils manquent lors de sa première installation, le module est installé **désactivé** («Désactivé», avec la raison «Il manque à ce serveur ce dont il a besoin : …») et son interrupteur est **verrouillé**. Sa page liste ses prérequis comme le diagnostic (titre, détail et commande qui installe ce qui manque, avec «Copier»), y compris tant qu'il est désactivé. Une fois que vous avez installé ce qui manque (et, si Apache se trouve à un emplacement non standard, renseigné le **Fichier de configuration d'Apache** et enregistré les paramètres), cliquez sur **Reconfigurer** : localSIEM le recherche de nouveau avec les paramètres enregistrés.

- S'il trouve tout, il déverrouille l'interrupteur mais n'active pas le module : c'est vous qui l'activez avec son interrupteur. Il affiche aussi la commande pour root de la section 2 : exécutez-la, car les journaux créés après l'installation du module (`/var/log/apache2`) ne peuvent être lus qu'avec l'accès en lecture que donne root.
- S'il manque encore quelque chose, les prérequis l'affichent de nouveau.
- Si le module est déjà activé, Reconfigurer redécouvre aussi ses sources et lance son diagnostic.

Un module activé qui perd ensuite ses prérequis (quelqu'un désinstalle ModSecurity) reste activé : son diagnostic et l'avertissement de santé «ModSecurity is no longer loaded» (section 15) le signalent, et le désactiver ferait taire précisément cet avertissement. Le collecteur vérifie les prérequis à son démarrage et quand ses paramètres changent, jamais périodiquement ; `manage.py modules` et `manage.py doctor` les affichent aussi (section 17).

**Désactiver et réactiver le module Apache.** Dans **Modules › Installés**, utilisez l'interrupteur d'«Apache + ModSecurity» et confirmez. Tant qu'il est désactivé, localSIEM ne lit pas les journaux d'Apache, n'exécute ni son diagnostic ni ses règles et n'envoie aucune alerte de sa part ; les événements déjà conservés restent consultables par la recherche. Réactivez l'interrupteur pour reprendre (possible uniquement tant qu'Apache et ModSecurity sont présents) : le collecteur reprend à la position où il s'était arrêté dans chaque journal (en suivant les rotations effectuées entre-temps), de sorte qu'il lit aussi ce qu'Apache a écrit pendant que le module était désactivé et envoie les alertes qui en découlent.

**Paramètres du module Apache** (Modules › Installés › Apache + ModSecurity › Configurer) :

| Paramètre | Usage |
|---|---|
| Uniquement les sources ci-dessous | Ne pas découvrir les journaux à partir de la configuration d'Apache : lire uniquement les sources ajoutées manuellement |
| Sources ajoutées manuellement | Journaux à lire en plus de ceux découverts (voir ci-dessous) |
| Fichier de configuration d'Apache | Vide : détecté automatiquement (`/etc/apache2/apache2.conf` sur Debian, `/etc/apache2/httpd.conf` sur Alpine). Reconfigurer y recherche aussi Apache |
| Intervalle de découverte (secondes) | Fréquence à laquelle la configuration d'Apache est relue pour trouver de nouveaux vhosts et journaux (par défaut 3600) |
| Seuil de blocage de ModSecurity | 0 : lu dans la configuration du CRS (`tx.inbound_anomaly_score_threshold`), 5 s'il n'y figure pas |
| Jours d'apprentissage pour les nouveaux fichiers PHP | Pendant les premiers jours, un fichier PHP jamais vu auparavant n'est pas signalé comme nouveau (règle `apache-webshell` ; par défaut 3) |

**Ajouter un journal manuellement.** Dans **Sources ajoutées manuellement**, cliquez sur «Ajouter une source» et renseignez **Type** (access.log, error.log ou Journal d'audit de ModSecurity), **Chemin** (absolu) et, si nécessaire, **Vhost**, **LogFormat** (pour un journal d'accès dans un format qui lui est propre), **Type de journal d'audit** (Série ou Concurrent) et **Dossier de stockage de l'audit** (pour un journal d'audit concurrent). «Retirer» supprime une source. Cliquez sur «Enregistrer les paramètres» : le collecteur redécouvre immédiatement les sources et le nouveau journal apparaît dans **Sources**. S'il apparaît comme illisible, donnez à `localsiem` l'accès en lecture à son dossier (section 3.7).

**Du module `apache` à `apache2`.** Jusqu'à localSIEM 2.1, le module Apache s'appelait `apache` ; il s'appelle désormais `apache2` (dossier `mod-apache2/` dans le dépôt, installé dans `/opt/localsiem/modules/apache2/`, page `/admin/dashboard/modules/installed/apache2/`). Sur un serveur qui avait `apache`, installer `apache2` laisse les deux chargés : l'ancien garde les journaux d'Apache (les deux trouvent les mêmes sources), `apache2` n'affiche aucune source tant que l'ancien n'est pas désinstallé, et les paramètres d'`apache` ne sont pas transférés d'eux-mêmes. Pour migrer :

1. Notez les paramètres que vous avez modifiés dans la page du module `apache` (Configurer) : sources ajoutées manuellement, fichier de configuration d'Apache, intervalle de découverte, seuil de blocage, jours d'apprentissage.
2. Installez `apache2` dans Modules › Installables.
3. Désinstallez le module `apache` : **Désinstaller**, sur sa ligne dans Modules › Installés ou sur sa page. Le collecteur redémarre et `apache2` lit dès lors les journaux d'Apache.
4. Ouvrez la page d'`apache2`, saisissez de nouveau ces paramètres et enregistrez-les. (Vous pouvez aussi, en tant que root, copier dans `/opt/localsiem/config/settings.json`, à l'intérieur de `"modules"`, ce qui se trouve sous `"apache"` vers `"apache2"`, puis redémarrer localSIEM.)

Les règles conservent leurs id (`apache-bruteforce`…) et leurs modifications, et les positions lues dans chaque journal ainsi que la mémoire des avertissements de santé sont conservées : `apache2` reprend là où `apache` s'est arrêté, sans rien lire deux fois. Les événements conservés par le module `apache` restent consultables par la recherche (`module:apache`).

<a id="administration"></a>
## 14. Administration

Ces onglets ne se trouvent que dans le tableau de bord administrateur :

- **Modules** (section 13), en deux sections : **Installés** (`/admin/dashboard/modules/installed/`), la liste avec l'interrupteur de chaque module, **Configurer** (prérequis et Reconfigurer, paramètres, sources, diagnostic et règles du module), **Mettre à jour** (quand le dépôt propose une version plus récente) et **Désinstaller** ; et **Installables** (`/admin/dashboard/modules/installable/`), les modules du dépôt pas encore installés, avec **Prérequis** et **Installer**. Les modules s'installent, se mettent à jour et se désinstallent uniquement à cet endroit.
- **Utilisateurs › Comptes** (`/admin/dashboard/users/accounts/`) : créer des comptes (un mot de passe est généré et affiché une seule fois ; il doit être changé à la première connexion), réinitialiser le mot de passe ou la vérification en deux étapes, activer ou désactiver, changer le rôle, supprimer. Il y a toujours au moins un administrateur actif.
- **Utilisateurs › Jetons d'accès** (`/admin/dashboard/users/tokens/`) : **Créer un jeton** pour un compte d'analyste actif (les administrateurs se connectent toujours avec leur mot de passe, et avec le second facteur quand la vérification en deux étapes est activée), avec un libellé facultatif et une validité de 7, 30, 90 (par défaut), 180 ou 365 jours. L'URL d'accès, `https://<server>:10443/auth/login/auto?token=...`, n'est affichée **qu'une seule fois**, avec un bouton «Copier» : remettez-la à l'analyste (section 6). La liste affiche le compte et le libellé de chaque jeton, ses 4 derniers caractères, son état (Actif, Expiré, Révoqué, ou Inutilisable quand le compte est désactivé ou n'est plus un compte d'analyste), quand et par qui il a été créé, quand il expire et sa dernière utilisation (heure et IP). **Révoquer** l'arrête immédiatement ; les sessions qu'il a déjà ouvertes prennent fin à leur expiration. Une session ouverte avec un jeton ne demande ni le second facteur ni un changement de mot de passe. Les tentatives échouées comptent pour le blocage temporaire de la connexion.
- **SOC** : URL, jeton (jamais affiché en entier), fichier de CA facultatif, **Tester la connexion** (envoie un signal de vie), état de l'envoi, dernier signal de vie, dernière erreur, file (en attente, envoyées, rejetées) et **Envoyer la file maintenant**. Également l'adresse du SIEM à communiquer au SOC. Le SOC est facultatif (section 5).
- **Canaux** (`/admin/dashboard/channels/`), en deux sections, **Général** (ouverte par défaut) et **Telegram** : les messages que localSIEM vous envoie, en plus des alertes qu'il transmet au SOC (ci-dessous).
- **Paramètres** : rétention, taille maximale sur disque, IP autorisées (votre propre adresse doit figurer dans la liste), vérification en deux étapes (désactivée par défaut ; l'activer la rend obligatoire pour tous les comptes et déconnecte immédiatement les comptes qui ne l'ont pas encore configurée, y compris le vôtre, qui la configurent à leur prochaine connexion ; la désactiver conserve les applications d'authentification déjà configurées pour le jour où elle sera réactivée), durée maximale d'une recherche, limite d'export, fenêtre de regroupement et tampon, fenêtre de corrélation et gravité sous le seuil. Les changements s'appliquent immédiatement. Les règles ne se trouvent plus ici : elles se configurent dans chaque module (Modules › Installés › Configurer).
- **Audit des recherches** : qui a recherché quoi et quand.
- **Connexions** (`/admin/dashboard/logins/`) : chaque connexion à localSIEM et chaque tentative échouée, des plus récentes aux plus anciennes : heure, compte, méthode (Mot de passe, Mot de passe et second facteur, ou Jeton d'accès), résultat (Réussie ou Échouée), raison d'un échec (nom d'utilisateur ou mot de passe incorrect, code du second facteur incorrect, bloquée après plusieurs échecs, la connexion a pris trop de temps, jeton inconnu, expiré ou révoqué, compte désactivé, le compte n'est pas un compte d'analyste), IP et navigateur. Filtrez par résultat ; **Charger plus** charge les plus anciennes. Elles sont conservées aussi longtemps que les alertes (365 jours par défaut).

L'état du collecteur, du disque et de la base de données se trouve dans la Vue d'ensemble (section 8).

### Canaux : messages qui vous sont destinés (Telegram)

En plus de transmettre toutes les alertes au SOC, localSIEM peut vous envoyer les plus importantes via un **canal**. Pour l'instant, le canal est **Telegram**.

**Général** (`/admin/dashboard/channels/general/`) :

- **Envoyer des messages via les canaux** : active ou désactive tous les canaux à la fois.
- **Gravité minimale** : les alertes de cette gravité ou supérieure sont envoyées (par défaut : Élevée).
- **Langue des messages** : n'importe laquelle des 15 langues de l'interface web (par défaut en-US). La règle et la description de l'alerte restent telles que localSIEM les a écrites.
- Un tableau avec chaque canal : son état (Désactivé, Non configuré, En fonctionnement ou Erreur), les messages envoyés, le dernier envoyé et la dernière erreur.

**Telegram** (`/admin/dashboard/channels/telegram/`) :

1. Dans Telegram, ouvrez **@BotFather**, envoyez `/newbot` et suivez ses étapes. Il vous donne le **jeton du bot** (`123456789:AA...` ; le nombre avant les deux-points est l'id du bot).
2. Ouvrez le chat avec votre bot et appuyez sur **Démarrer** (ou ajoutez le bot au groupe, ou en tant qu'administrateur du canal, qui recevra les messages) : un bot ne peut pas écrire à quelqu'un qui ne lui a pas parlé en premier.
3. Trouvez l'**ID du chat** : envoyez n'importe quel message au bot et ouvrez `https://api.telegram.org/bot<token>/getUpdates` dans un navigateur ; l'ID est le nombre qui suit `"chat":{"id":`. L'ID d'un groupe commence par `-` et celui d'un canal par `-100` ; un canal ou un groupe public peut aussi être indiqué sous la forme `@username`.
4. Saisissez le jeton et l'ID du chat, cochez **Envoyer les messages via Telegram** et cliquez sur **Enregistrer et envoyer un message de test**. Si Telegram le refuse, l'avis en indique la raison (par exemple `Unauthorized` : jeton incorrect ; `Bad Request: chat not found` : ID du chat incorrect, ou personne n'a appuyé sur Démarrer).

Le jeton est conservé sur le serveur dans `/opt/localsiem/config/telegram-bot-token` (mode 600) et n'est jamais affiché en entier ; **Supprimer le jeton** le supprime et désactive Telegram. Le serveur doit pouvoir joindre `https://api.telegram.org` (port 443 sortant).

Chaque message indique la gravité, la règle, la description, le module, le nombre d'événements, la première et la dernière fois (UTC) et la recherche qui les affiche. localSIEM envoie au maximum un message par seconde. Si Telegram ne répond pas, il réessaie quelques fois ; si Telegram refuse un message (jeton incorrect, chat inconnu, bot bloqué), il l'abandonne et affiche l'erreur. Les messages en attente sont perdus si localSIEM redémarre : les canaux sont une notification pour vous, et le SOC reçoit toujours toutes les alertes.

<a id="health"></a>
## 15. Avertissements de santé et que faire

Ils vont aussi au SOC (règles `localSIEM health: …`), regroupés pour ne pas se répéter :

| Avertissement | Gravité | Que faire |
|---|---|---|
| Journal tronqué, disparu ou remplacé en dehors d'une rotation | élevée | Quelqu'un est peut-être en train d'effacer des traces. Vérifiez qui avait accès au serveur à ce moment-là, ainsi que ses autres journaux. |
| ModSecurity n'est plus chargé, ou moteur passé à Off | élevée | Si personne ne l'a fait volontairement, la protection a été désactivée : vérifiez la configuration d'Apache et ses modifications récentes. |
| Source de journal illisible | moyenne | Généralement des permissions après une rotation : exécutez de nouveau en tant que root la commande de la section 2 (`manage.py setup-modules`) ou donnez à `localsiem` l'accès en lecture (section 3.7). Seul un journal que localSIEM pouvait lire auparavant le déclenche : un journal qu'il n'a jamais pu lire (un module tout juste installé, avant la commande de la section 2) n'apparaît que dans l'état du module («Erreur», une source ne peut pas être lue). |
| Source de journal silencieuse depuis longtemps (24 h) | moyenne | Vérifiez qu'Apache écrit toujours dans ce fichier (changements de journalisation, disque plein). |
| IP réelle du client manquante | moyenne | Presque toutes les requêtes proviennent d'une seule adresse privée : le site web est derrière un proxy et Apache journalise son IP, si bien que les règles par IP ne fonctionnent pas pour ces requêtes. |
| Nombreuses lignes non analysées (plus de 5 %) | faible | Le format du journal a changé : dans la page du module (Modules › Installés › Configurer), cliquez sur «Redécouvrir et lancer le diagnostic», pour que le module lise le nouveau format ; le diagnostic décrit le format de chaque journal. |
| Peu d'espace disque libre, ou rétention réduite faute de place | moyenne | Libérez de l'espace ou augmentez la taille maximale sur disque. localSIEM conserve moins de détails entre-temps. |

<a id="retention"></a>
## 16. Rétention et disque

Les événements sont conservés 90 jours et les alertes 365 jours. La base de données ne dépasse jamais son maximum (par défaut : la plus petite valeur entre 15 % du disque et 10 Go) : les événements les plus anciens sont supprimés en premier, par petits lots, et l'espace est rendu au disque. Avec peu d'espace disque libre, localSIEM cesse de conserver le détail volumineux (en-têtes et corps des enregistrements d'audit) ; quand il n'en reste presque plus, il ne conserve que les événements qui font partie d'une alerte, et il prévient le SOC. Modifiez les valeurs avec `--retention-days` et `--max-disk` (par exemple `--max-disk 5G`) ou dans Administration › Paramètres.

<a id="cli"></a>
## 17. Ligne de commande

En tant que root, `/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py` :

| Commande | Usage |
|---|---|
| `list-users` | Comptes et leur vérification en deux étapes |
| `create-user NAME --role admin\|analyst --credentials /root/webapp-credentials.txt` | Nouveau compte avec un mot de passe généré |
| `reset-password NAME --credentials /root/webapp-credentials.txt` | Nouveau mot de passe (à changer à la prochaine connexion) |
| `reset-mfa NAME` | Vérification en deux étapes à reconfigurer à la prochaine connexion |
| `doctor` (`--json`) | Prérequis et sources de chaque module activé et, pour un module désactivé qui a des prérequis, ce dont il a besoin avant de pouvoir être activé (exécutez-le en tant que `localsiem`, section 4) |
| `modules` | Modules installés : nom, version, activé, désactivé ou non chargé, dossier, et sous un module les prérequis qui manquent au serveur pour lui ; ainsi que les modules qui ne peuvent pas être chargés, avec la raison |
| `read-paths` | Dossiers que lisent les modules installés (`setup-modules` et l'installateur donnent à `localsiem` l'accès en lecture à ces dossiers) |
| `soc-test` | Envoie un signal de vie au SOC |
| `setup-modules` | En tant que root, la commande que l'interface web affiche après l'installation d'un module, après une mise à jour qui change les journaux que lit le module, et avec Reconfigurer : accès en lecture pour `localsiem` aux dossiers des modules installés (ACL, y compris pour les prochaines rotations ; le groupe `adm` sur Debian), redémarrage de localSIEM et diagnostic en tant que `localsiem`. Avec `--no-restart` (ce qu'utilise l'installateur), elle donne seulement l'accès en lecture. |

Les modules s'installent, se mettent à jour et se désinstallent uniquement depuis l'interface web (section 13) : il n'existe pas de commande pour cela.

Services : localSIEM fonctionne sous la forme de deux services de l'utilisateur système `localsiem`, le collecteur (`localsiem`) et l'interface web (`localsiem-web`). `systemctl status localsiem localsiem-web` les affiche et `systemctl restart localsiem localsiem-web` les redémarre (Debian), ou `rc-service localsiem status; rc-service localsiem-web status` et `rc-service localsiem restart; rc-service localsiem-web restart` (Alpine) ; redémarrez les deux après avoir copié ou supprimé manuellement un module dans `/opt/localsiem/modules/` (l'interface web le fait d'elle-même quand elle installe, met à jour ou désinstalle un module). Journaux : `journalctl -u localsiem -u localsiem-web` (Debian) ou `/opt/localsiem/log/` (Alpine) ; au démarrage, le collecteur journalise la ligne `Modules: ...` avec chaque module, sa version et s'il est activé ou désactivé, et `Module <name>: requirements missing: ...` pour un module dont les prérequis manquent.

**Fichiers sur le serveur**

| Chemin | Contenu |
|---|---|
| `/opt/localsiem/webapp/` | Code du noyau |
| `/opt/localsiem/modules/` | Modules installés, un dossier chacun (`apache2/`), installés par l'interface web depuis `localSIEM-modules` |
| `/opt/localsiem/venv/` | Dépendances Python (séparées de celles du système) |
| `/opt/localsiem/config/` | Paramètres, options de l'installateur (`install.env`), jeton du SOC et secrets (mode 600) |
| `/opt/localsiem/db/` | Bases de données |
| `/opt/localsiem/certificates/` | Certificat de l'interface web |
| `/opt/localsiem/log/`, `/opt/localsiem/run/` | Journaux (Alpine) et fichiers d'exécution |
| `/root/webapp-install.log`, `/root/webapp-credentials.txt` | Journal de l'installateur et mots de passe qu'il a créés (mode 600) |
