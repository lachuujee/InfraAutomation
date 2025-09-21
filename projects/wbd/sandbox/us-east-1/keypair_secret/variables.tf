variable "name"        { description = "Key pair / secret base name"; type = string }
variable "tags"        { type = map(string), default = {} }
variable "algorithm"   { type = string, default = "RSA" }    # or "ED25519"
variable "rsa_bits"    { type = number, default = 4096 }
variable "create_kms_key" { type = bool, default = true }    # create CMK for the secret
variable "kms_key_id"  { type = string, default = null }     # use existing CMK if provided
