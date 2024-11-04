variable "players_ips" {
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

variable "instance_ami" {
  type     = string
  nullable = false
}

variable "budget_limit" {
  description = "Monthly budget limit in CAD"
  type        = number
  nullable    = false
}

variable "admin_email" {
  type     = string
  nullable = false
}
