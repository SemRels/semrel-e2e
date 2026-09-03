#!/usr/bin/env bash
# Category coverage: updater (maven, gradle, nuget, terraform, helm, homebrew,
# docker) -- every remaining local-file-only updater, stacked in one release
# to also prove plugin composition at scale.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../scripts/common.sh"

build_semrel
MAVEN=$(build_plugin updater-maven updater-maven)
GRADLE=$(build_plugin updater-gradle updater-gradle)
NUGET=$(build_plugin updater-nuget updater-nuget)
TF=$(build_plugin updater-terraform updater-terraform)
HELM=$(build_plugin updater-helm updater-helm)
BREW=$(build_plugin updater-homebrew updater-homebrew)
DOCKER=$(build_plugin updater-docker updater-docker)

REPO=$(new_scenario_repo "05-updater-sweep")

cat > "$REPO/pom.xml" <<'EOF'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>io.semrel.e2e</groupId>
  <artifactId>e2e-demo</artifactId>
  <version>0.1.0</version>
</project>
EOF

echo "version=0.1.0" > "$REPO/gradle.properties"

mkdir -p "$REPO/src/MyApp"
cat > "$REPO/src/MyApp/MyApp.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <Version>0.1.0</Version>
  </PropertyGroup>
</Project>
EOF

cat > "$REPO/variables.tf" <<'EOF'
variable "app_version" {
  type    = string
  default = "0.1.0"
}
EOF

mkdir -p "$REPO/charts/app"
cat > "$REPO/charts/app/Chart.yaml" <<'EOF'
apiVersion: v2
name: app
version: 0.1.0
appVersion: "0.1.0"
EOF

mkdir -p "$REPO/Formula"
cat > "$REPO/Formula/my-tool.rb" <<'EOF'
class MyTool < Formula
  desc "e2e demo formula"
  homepage "https://example.com"
  url "https://github.com/acme/tool/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
EOF

cat > "$REPO/Dockerfile" <<'EOF'
FROM alpine:3
ARG VERSION=0.1.0
EOF

commit_all "$REPO" "chore: initial commit"
git -C "$REPO" tag v0.1.0

echo "feature" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feat: bump every packaging manifest at once"

cat > "$REPO/.semrel.yaml" <<EOF
schemaVersion: 1
tagPrefix: "v"
branches:
  - name: main
rules:
  - type: feat
    bump: minor
  - type: fix
    bump: patch
plugins:
  - path: "$MAVEN"
    phase: pre-tag
    args:
      file: pom.xml
  - path: "$GRADLE"
    phase: pre-tag
    args:
      file: gradle.properties
      key: version
  - path: "$NUGET"
    phase: pre-tag
    args:
      file: src/MyApp/MyApp.csproj
      property: Version
  - path: "$TF"
    phase: pre-tag
    args:
      file: variables.tf
      variable: app_version
  - path: "$HELM"
    phase: pre-tag
    args:
      file: charts/app/Chart.yaml
      update_app_version: "true"
  - path: "$BREW"
    phase: pre-tag
    args:
      formula_file: Formula/my-tool.rb
      url_template: "https://github.com/acme/tool/archive/refs/tags/v{{ .Version }}.tar.gz"
      sha256: "1111111111111111111111111111111111111111111111111111111111111111"
  - path: "$DOCKER"
    phase: pre-tag
    args:
      file: Dockerfile
      arg_name: VERSION
EOF

( cd "$REPO" && "$SEMREL_BIN" release --config .semrel.yaml )

assert_tag_exists "$REPO" "v0.2.0"
assert_file_contains "$REPO/pom.xml" '<version>0.2.0</version>'
assert_file_contains "$REPO/gradle.properties" 'version=0.2.0'
assert_file_contains "$REPO/src/MyApp/MyApp.csproj" '<Version>0.2.0</Version>'
assert_file_contains "$REPO/variables.tf" 'default = "0.2.0"'
assert_file_contains "$REPO/charts/app/Chart.yaml" 'appVersion: "0.2.0"'
assert_file_contains "$REPO/Formula/my-tool.rb" 'v0.2.0.tar.gz'
assert_file_contains "$REPO/Dockerfile" 'ARG VERSION=0.2.0'

finish
