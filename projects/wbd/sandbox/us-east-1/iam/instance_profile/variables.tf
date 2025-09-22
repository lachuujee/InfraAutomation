variable "region" {
  type = string
}

# main.tf uses these too:
variable "name_prefix" {
  type = string
  # e.g., "WBD_sandbox"
}

variable "tags" {
  type    = map(string)
  default = {}
}
