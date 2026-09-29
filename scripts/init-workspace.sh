#!/usr/bin/env bash
# Initialise le workspace colcon dans le volume nommé /ardu_ws.
# Idempotent : relançable après un échec réseau OU après un recreate du container.
# C'est LE mécanisme de récupération — chaque étape se garde ou reprend d'elle-même.
set -eo pipefail

source /opt/ros/humble/setup.bash
set -u  # après le source : les setup.bash ROS ne sont pas nounset-safe

mkdir -p /ardu_ws/src
cd /ardu_ws

# Import des sources. Toujours rejoué avec --skip-existing : un import interrompu
# (réseau) est complété au run suivant, les dépôts déjà clonés sont sautés.
vcs import --skip-existing --recursive --input \
  https://raw.githubusercontent.com/ArduPilot/ardupilot/master/Tools/ros2/ros2.repos src
vcs import --skip-existing --recursive --input \
  https://raw.githubusercontent.com/ArduPilot/ardupilot_gz/main/ros2_gz.repos src

# Toujours rejoué : les debs installés par rosdep vivent dans le container,
# perdus au down/recreate — ce chemin les réinstalle sur le workspace persisté.
sudo apt-get update
rosdep update
rosdep install --from-paths src --ignore-src -y

# Build. colcon reprend là où il s'était arrêté si une passe a échoué.
# Cap RAM ~2 Go/job sur les grosses TUs Gazebo : limiter les workers.
colcon build --packages-up-to ardupilot_gz_bringup \
  --parallel-workers "${COLCON_JOBS:-4}"

# Marqueur dans le layer du container (PAS le volume) : il disparaît au recreate,
# exactement comme les debs rosdep — les cibles sim/sitl s'en servent en préflight.
sudo touch /var/lib/init-workspace-done

echo
echo "Workspace prêt."
echo "Si le build a échoué (réseau), relance 'make init' : colcon reprend où il en était."
echo "Prochaine étape : 'make sim'."
