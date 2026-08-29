FROM ubuntu:24.04

ARG RUNNER_VERSION
ARG RUNNER_SHA256

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        docker.io \
        docker-compose-v2 \
        git \
        jq \
        libicu74 \
        libssl3 \
        sudo \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1000 --shell /bin/bash runner \
    && install -d -o runner -g runner /opt/actions-runner /runner

WORKDIR /opt/actions-runner

RUN test -n "${RUNNER_VERSION}" \
    && test -n "${RUNNER_SHA256}" \
    && curl --fail --location --retry 3 \
        --output runner.tar.gz \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    && echo "${RUNNER_SHA256}  runner.tar.gz" | sha256sum --check --strict \
    && tar --extract --gzip --file runner.tar.gz \
    && rm runner.tar.gz \
    && ./bin/installdependencies.sh \
    && chown -R runner:runner /opt/actions-runner

COPY --chown=runner:runner entrypoint.sh /usr/local/bin/runner-entrypoint
RUN chmod 0755 /usr/local/bin/runner-entrypoint

USER runner
WORKDIR /runner

ENTRYPOINT ["/usr/local/bin/runner-entrypoint"]

