#!/bin/bash
set -euo pipefail
umask 027

service="$1"
image_name="$2"
deployment_bucket="$3"
artifact_key="$4"
expected_digest="$5"

[[ "$service" =~ ^(frontend|backend|ai)$ ]]
[[ "$image_name" =~ ^ocean-across-(frontend|backend|ai):[0-9a-f]{40}$ ]]
[[ "$deployment_bucket" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]
[[ "$artifact_key" =~ ^deployments/(dev|production)/(frontend|backend|ai)/[0-9a-f]{40}/[0-9]+-[0-9]+/image.tar.gz$ ]]
[[ "$expected_digest" =~ ^[0-9a-f]{64}$ ]]
[ "${image_name%%:*}" = "ocean-across-$service" ]
case "$artifact_key" in
  deployments/dev/"$service"/* | deployments/production/"$service"/*) ;;
  *) echo "Artifact service does not match deployment service." >&2; exit 1 ;;
esac

release_dir="/opt/ocean-across/$service/releases/$expected_digest"
install -d -m 0750 "$release_dir"
aws s3 cp "s3://$deployment_bucket/$artifact_key" \
  "$release_dir/image.tar.gz" --only-show-errors
actual_digest="$(sha256sum "$release_dir/image.tar.gz" | cut -d ' ' -f 1)"
[ "$actual_digest" = "$expected_digest" ]
gzip --decompress --stdout "$release_dir/image.tar.gz" | docker load
docker image inspect "$image_name" > /dev/null

run_container() {
  local container_name="$1"
  local host_port="$2"
  local image="$3"
  docker run --detach \
    --name "$container_name" \
    --restart unless-stopped \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=16m \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --pids-limit 128 \
    --memory 256m \
    --env "PORTAL_TYPE=$service" \
    --publish "127.0.0.1:$host_port:8080" \
    "$image" > /dev/null
}

wait_for_health() {
  local host_port="$1"
  for attempt in {1..15}; do
    if curl --fail --silent "http://127.0.0.1:$host_port/health" > /dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

active_container="ocean-across-$service"
candidate_container="$active_container-candidate"
docker rm --force "$candidate_container" 2>/dev/null || true

run_container "$candidate_container" 18080 "$image_name"
if ! wait_for_health 18080; then
  docker rm --force "$candidate_container" > /dev/null
  echo "Candidate container failed its health check." >&2
  exit 1
fi

previous_image="$(docker inspect --format '{{.Config.Image}}' "$active_container" 2>/dev/null || true)"
docker rm --force "$candidate_container" > /dev/null
docker rm --force "$active_container" 2>/dev/null || true
run_container "$active_container" 8080 "$image_name"

if ! wait_for_health 8080; then
  docker rm --force "$active_container" > /dev/null
  if [ -n "$previous_image" ] && docker image inspect "$previous_image" > /dev/null 2>&1; then
    run_container "$active_container" 8080 "$previous_image"
  fi
  echo "Deployment failed its final health check; rollback was attempted." >&2
  exit 1
fi
