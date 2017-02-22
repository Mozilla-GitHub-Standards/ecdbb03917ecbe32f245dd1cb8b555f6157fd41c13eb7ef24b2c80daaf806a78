output "EIP" {
  value = "${aws_eip.dns.id}"
}

output "Address" {
  value = "${aws_eip.dns.public_ip}"
}

