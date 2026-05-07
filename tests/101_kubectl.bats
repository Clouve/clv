#!/usr/bin/env bats
load 'helpers/load'

@test "kubectl shim mounts kube config dir" {
  CLV_DRY_RUN=1 run "$REPO_ROOT/bin/kubectl" version --client
  [ "$status" -eq 0 ]
  [[ "$output" == *"bitnami/kubectl"* ]]
  [[ "$output" == *"--entrypoint kubectl"* ]]
  [[ "$output" == *"/.kube:/.kube"* ]]
  [[ "$output" == *"KUBECONFIG=/.kube/config"* ]]
}
