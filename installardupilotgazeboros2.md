# Installation ArduPilot SITL + ROS 2 Humble + Gazebo Harmonic (Linux)

Guide compilé à partir des docs officielles ArduPilot, ROS 2 et Gazebo, incluant les pièges rencontrés sur le terrain.

## 0. Conditions nécessaires (avant de commencer)

| Condition | Valeur requise | Pourquoi |
|---|---|---|
| OS | Ubuntu 22.04 (Jammy) natif ou WSL2 | ROS 2 Humble n'est packagé que pour Jammy. Harmonic supporte 22.04 et 24.04, mais Humble force le 22.04. |
| ROS 2 | **Humble desktop** (pas base, sauf sur un Pi) | Seule version supportée par ArduPilot ROS 2. `desktop` inclut RViz et les demos. |
| Gazebo | **Harmonic** (PAS Garden) | Version recommandée par ardupilot_gz. `export GZ_VERSION=harmonic` obligatoire. |
| ArduPilot | 4.6+ pour DDS natif (branche master via ros2.repos) | Le support DDS/ROS2 complet arrive en 4.6. La page ros2-sitl a des variantes 4.5 / 4.6 : voir §5. |
| Java | JRE (default-jre) | Requis pour builder Micro-XRCE-DDS-Gen (gradle). |
| GPU | Accélération OpenGL matérielle | Le rendu logiciel rend Gazebo inutilisable. Vérifier avec `glxinfo | grep "OpenGL renderer"`. |
| Réseau | Connexion stable | Le gros build colcon (ardupilot_gz et cie) télécharge beaucoup; une coupure fait échouer le build. Relancer la commande complète en cas d'échec. |
| Divers | git, curl, ~20 Go disque libre | Clones avec submodules + builds. |

Ordre strict des étapes : **ArduPilot build env → ROS 2 Humble → Gazebo Harmonic → workspace ROS 2 ArduPilot (DDS) → SITL+ROS2 → ardupilot_gz**. Chaque étape a une commande de validation : ne pas passer à la suivante sans l'avoir exécutée.

---

## 1. Environnement de build ArduPilot

Source : [Building setup Linux](https://ardupilot.org/dev/docs/building-setup-linux.html)

```bash
sudo apt-get update
sudo apt-get install git gitk git-gui
```

Clone avec submodules (fork perso ou repo officiel) :

```bash
git clone --recurse-submodules https://github.com/ArduPilot/ardupilot.git
cd ardupilot
```

Installation des prérequis :

```bash
Tools/environment_install/install-prereqs-ubuntu.sh -y
. ~/.profile
```

> **PIÈGE — profil non permanent** : `. ~/.profile` ne vaut que pour le shell courant. **Reboot (ou logout/login) obligatoire** pour que le PATH (waf, sim_vehicle.py) soit permanent. Sans ça, `sim_vehicle.py` introuvable dans les nouveaux terminaux.

> Note : si le clone se fait plus tard via `vcs import` dans le workspace ROS 2 (§4), relancer `./Tools/environment_install/install-prereqs-ubuntu.sh -y` depuis `~/ardu_ws/src/ardupilot`. Le script ne supporte pas les Ubuntu en fin de support (20.04 exclu).

**Validation** : build SITL + premier vol simulé.

```bash
./waf configure --board sitl
./waf copter
cd ArduCopter
../Tools/autotest/sim_vehicle.py --map --console
```

Si la console MAVProxy s'ouvre et que le drone apparaît sur la carte, l'étape est bonne. `Ctrl+C` pour quitter.

---

## 2. ROS 2 Humble (paquets deb — PAS la compilation depuis les sources)

Source : [Ubuntu (deb packages) — ROS 2 Humble](https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html)

> **PIÈGE — mauvaise méthode d'installation** : ne pas suivre le lien "installation" proposé par défaut ailleurs (build from source, très long). Utiliser les **paquets deb** ci-dessous. Prendre `ros-humble-desktop` partout sauf sur un Raspberry Pi (`ros-humble-ros-base`).

Locale UTF-8 :

```bash
locale  # vérifier UTF-8
sudo apt update && sudo apt install locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8
```

Dépôt universe + source apt ROS 2 (méthode actuelle via le paquet `ros2-apt-source`) :

```bash
sudo apt install software-properties-common curl
sudo add-apt-repository universe

export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}')
curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"
sudo dpkg -i /tmp/ros2-apt-source.deb
```

Installation :

```bash
sudo apt update && sudo apt upgrade
sudo apt install ros-humble-desktop ros-dev-tools
```

Ajout au bashrc (à faire une seule fois) :

```bash
echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
source ~/.bashrc
```

> **PIÈGE — bashrc corrompu** : vérifier le contenu de `~/.bashrc` après chaque `echo >> ~/.bashrc` (typos, `$` non échappés, lignes dupliquées). Ouvrir le fichier et confirmer que les lignes ajoutées sont exactement celles attendues. Une ligne croche dans le bashrc casse silencieusement tous les shells suivants.

**Validation obligatoire — l'exemple talker/listener** (deux terminaux) :

```bash
# Terminal 1
ros2 run demo_nodes_cpp talker
# Terminal 2
ros2 run demo_nodes_py listener
```

Le talker publie `Hello World: N` et le listener les reçoit. Si ça marche, C++ et Python fonctionnent et les DDS discovery locales sont bonnes. Ne pas continuer sans ce test.

---

## 3. Gazebo Harmonic

Source : [Binary Installation on Ubuntu — Gazebo Harmonic](https://gazebosim.org/docs/harmonic/install_ubuntu/)

> **PIÈGE — mauvaise version** : installer **gz-harmonic**, pas Gazebo Garden, pas gazebo-classic (gazebo11). Les paquets s'appellent `gz-*`, l'exécutable est `gz sim`.

```bash
sudo apt-get update
sudo apt-get install curl lsb-release gnupg

sudo curl https://packages.osrfoundation.org/gazebo.gpg --output /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] https://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null
sudo apt-get update
sudo apt-get install gz-harmonic
```

Variable d'environnement requise par ardupilot_gz (à mettre dans le bashrc) :

```bash
echo "export GZ_VERSION=harmonic" >> ~/.bashrc
source ~/.bashrc
```

**Validation** :

```bash
gz sim shapes.sdf
```

La fenêtre Gazebo doit s'ouvrir avec des formes 3D, fluide (sinon problème OpenGL/GPU).

---

## 4. Workspace ROS 2 + ArduPilot (DDS)

Source : [ROS 2 — ArduPilot dev](https://ardupilot.org/dev/docs/ros2.html)

Création du workspace et import des repos :

```bash
mkdir -p ~/ardu_ws/src
cd ~/ardu_ws
vcs import --recursive --input https://raw.githubusercontent.com/ArduPilot/ardupilot/master/Tools/ros2/ros2.repos src
```

Dépendances :

```bash
cd ~/ardu_ws
sudo apt update
rosdep update
source /opt/ros/humble/setup.bash
rosdep install --from-paths src --ignore-src -r -y
```

Prérequis ArduPilot dans le workspace :

```bash
cd ~/ardu_ws/src/ardupilot
./Tools/environment_install/install-prereqs-ubuntu.sh -y
```

Micro-XRCE-DDS-Gen (générateur DDS, nécessite Java) :

```bash
sudo apt install default-jre
cd ~/ardu_ws
git clone --recurse-submodules --branch v4.7.0 https://github.com/ardupilot/Micro-XRCE-DDS-Gen.git
cd Micro-XRCE-DDS-Gen
./gradlew assemble
echo "export PATH=\$PATH:$PWD/scripts" >> ~/.bashrc
source ~/.bashrc
```

> **PIÈGE — bashrc encore** : la ligne ci-dessus contient un `\$PATH` échappé et un `$PWD` non échappé. C'est voulu : `$PWD` doit être résolu au moment de l'écriture, `$PATH` au moment du source. Vérifier dans `~/.bashrc` que la ligne finale ressemble à `export PATH=$PATH:/home/<user>/ardu_ws/Micro-XRCE-DDS-Gen/scripts`.

**Validation intermédiaire** :

```bash
microxrceddsgen -help
```

Build du workspace :

```bash
cd ~/ardu_ws
colcon build --packages-up-to ardupilot_dds_tests
```

> **PIÈGE — gros build qui plante** : ce build (et surtout celui du §6) est long et télécharge des paquets. Un échec réseau laisse des paquets manquants. **Relancer la même commande `colcon build`** : elle reprend et comble ce qui manque. Ne pas paniquer au premier fail.

**Validation** :

```bash
cd ~/ardu_ws
source ./install/setup.bash
colcon test --executor sequential --parallel-workers 0 --base-paths src/ardupilot
colcon test-result --all --verbose
```

---

## 5. SITL + ROS 2 (DDS)

Source : [ROS 2 with SITL](https://ardupilot.org/dev/docs/ros2-sitl.html)

Build du package SITL puis source :

```bash
cd ~/ardu_ws
colcon build --packages-up-to ardupilot_sitl
source install/setup.bash
```

> **PIÈGE — version du code sur la page** : la page a deux variantes (ArduPilot 4.5 / ArduPilot 4.6+). Sur ArduPilot ≥ 4.6 (dont `master` 4.8-dev), utiliser la **variante 4.6+, sans `refs`** : le fichier `dds_xrce_profile.xml` n'existe plus (les entités DDS sont créées par le firmware) et le passer fait mourir l'agent micro-ROS (`reference file ... does not exist`). Vérifié le 2026-09-29 sur `master` : session établie, 18 topics `/ap/*`.

Launch SITL avec DDS sur UDP :

```bash
source /opt/ros/humble/setup.bash
cd ~/ardu_ws/
source install/setup.bash
ros2 launch ardupilot_sitl sitl_dds_udp.launch.py \
transport:=udp4 \
synthetic_clock:=True \
wipe:=False \
model:=quad \
speedup:=1 \
slave:=0 \
instance:=0 \
defaults:=$(ros2 pkg prefix ardupilot_sitl)/share/ardupilot_sitl/config/default_params/copter.parm,$(ros2 pkg prefix ardupilot_sitl)/share/ardupilot_sitl/config/default_params/dds_udp.parm \
sim_address:=127.0.0.1 \
master:=tcp:127.0.0.1:5760 \
sitl:=127.0.0.1:5501
```

**Validation** (autre terminal, workspace sourcé) :

```bash
ros2 node list          # doit montrer /ap
ros2 node info /ap
ros2 topic echo /ap/geopose/filtered
```

Dépannage DDS : `param set DDS_ENABLE 1` dans MAVProxy (puis reboot du SITL), et vérifier que `DDS_DOMAIN_ID` (param ArduPilot) == `ROS_DOMAIN_ID` (env, défaut 0 des deux bords).

Pour un SITL manuel hors launch file :

```bash
export PATH=$PATH:~/ardu_ws/src/ardupilot/Tools/autotest
sim_vehicle.py -w -v ArduCopter --console -DG --enable-DDS
```

---

## 6. ArduPilot + Gazebo + ROS 2 (ardupilot_gz)

Source : [ROS 2 with Gazebo](https://ardupilot.org/dev/docs/ros2-gazebo.html)

Import des repos Gazebo dans le même workspace :

```bash
cd ~/ardu_ws
vcs import --input https://raw.githubusercontent.com/ArduPilot/ardupilot_gz/main/ros2_gz.repos --recursive src
```

Sources rosdep pour Gazebo + dépendances :

```bash
sudo wget https://raw.githubusercontent.com/osrf/osrf-rosdep/master/gz/00-gazebo.list -O /etc/ros/rosdep/sources.list.d/00-gazebo.list
rosdep update
cd ~/ardu_ws
source /opt/ros/humble/setup.bash
sudo apt update
rosdep install --from-paths src --ignore-src -y
```

(Le dépôt apt osrfoundation est déjà configuré depuis le §3. `GZ_VERSION=harmonic` doit être actif — vérifier avec `echo $GZ_VERSION`.)

Le gros build :

```bash
cd ~/ardu_ws
colcon build --packages-up-to ardupilot_gz_bringup
```

> **PIÈGE — build qui fail la première fois** : c'est LE build qui a échoué à la première tentative (réseau probable). Relancer la même commande jusqu'à un build propre; colcon reprend où il était et récupère les paquets manquants. Si une erreur persiste après 2-3 relances, lire l'erreur réelle dans `log/latest_build/`.

Tests :

```bash
cd ~/ardu_ws
source install/setup.bash
colcon test --packages-select ardupilot_sitl ardupilot_dds_tests ardupilot_gazebo ardupilot_gz_applications ardupilot_gz_description ardupilot_gz_gazebo ardupilot_gz_bringup
colcon test-result --all --verbose
```

**Validation finale — l'exemple iris_runway** (SITL + Gazebo + RViz en une commande) :

```bash
source install/setup.bash
ros2 launch ardupilot_gz_bringup iris_runway.launch.py
```

Gazebo s'ouvre avec l'iris sur la piste, RViz affiche le modèle, et `ros2 topic list` montre les topics `/ap/*`. Test de vol via MAVProxy :

```bash
mavproxy.py --console --map --aircraft test --master=:14550
# puis : mode guided / arm throttle / takeoff 5
```

---

## 7. Cas WSL2 (référence Windows)

Source : [SITL on Windows WSL](https://ardupilot.org/dev/docs/sitl-on-windows-wsl.html)

Quasi identique au Linux natif une fois Ubuntu 22.04 installé dans WSL2. Différences : Windows 10 requiert VcXsrv/XWindows pour les GUI (Windows 11 a WSLg natif); si `.wslconfig` contient `networkingMode = mirrored`, ajouter `--no-wsl2-network` aux commandes `sim_vehicle.py`.

---

## 8. Récap des pièges (checklist)

1. **Reboot après install-prereqs** : `. ~/.profile` est temporaire; logout/login ou reboot pour rendre le PATH permanent.
2. **ROS 2 via deb packages seulement** : pas le build from source. `ros-humble-desktop` (PC) / `ros-humble-ros-base` (Pi).
3. **Valider chaque étape avec son exemple** : SITL seul (§1), talker/listener (§2), `gz sim shapes.sdf` (§3), `microxrceddsgen -help` + colcon test (§4), `ros2 node list` → `/ap` (§5), iris_runway (§6).
4. **Inspecter le bashrc après chaque ajout** : lignes exactes, pas de doublons, `$PATH` vs `$PWD` bien résolus. Lignes attendues à la fin : `source /opt/ros/humble/setup.bash`, `export GZ_VERSION=harmonic`, `export PATH=$PATH:<...>/Micro-XRCE-DDS-Gen/scripts`.
5. **Gros build colcon qui fail** : relancer la même commande (réseau). Lire `log/latest_build/` si ça persiste.
6. **ros2-sitl : variante 4.6+, SANS `refs:=`** — `dds_xrce_profile.xml` n'existe plus sur ArduPilot ≥ 4.6 ; le passer tue l'agent micro-ROS.
7. **Gazebo Harmonic, pas Garden** : `gz-harmonic` + `GZ_VERSION=harmonic`.
8. **Ne jamais sourcer le workspace ET oublier /opt/ros/humble** : ordre = ROS d'abord (`/opt/ros/humble/setup.bash`, via bashrc), workspace ensuite (`source ~/ardu_ws/install/setup.bash` dans chaque terminal de travail).

---

## Références

- https://ardupilot.org/dev/docs/building-setup-linux.html
- https://ardupilot.org/dev/docs/sitl-on-windows-wsl.html
- https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html
- https://ardupilot.org/dev/docs/ros2.html
- https://ardupilot.org/dev/docs/ros2-sitl.html
- https://gazebosim.org/docs/harmonic/install_ubuntu/
- https://ardupilot.org/dev/docs/ros2-gazebo.html
