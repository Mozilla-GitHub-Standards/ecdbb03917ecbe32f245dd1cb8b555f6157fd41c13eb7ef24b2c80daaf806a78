module "worker" {
  source       = "github.com/nubisproject/nubis-terraform//worker?ref=v1.4.1"
  region       = "${var.region}"
  environment  = "${var.environment}"
  account      = "${var.account}"
  service_name = "${var.service_name}"
  ami          = "${var.ami}"
  purpose      = "dns"
  
  public       = true
  
  security_group        = "${aws_security_group.dns.id}"
  security_group_custom = true

  instance_type = "${lookup(var.instance_types, var.environment, lookup(var.instance_types, "default"))}"
}

module "info" {
  source      = "github.com/nubisproject/nubis-terraform//info?ref=v1.4.1"
  region      = "${var.region}"
  environment = "${var.environment}"
  account     = "${var.account}"
}

provider "aws" {
  region = "${var.region}"
}

# We need an Elastic IP
resource "aws_eip" "dns" {
  vpc   = true

  lifecycle {
    create_before_destroy = true
  }
}

# And a special role to be able to bind it to ourselves
resource "aws_iam_role_policy" "dns" {
    name = "dns-eip-associate"
    role = "${module.worker.role}"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
            {
              "Effect": "Allow",
              "Action": [
                "ec2:AssociateAddress",
                "ec2:DescribeAddresses"
              ],
              "Resource": "*"
            }
          ]
}
EOF
}

# And a custom DNS security group from the world
resource "aws_security_group" "dns" {
  name_prefix = "${var.service_name}-${var.environment}-dns-"

  vpc_id = "${module.info.vpc_id}"

  tags = {
    Name           = "${var.service_name}-${var.environment}-dns"
    Region         = "${var.region}"
    Environment    = "${var.environment}"
    Backup         = "true"
    Shutdown       = "never"
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [
      "${module.info.ssh_security_group}"
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}
