#!/usr/bin/env bash
set -Eeuo pipefail

deploy_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
env_file=${SUB2API_ENV_FILE:-/srv/sub2api/config/prod.env}

if [[ ! -S /var/run/docker.sock ]]; then
  echo "Docker socket not found: /var/run/docker.sock" >&2
  exit 1
fi

export DOCKER_GID=${DOCKER_GID:-$(stat -c '%g' /var/run/docker.sock)}

read -r -s -p "Paste the one-time GitHub runner token: " RUNNER_TOKEN
echo

if [[ -z "${RUNNER_TOKEN}" ]]; then
  echo "Runner token cannot be empty." >&2
  exit 1
fi

export RUNNER_TOKEN
trap 'unset RUNNER_TOKEN' EXIT

docker compose \
  --env-file "${env_file}" \
  --file "${deploy_root}/compose.runner.yml" \
  run --rm --no-deps \
  --env RUNNER_REGISTER_ONLY=true \
  --env RUNNER_TOKEN \
  actions-runner

docker compose \
  --env-file "${env_file}" \
  --file "${deploy_root}/compose.runner.yml" \
  up --detach --no-build actions-runner

