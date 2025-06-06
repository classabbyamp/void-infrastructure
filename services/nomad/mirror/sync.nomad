job "sync" {
  type = "sysbatch"
  datacenters = ["VOID-MIRROR"]
  namespace = "mirror"

  # FIXME: b-hel-fi is consistently filling up when syncing chromium/electron tarballs
  constraint {
    attribute = "${node.unique.name}"
    operator = "set_contains_any"
    value = "d-hel-fi,a-fra-de"
  }

  periodic {
    crons = ["* * * * *"]
    prohibit_overlap = true
  }

  dynamic "group" {
    for_each = [ "mirror", "sources", ]
    labels = [ "sync-${group.value}" ]

    content {
      count = 1
      network { mode = "bridge" }

      dynamic "volume" {
        for_each =  [ "${group.value}" ]
        labels = [ "dist-${volume.value}" ]

        content {
          type = "host"
          source = "dist_${volume.value}"
          read_only = false
        }
      }

      task "rsync" {
        driver = "docker"

        config {
          image = "ghcr.io/void-linux/infra-rsync:20240709R1"
          command = "/usr/bin/rsync"
          args = [
            "-vurk",
            "--delete-after",
            "--delay-updates",
            "--links",
            "rsync://${env["RSYNC_ADDR"]}/${group.value}/",
            "/${group.value}/",
          ]
        }

        template {
          data=<<EOF
{{ $allocID := env "NOMAD_ALLOC_ID" -}}
{{ range nomadService 1 $allocID "shadow-rsyncd" }}
RSYNC_ADDR="{{ .Address }}:{{ .Port }}"
{{ end }}
EOF
          destination = "local/env"
          env = true
        }

        resources {
          memory = 1000
        }

        volume_mount {
          volume = "dist-${group.value}"
          destination = "/${group.value}"
        }
      }
    }
  }
}
