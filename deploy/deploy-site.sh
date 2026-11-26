#!/usr/bin/env bash
# Publishes the landing page with the signed disk image for one release.
#
#   deploy/deploy-site.sh 1.0.0
#
# Needs gh (signed in), docker, and kubectl pointed at the cluster. Set
# DOCKER="sudo docker" where docker needs root, and KUBECONFIG for the cluster.
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 <version, for example 1.0.0>" >&2
  exit 64
fi
version="$1"
repository="${GRISWOLD_REPOSITORY:-chriskearney/griswold}"
image="${GRISWOLD_IMAGE:-ghcr.io/chriskearney/griswold-site}"
docker_command="${DOCKER:-docker}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/site/download" "$stage/release"
cp -R "$root/site/." "$stage/site/"
cp "$root/deploy/nginx.conf" "$root/deploy/Dockerfile" "$stage/"

gh release download "v$version" --repo "$repository" --dir "$stage/release" \
  --pattern "Griswold-$version.dmg" --pattern "Griswold-$version.dmg.sha256"
dmg="$stage/release/Griswold-$version.dmg"
expected="$(awk '{print $1}' "$dmg.sha256")"
actual="$(sha256sum "$dmg" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$dmg" | awk '{print $1}')"
if [[ "$expected" != "$actual" ]]; then
  echo "checksum mismatch for $dmg" >&2
  exit 1
fi
cp "$dmg" "$stage/site/download/Griswold.dmg"
size="$(wc -c < "$dmg" | tr -d ' ')"

# The page and the app's update check both read this.
cat > "$stage/site/version.json" <<JSON
{
  "version": "$version",
  "url": "https://chonkbase.net/griswold/",
  "size": $size,
  "sha256": "$actual"
}
JSON

tag="$version-$(date -u +%Y%m%d%H%M%S)"
$docker_command build --pull -t "$image:$tag" "$stage"
$docker_command push "$image:$tag"

kubectl apply -f "$root/deploy/k8s.yaml"
kubectl -n griswold set image deployment/griswold-site "web=$image:$tag"
kubectl -n griswold rollout status deployment/griswold-site --timeout=180s
echo "Deployed $image:$tag"
