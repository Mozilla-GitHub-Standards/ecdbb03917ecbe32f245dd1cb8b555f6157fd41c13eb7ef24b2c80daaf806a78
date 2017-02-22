variable "account" {}

variable "region" {
  default = "us-west-2"
}

variable "environment" {
  default = "stage"
}

variable "service_name" {
  default = "akamai"
}

variable "ami" {}

variable "instance_types" {
  type = "map"

  default = {
    prod      = "t2.micro"
    stage     = "t2.nano"
    default   = "t2.nano"
  }
}
