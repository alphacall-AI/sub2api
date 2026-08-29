#!/usr/bin/env bash
set -Eeuo pipefail

runner_root=/runner
runner_dist=/opt/actions-runner

if [[ ! -x "${runner_root}/config.sh" ]]; then
  cp -a "${runner_dist}/." "${runner_root}/"
fi

cd "${runner_root}"

if [[ "${RUNNER_REGISTER_ONLY:-false}" == "true" ]]; then
  : "${RUNNER_URL:?RUNNER_URL is required}"
  : "${RUNNER_TOKEN:?RUNNER_TOKEN is required for initial registration}"

  ./config.sh \
    --unattended \
    --replace \
    --url "${RUNNER_URL}" \
    --token "${RUNNER_TOKEN}" \
    --name "${RUNNER_NAME:-sub2api-prod}" \
    --labels "${RUNNER_LABELS:-sub2api-prod}" \
    --work "${RUNNER_WORKDIR:-_work}"

  exit 0
fi

if [[ ! -f .runner ]]; then
  echo "Runner is not registered. Run register.sh first." >&2
  exit 1
fi

exec ./run.sh

