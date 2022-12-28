job "mariadb" {
    datacenters = ["homelab"]
    type = "service"

    group "database" {
        count = 1

        network {
            port "mariadb-net" {
                to = 3306
            }
        }

        volume "mariadb-nfs-volume" {
            type            = "csi"
            source          = "mariadb-nfs"
            read_only       = false
            attachment_mode = "file-system"
            access_mode     = "single-node-writer"
        }

        service {
            name = "mariadb-server"
            port = "mariadb-net"
            provider = "nomad"
        }

        task "mariadb" {
            driver = "docker"
            resources {
                cores  = 2
                memory = 2048
            }
            env {
                MYSQL_ROOT_PASSWORD = "password123456789"
                TZ="America/Seattle"
            }
            config {
                image = "linuxserver/mariadb"
                ports=["mariadb-net"]
            }
            volume_mount {
                volume = "mariadb-nfs-volume"
                destination = "/config"
                read_only = false
            }
        }
    }
}
