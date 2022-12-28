job "nfs-node" {
  datacenters = ["homelab"]

  type = "system"

  group "nodes" {
    task "plugin" {
      driver = "docker"

      config {
        image = "mcr.microsoft.com/k8s/csi/nfs-csi:latest"
        args = [
          "-v=5",
          "--nodeid=${attr.unique.hostname}",
          "--endpoint=unix://csi/csi.sock"
        ]
        privileged = true
      }

      csi_plugin {
        id        = "nfs"
        type      = "node"
        mount_dir = "/csi"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
