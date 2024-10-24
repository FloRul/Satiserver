﻿variable "players_ips" {
  type     = list(string)
  nullable = false
  default  = []
}

variable "instance_type" {
  type     = string
  nullable = false
  default  = "m5a.large"
}

variable "backup_bucket" {
  type    = string
  default = "satiserver-backup"
}
