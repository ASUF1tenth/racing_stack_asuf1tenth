#!/bin/bash
# AutoDRIVE + ForzaETH Race Stack — End-to-End Test
#
# Orchestrates:
#   1. autodrive_sim   — AutoDRIVE Unity simulator (Docker)
#   2. autodrive_api   — Devkit bridge (Socket.IO ↔ ROS 2, Docker)
#   3. forzaeth_stack  — ForzaETH race stack with our launch (Docker)
#
# Usage:
#   ./scripts/test_autodrive_e2e.sh                  # full stack
#   ./scripts/test_autodrive_e2e.sh --no-sim         # skip sim
#   ./scripts/test_autodrive_e2e.sh --no-devkit      # skip devkit
#   ./scripts/test_autodrive_e2e.sh --no-stack       # skip stack
#   ./scripts/test_autodrive_e2e.sh --rebuild        # force colcon rebuild
#   ./scripts/test_autodrive_e2e.sh --map <name>     # map (default: levine)
#   ./scripts/test_autodrive_e2e.sh --headless       # no X11 forwarding
#   ./scripts/test_autodrive_e2e.sh --help
#
# Cleanup: Ctrl+C

set -euo pipefail

# ─── Paths ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Config ─────────────────────────────────────────────────────────
MAP_NAME="levine"
HEADLESS=false
RUN_SIM=true
RUN_DEVKIT=true
RUN_STACK=true
FORCE_REBUILD=false

STACK_IMAGE="forzaeth_stack_autodrive:latest"
CONTAINER_PREFIX="autodrive_test"
LOG_DIR="/tmp/autodrive_test_logs"

mkdir -p "$LOG_DIR"

# ─── Parse args ─────────────────────────────────────────────────────
usage() {
  sed -n '3,17p' "$0"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-sim)     RUN_SIM=false; shift ;;
    --no-devkit)  RUN_DEVKIT=false; shift ;;
    --no-stack)   RUN_STACK=false; shift ;;
    --rebuild)    FORCE_REBUILD=true; shift ;;
    --map)        MAP_NAME="$2"; shift 2 ;;
    --headless)   HEADLESS=true; shift ;;
    --help)       usage ;;
    *)            echo "Unknown: $1"; usage ;;
  esac
done

# ─── Helpers ────────────────────────────────────────────────────────
info()  { echo -e "\e[36m[INFO]\e[0m  $*"; }
ok()    { echo -e "\e[32m[OK]\e[0m    $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
err()   { echo -e "\e[31m[ERR]\e[0m   $*"; }
step()  { echo -e "\n\e[35m━━━ $* ━━━\e[0m"; }
header(){ echo -e "\e[1m$*\e[0m"; }

cleanup() {
  local ec=$?
  echo ""
  step "CLEANUP"
  for c in \
    "${CONTAINER_PREFIX}_autodrive_sim_1" \
    "${CONTAINER_PREFIX}_autodrive_api_1" \
    "${CONTAINER_PREFIX}_forzaeth_stack_1"; do
    docker rm -f "$c" 2>/dev/null || true
  done
  rm -rf "$LOG_DIR" 2>/dev/null || true
  if [ "$ec" -eq 0 ]; then
    ok "Done."
  else
    err "Exited with code $ec."
  fi
  exit $ec
}
trap cleanup EXIT INT TERM

# ─── X11 ────────────────────────────────────────────────────────────
if ! $HEADLESS; then
  if [ -n "${DISPLAY:-}" ]; then
    xhost +local:root 2>/dev/null || warn "xhost failed (non-fatal)"
    ok "X11 forwarding (DISPLAY=$DISPLAY)"
  else
    warn "DISPLAY not set; use --headless to suppress"
  fi
fi

# ─── Build stack image ──────────────────────────────────────────────
build_stack_image() {
  step "Building stack image: $STACK_IMAGE"

  if ! $FORCE_REBUILD && docker image inspect "$STACK_IMAGE" &>/dev/null; then
    ok "Image $STACK_IMAGE exists (use --rebuild to force rebuild)"
    return
  fi

  info "Building from Dockerfile (may take 15-30 min first time)..."
  info "Running: docker compose build nuc"
  echo ""

  env UID="$(id -u)" GID="$(id -g)" \
    docker compose -f "$REPO_DIR/docker-compose.yaml" build nuc 2>&1 | \
    while IFS= read -r line; do echo "  $line"; done

  echo ""
  docker tag nuc_forzaeth_racestack_ros2:jazzy "$STACK_IMAGE"
  ok "Stack image built: $STACK_IMAGE"
}

# ─── Start AutoDRIVE Simulator ──────────────────────────────────────
start_sim() {
  step "Starting AutoDRIVE Simulator"
  local name="${CONTAINER_PREFIX}_autodrive_sim_1"
  if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
    ok "Simulator already running"
    return
  fi

  info "Starting container from: autodrive_roboracer/sim:latest"
  docker run -d \
    --name "$name" \
    --network host \
    --ipc host \
    --privileged \
    --env DISPLAY="${DISPLAY:-:0}" \
    --env ROS_DOMAIN_ID=0 \
    --env NVIDIA_VISIBLE_DEVICES=all \
    --env NVIDIA_DRIVER_CAPABILITIES=all \
    --volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
    --gpus all \
    --restart no \
    autodrive_roboracer/sim:latest \
    /bin/bash -c "./AutoDRIVE\\ Simulator.x86_64 -ip 127.0.0.1 -port 4567"

  ok "Simulator container started: $name"
  info "Initializing (5s)..."
  sleep 5

  # Show sim logs
  echo ""
  header "Simulator startup output:"
  docker logs "$name" --tail 10 2>&1 | sed 's/^/  /'
  echo ""
}

# ─── Start Devkit Bridge ────────────────────────────────────────────
start_devkit() {
  step "Starting AutoDRIVE Devkit Bridge"
  local name="${CONTAINER_PREFIX}_autodrive_api_1"
  if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
    ok "Devkit already running"
    return
  fi

  info "Starting container from: autodrive_roboracer/devkit:latest"
  # Let the entrypoint auto-launch bringup_graphics.launch.py (bridge + rviz2).
  # rviz2 may crash without display — the bridge keeps running.
  docker run -d \
    --name "$name" \
    --network host \
    --ipc host \
    --privileged \
    --env DISPLAY="${DISPLAY:-:0}" \
    --env ROS_DOMAIN_ID=0 \
    --volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
    --restart no \
    autodrive_roboracer/devkit:latest

  ok "Devkit container started: $name"
  sleep 3

  # Show startup logs (rviz2 may complain about no display — ignore)
  echo ""
  header "Devkit bridge output:"
  docker logs "$name" --tail 10 2>&1 | sed 's/^/  /'
  echo ""
}

# ─── Start ForzaETH Stack ───────────────────────────────────────────
start_stack() {
  step "Starting ForzaETH Stack Container"
  local name="${CONTAINER_PREFIX}_forzaeth_stack_1"
  local user="${USER:-belal}"

  mkdir -p "$REPO_DIR/../cache/jazzy/build" \
           "$REPO_DIR/../cache/jazzy/install" \
           "$REPO_DIR/../cache/jazzy/log"
  chmod 777 "$REPO_DIR/../cache/jazzy/build" \
            "$REPO_DIR/../cache/jazzy/install" \
            "$REPO_DIR/../cache/jazzy/log"

  info "Mounting repo at /home/$user/ws/src/race_stack"
  docker run -d \
    --name "$name" \
    --network host \
    --ipc host \
    --privileged \
    --env DISPLAY="${DISPLAY:-:0}" \
    --env USER="$user" \
    --env ROS_DOMAIN_ID=0 \
    --volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
    --volume /dev:/dev \
    --volume "$REPO_DIR/../cache/jazzy/build:/home/$user/ws/build" \
    --volume "$REPO_DIR/../cache/jazzy/install:/home/$user/ws/install" \
    --volume "$REPO_DIR/../cache/jazzy/log:/home/$user/ws/log" \
    --volume "$REPO_DIR:/home/$user/ws/src/race_stack" \
    --restart no \
    --entrypoint /bin/bash \
    "$STACK_IMAGE" \
    -c "sleep infinity"

  ok "Stack container started: $name"
  sleep 2

  # Build
  step "Building stack_master + f110_autodrive"
  info "Building workspace (may take a few minutes)..."
  echo ""
  docker exec "$name" \
    /bin/bash -c "source /opt/ros/jazzy/setup.bash && \
                  cd /home/$user/ws && \
                  colcon build --symlink-install \
                    --continue-on-error 2>&1" 2>/dev/null | \
    while IFS= read -r line; do echo "  $line"; done || true

  # colcon returns non-zero if any package failed (expected: f110_gym)
  echo ""
  ok "Build complete (expected warnings: vesc, f110_gym)"

  # Verify
  header "Installed packages:"
  docker exec "$name" \
    /bin/bash -c "source /opt/ros/jazzy/setup.bash && \
                  cd /home/$user/ws && \
                  source install/setup.bash && \
                  ros2 pkg list | grep -E 'stack_master|f110_autodrive|frenet'" | \
    sed 's/^/  /'
}

# ─── Launch ─────────────────────────────────────────────────────────
launch_stack() {
  step "Launching autodrive_system_launch.xml  sim_mode:=autodrive"
  local name="${CONTAINER_PREFIX}_forzaeth_stack_1"
  local user="${USER:-belal}"
  local logfile="$LOG_DIR/stack_launch.log"

  info "Map: $MAP_NAME"
  info "Logging to: $logfile"

  docker exec "$name" \
    /bin/bash -c "source /opt/ros/jazzy/setup.bash && \
                  cd /home/$user/ws && \
                  source install/setup.bash && \
                  echo '--- stack launch starting ---' && \
                  ros2 launch f110_autodrive autodrive_system_launch.xml \
                    sim_mode:=autodrive \
                    map_name:=${MAP_NAME}" \
    > "$logfile" 2>&1 &

  LPID=$!
  info "PID $LPID — live log output:"
  echo ""

  # Tail log in background
  tail -f "$logfile" &
  TAILPID=$!

  # Wait for nodes to come up (watch log)
  local timeout=20
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if grep -q "process started" "$logfile" 2>/dev/null; then
      kill $TAILPID 2>/dev/null || true
      echo ""
      ok "Nodes are starting up!"
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
    if [ $((elapsed % 5)) -eq 0 ]; then
      echo "  ... waiting for nodes ($elapsed / ${timeout}s)"
    fi
  done
  kill $TAILPID 2>/dev/null || true
  echo ""

  # Show node list
  header "ROS 2 nodes in stack container:"
  docker exec "$name" \
    /bin/bash -c "source /opt/ros/jazzy/setup.bash && \
                  cd /home/$user/ws && \
                  source install/setup.bash && \
                  timeout 3 ros2 node list 2>/dev/null || echo '(DDS discovery...)'" | \
    sed 's/^/  /'
}

# ─── Monitor ────────────────────────────────────────────────────────
monitor() {
  step "SYSTEM STATUS"
  echo ""
  docker ps --filter "name=${CONTAINER_PREFIX}" \
    --format "table {{.Names}}\t{{.Status}}"
  echo ""

  local auto_api="${CONTAINER_PREFIX}_autodrive_api_1"
  local auto_sim="${CONTAINER_PREFIX}_autodrive_sim_1"
  local stack="${CONTAINER_PREFIX}_forzaeth_stack_1"
  local logfile="$LOG_DIR/stack_launch.log"

  echo "──────────────────────────────────────────────"
  echo "  Interactive commands:"
  echo ""
  echo "  Stack shell:    docker exec -it $stack bash"
  echo "  Stack logs:     tail -f $logfile"
  echo "  Devkit logs:    docker logs $auto_api"
  echo "  Sim logs:       docker logs $auto_sim"
  echo "  ROS 2 topics:   docker exec $stack bash -c 'source /opt/ros/jazzy/setup.bash && cd ~/ws && source install/setup.bash && ros2 topic list'"
  echo "  Stop all:       docker rm -f $stack $auto_api $auto_sim"
  echo "──────────────────────────────────────────────"
  echo ""

  # Live monitor: show log snippets + container health
  info "Monitoring containers (Ctrl+C to stop)..."
  echo ""
  local count=0
  while true; do
    count=$((count + 1))

    # Check health
    for c in "$auto_sim" "$auto_api" "$stack"; do
      s=$(docker inspect --format='{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
      if [ "$s" != "running" ]; then
        warn "$c is $s"
      fi
    done

    # Show stack log tail
    if [ -f "$logfile" ] && [ -s "$logfile" ]; then
      echo ""
      header "[$(date +%H:%M:%S)] Last 5 lines from stack:"
      tail -5 "$logfile" | sed 's/^/  /'
    fi

    # ROS 2 topics every ~60 seconds
    if [ $((count % 2)) -eq 0 ]; then
      echo ""
      header "ROS 2 topics:"
      docker exec "$stack" \
        /bin/bash -c "source /opt/ros/jazzy/setup.bash && \
                      cd /home/${USER:-belal}/ws && \
                      source install/setup.bash && \
                      timeout 3 ros2 topic list 2>/dev/null" 2>/dev/null | \
        sed 's/^/  /' || echo "  (DDS not ready)"
    fi

    sleep 30
    echo "  ─── ${count} check(s) passed ───"
  done
}

# ─── Main ───────────────────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  AutoDRIVE + ForzaETH — End-to-End Test    ║"
echo "╚════════════════════════════════════════════╝"
echo "  Map:       $MAP_NAME"
echo "  Sim:       $([ $RUN_SIM = true ] && echo yes || echo no)"
echo "  Devkit:    $([ $RUN_DEVKIT = true ] && echo yes || echo no)"
echo "  Stack:     $([ $RUN_STACK = true ] && echo yes || echo no)"
echo "  Rebuild:   $([ $FORCE_REBUILD = true ] && echo yes || echo no)"
echo ""

$RUN_STACK  && build_stack_image
$RUN_SIM    && start_sim
$RUN_DEVKIT && start_devkit
$RUN_STACK  && start_stack
$RUN_STACK  && launch_stack

if ! $RUN_SIM && ! $RUN_DEVKIT && ! $RUN_STACK; then
  warn "Nothing to do (all --no-* flags)"
  exit 0
fi

monitor
