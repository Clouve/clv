#!/usr/bin/env bats

load 'helpers/load'

setup() {
  export CLV_DRY_RUN=1
}

@test "aws shim emits expected docker command" {
  run clv_dry aws --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker run"* ]]
  [[ "$output" == *"amazon/aws-cli"* ]]
  [[ "$output" == *"--version"* ]]
  [[ "$output" != *"-a STDOUT"* ]]
}

@test "az shim emits expected docker command with az entrypoint" {
  run clv_dry az --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"--entrypoint az"* ]]
  [[ "$output" == *"mcr.microsoft.com/azure-cli"* ]]
}

@test "gcloud shim emits expected docker command" {
  run clv_dry gcloud --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"--entrypoint gcloud"* ]]
  [[ "$output" == *"google/cloud-sdk"* ]]
}

@test "git shim emits expected docker command" {
  run clv_dry git --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"--entrypoint git"* ]]
  [[ "$output" == *"alpine/git"* ]]
}

@test "go shim publishes ports when PORTS is set" {
  PORTS="8080" run clv_dry go version
  [ "$status" -eq 0 ]
  [[ "$output" == *"--publish=8080:8080"* ]]
  [[ "$output" == *"--entrypoint go"* ]]
  [[ "$output" == *"golang"* ]]
}

@test "go shim defaults to host network when PORTS unset" {
  run clv_dry go version
  [ "$status" -eq 0 ]
  [[ "$output" == *"--network=host"* ]]
}

@test "helm shim double-mounts .config" {
  run clv_dry helm version
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.clv/helm:/root"* ]]
  [[ "$output" == *".config:/root/.config"* ]]
  [[ "$output" == *"--entrypoint helm"* ]]
  [[ "$output" == *"alpine/helm"* ]]
}

@test "node shim emits expected docker command" {
  run clv_dry node --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"--entrypoint node"* ]]
  [[ "$output" == *"PATH=/root/bin:"* ]]
}

@test "npm shim mounts node home (not npm home)" {
  run clv_dry npm --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.clv/node:/root"* ]]
  [[ "$output" == *"--entrypoint npm"* ]]
}

@test "ncu shim mounts node home" {
  run clv_dry ncu --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.clv/node:/root"* ]]
  [[ "$output" == *"--entrypoint ncu"* ]]
}

@test "prettier shim mounts node home" {
  run clv_dry prettier --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.clv/node:/root"* ]]
  [[ "$output" == *"--entrypoint prettier"* ]]
}

@test "python shim sets PYTHONUSERBASE" {
  run clv_dry python --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"PYTHONUSERBASE=/root/base"* ]]
  [[ "$output" == *"--entrypoint python"* ]]
}

@test "CLV_TAG override changes the image tag" {
  CLV_TAG=20 run clv_dry node --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"node:20"* ]]
}

@test "gcloud defaults to the slim image variant" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/gcloud" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"google/cloud-sdk:slim"* ]]
}

@test "CLV_TAG override changes the gcloud image tag" {
  CLV_TAG=alpine CLV_DRY_RUN=1 run "$REPO_ROOT/bin/gcloud" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"google/cloud-sdk:alpine"* ]]
}
