resource "helm_release" "nvidia_device_plugin" {
  name             = "nvidia-device-plugin"
  namespace        = "nvidia"
  create_namespace = true

  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = "0.14.5"

  values = [
    "${file("nvidia-values.yml")}"
  ]
}