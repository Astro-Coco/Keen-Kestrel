# syntax=docker/dockerfile:1.6
FROM osrf/ros:humble-desktop

ARG ROS_DISTRO=humble
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 1. Locale UTF-8 + base tooling (mesa-utils fournit glxinfo pour diagnostiquer l'OpenGL).
RUN apt-get update && apt-get install -y --no-install-recommends \
      locales curl wget gnupg lsb-release sudo git ccache mesa-utils && \
    locale-gen en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8

# 2. Aligner les debs ROS préinstallés avec ceux ajoutés plus bas (évite un mix d'ABI ROS).
RUN apt-get update && apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/*

# 3. Dépôt osrf Gazebo + Gazebo Harmonic.
RUN curl -fsSL https://packages.osrfoundation.org/gazebo.gpg \
      -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] https://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/gazebo-stable.list && \
    apt-get update && apt-get install -y --no-install-recommends gz-harmonic && \
    rm -rf /var/lib/apt/lists/*

# 4. Outils dev ROS, RMW CycloneDDS, JDK (gradle compile → JDK, pas JRE),
#    et libglvnd requis pour l'OpenGL via nvidia-container-toolkit.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ros-dev-tools \
      ros-humble-rmw-cyclonedds-cpp \
      default-jdk \
      libglvnd0 libgl1 libglx0 libegl1 libgles2 && \
    rm -rf /var/lib/apt/lists/*

# 5. Liste rosdep Gazebo bakée (résout les clés gz-* au moment du rosdep install runtime).
RUN wget https://raw.githubusercontent.com/osrf/osrf-rosdep/master/gz/00-gazebo.list \
      -O /etc/ros/rosdep/sources.list.d/00-gazebo.list

# 6. User non-root dev (uid/gid 1000) avec sudo NOPASSWD (rosdep install fait sudo apt-get au runtime).
ARG UID=1000
ARG GID=1000
# dev est créé avant render : groupadd sans -g prendrait sinon le premier gid libre (1000),
# volant celui de dev. -r force un gid système (<1000) pour render.
RUN groupadd -g "${GID}" dev && \
    useradd -m -u "${UID}" -g "${GID}" -s /bin/bash dev && \
    (getent group render >/dev/null || groupadd -r render) && \
    usermod -aG sudo,dialout,video,render dev && \
    echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev && \
    chmod 0440 /etc/sudoers.d/dev

# 7. Micro-XRCE-DDS-Gen (générateur DDS, nécessite Java). Purge le cache gradle après build.
RUN git clone --recurse-submodules --branch v4.7.0 \
      https://github.com/ardupilot/Micro-XRCE-DDS-Gen.git /opt/Micro-XRCE-DDS-Gen && \
    cd /opt/Micro-XRCE-DDS-Gen && \
    ./gradlew assemble && \
    rm -rf /root/.gradle /opt/Micro-XRCE-DDS-Gen/.gradle
ENV PATH="/opt/Micro-XRCE-DDS-Gen/scripts:${PATH}"

# 8. Prereqs ArduPilot via un clone shallow jetable, en user dev
#    (le script pip-installe MAVProxy/empy/pymavlink dans ~/.local).
USER dev
RUN git clone --depth 1 https://github.com/ArduPilot/ardupilot.git /tmp/ardupilot && \
    cd /tmp/ardupilot && \
    USER=dev AP_DOCKER_BUILD=1 SKIP_AP_EXT_ENV=1 SKIP_AP_GRAPHIC_ENV=1 SKIP_AP_COV_ENV=1 SKIP_AP_GIT_CHECK=1 \
      Tools/environment_install/install-prereqs-ubuntu.sh -y && \
    sudo rm -rf /tmp/ardupilot /var/lib/apt/lists/*

# 8b. wxPython (modules console/map de MAVProxy, exclu par SKIP_AP_GRAPHIC_ENV=1)
#     + le delta rosdep observé du workspace ardupilot_gz : baké ici pour que la
#     recréation du container ne perde presque rien (rosdep du init → no-op).
#     Couche séparée en fin de build pour ne pas invalider le cache des couches lourdes.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3-wxgtk4.0 \
      ros-humble-geographic-msgs ros-humble-xacro ros-humble-image-transport-plugins \
      ros-humble-ament-black ros-humble-ament-cmake-black \
      ros-humble-ament-mypy ros-humble-ament-cmake-mypy && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i '\#/tmp/ardupilot/Tools/completion#d' /home/dev/.bashrc  # scorie du clone jetable
USER dev

# 9. Env runtime : caches sur le volume /ardu_ws, PATH vers .local, DDS-Gen et autotest.
ENV GZ_VERSION=harmonic \
    CCACHE_DIR=/ardu_ws/.ccache \
    GZ_FUEL_CACHE_PATH=/ardu_ws/.gz/fuel \
    PATH="/home/dev/.local/bin:${PATH}:/opt/Micro-XRCE-DDS-Gen/scripts:/ardu_ws/src/ardupilot/Tools/autotest"

# 10. Point de montage du volume nommé : ownership dev hérité au premier montage.
USER root
RUN mkdir -p /ardu_ws && chown dev:dev /ardu_ws
COPY --chmod=755 scripts/init-workspace.sh /usr/local/bin/init-workspace.sh

USER dev
WORKDIR /ardu_ws
CMD ["bash"]
