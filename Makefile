SHELL := /bin/bash
.DEFAULT_GOAL := help

# Gid du groupe render de l'hôte (Intel/AMD) — dérivé automatiquement; le défaut 992
# de compose.intel.yaml ne sert que si le groupe n'existe pas.
export RENDER_GID ?= $(shell getent group render 2>/dev/null | cut -d: -f3)

# Préflight sim/sitl : les debs rosdep vivent dans le layer du container et meurent au
# recreate ; init-workspace.sh pose ce marqueur au même endroit pour les tracer.
PREFLIGHT = [ -f /var/lib/init-workspace-done ] || { echo "Deps rosdep manquantes (container recréé ?) → lance make init"; exit 1; }

# Ordre de sourcing important : ROS d'abord, workspace ensuite (sinon les overlays
# colcon ne surchargent pas correctement les paquets de /opt/ros/humble).
# SDF_PATH + GZ_SIM_RESOURCE_PATH : libsdformat (robot_state_publisher) et gz-sim
# résolvent package://ardupilot_gazebo/... depuis la racine share/, que les hooks du
# paquet n'ajoutent pas. Sans SDF_PATH l'iris ne spawn pas (create attend robot_description) ;
# sans GZ_SIM_RESOURCE_PATH les meshes (.dae/.stl) sont introuvables dans Gazebo.
AP_SHARE = /ardu_ws/install/ardupilot_gazebo/share
SRC = source /opt/ros/humble/setup.bash && if [ -f /ardu_ws/install/setup.bash ]; then source /ardu_ws/install/setup.bash; export SDF_PATH=$${SDF_PATH:+$$SDF_PATH:}$(AP_SHARE) GZ_SIM_RESOURCE_PATH=$${GZ_SIM_RESOURCE_PATH:+$$GZ_SIM_RESOURCE_PATH:}$(AP_SHARE); fi

EXEC = docker compose exec sim bash -lc

.PHONY: help build up down init sim sitl mavproxy shell test clean clean-eeprom

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.env:
	cp .env.example .env

build: .env ## Construit l'image keen-kestrel
	docker compose build

up: .env ## Démarre le conteneur sim en arrière-plan
	@f="$${XAUTHORITY:-$$HOME/.Xauthority}"; [ -e "$$f" ] || touch "$$f"  # sinon docker crée un RÉPERTOIRE root à sa place
	docker compose up -d

down: ## Arrête et retire le conteneur sim
	docker compose down

init: ## Initialise le workspace ROS 2 (1er run long, relançable ; COLCON_JOBS=N pour ajuster)
	docker compose exec -e COLCON_JOBS sim bash -lc 'init-workspace.sh'

# Chaîne de fichiers de params du SITL : celle du launch iris + config/sim.parm en
# dernier (le dernier gagne). L'eeprom persistant (/ardu_ws/eeprom.bin) garde toutefois
# priorité pour tout param déjà modifié via GCS — voir clean-eeprom.
SITL_SHARE = /ardu_ws/install/ardupilot_sitl/share/ardupilot_sitl/config/default_params
DEFAULTS = $(SITL_SHARE)/copter.parm,$(AP_SHARE)/ardupilot_gazebo/config/gazebo-iris-gimbal.parm,$(SITL_SHARE)/dds_udp.parm,$(SITL_SHARE)/dds_use_ns.parm,/ardu_ws/config/sim.parm

sim: ## Lance SITL + Gazebo + RViz (iris_runway), params: config/sim.parm
	$(EXEC) '$(PREFLIGHT); $(SRC) && ros2 launch ardupilot_gz_bringup iris_runway.launch.py defaults:=$(DEFAULTS)'

sitl: ## Lance SITL + DDS seul, sans Gazebo (guide §5, variante refs 4.5)
	$(EXEC) '$(PREFLIGHT); $(SRC) && ros2 launch ardupilot_sitl sitl_dds_udp.launch.py transport:=udp4 refs:=$$(ros2 pkg prefix ardupilot_sitl)/share/ardupilot_sitl/config/dds_xrce_profile.xml synthetic_clock:=True wipe:=False model:=quad speedup:=1 slave:=0 instance:=0 defaults:=$$(ros2 pkg prefix ardupilot_sitl)/share/ardupilot_sitl/config/default_params/copter.parm,$$(ros2 pkg prefix ardupilot_sitl)/share/ardupilot_sitl/config/default_params/dds_udp.parm,/ardu_ws/config/sim.parm sim_address:=127.0.0.1 master:=tcp:127.0.0.1:5760 sitl:=127.0.0.1:5501'

mavproxy: ## Ouvre une console MAVProxy (console + carte) sur le SITL local
	$(EXEC) '$(SRC) && mavproxy.py --console --map --master=:14550'

shell: ## Ouvre un shell interactif dans le conteneur, ROS + workspace sourcés
	docker compose exec sim bash -c '$(SRC); exec bash'

test: ## Smoke-tests : OpenGL, Gazebo headless, DDS-Gen, MAVProxy
	$(EXEC) '$(SRC) && glxinfo -B && gz sim -v4 -s -r --iterations 100 shapes.sdf && microxrceddsgen -help > /dev/null && echo OK && mavproxy.py --version'

clean-eeprom: ## Supprime l'eeprom SITL : les params reviennent aux defaults + sim.parm
	$(EXEC) 'rm -f /ardu_ws/eeprom.bin' && echo "eeprom supprimé — prochain boot sur defaults + config/sim.parm"

clean: ## Down + supprime le volume ardu_ws (destructif, confirmation requise)
	docker compose down
	@read -p "Supprimer le volume ardu_ws (perte des workspaces/builds) ? [y/N] " ans; [ "$$ans" = "y" ] || [ "$$ans" = "Y" ] || exit 1
	docker compose down -v
