#!/usr/bin/env bash
set -Eeuo pipefail

deploy_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
env_file=${SUB2API_ENV_FILE:-/srv/sub2api/config/prod.env}

export DOCKER_GID=${DOCKER_GID:-$(stat -c '%g' /var/run/docker.sock)}

if [[ ! -f "${SUB2API_DATA_ROOT:-/srv/sub2api}/runner/.runner" ]]; then
  docker compose \
    --env-file "${env_file}" \
    --file "${deploy_root}/compose.runner.yml" \
    build actions-runner

  echo "Runner image is ready. Run runner/register.sh with a one-time GitHub token."
  exit 0
fi

docker compose \
  --env-file "${env_file}" \
  --file "${deploy_root}/compose.runner.yml" \
  up --detach --build actions-runner
