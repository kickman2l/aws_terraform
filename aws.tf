// creating VPC and subnets
resource "aws_vpc" "vpc" {
  cidr_block = "192.168.0.0/16"
  tags {
    Name = "test-vpc"
  }
}

resource "aws_subnet" "private_subnet" {
  depends_on = ["aws_vpc.vpc"]
  vpc_id = "${aws_vpc.vpc.id}"
  availability_zone = "us-west-2a"
  cidr_block = "192.168.100.0/24"
  tags {
    Name = "test-private-subnet"
  }
}

resource "aws_subnet" "public_subnet" {
  depends_on = ["aws_vpc.vpc"]
  vpc_id = "${aws_vpc.vpc.id}"
  availability_zone = "us-west-2a"
  cidr_block = "192.168.1.0/24"
  tags {
    Name = "test-public-subnet"
  }
}

// creating Gateways

//internet gateway
resource "aws_internet_gateway" "igw" {
  depends_on = ["aws_subnet.public_subnet"]
  vpc_id = "${aws_vpc.vpc.id}"
  tags {
    Name = "test-igw"
  }
}

//nat gateway
resource "aws_eip" "eip_nat" {}

resource "aws_nat_gateway" "gw" {
  depends_on = ["aws_eip.eip_nat"]
  depends_on = ["aws_subnet.public_subnet"]
  allocation_id = "${aws_eip.eip_nat.id}"
  subnet_id = "${aws_subnet.public_subnet.id}"
}

// creating route tables
resource "aws_route_table" "rt_pr" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name = "test-private-RT"
  }
}

resource "aws_route_table" "rt_pub" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name = "test-public-RT"
  }
}

//associate subnets with rt
resource "aws_route_table_association" "assoc_private" {
  subnet_id = "${aws_subnet.private_subnet.id}"
  route_table_id = "${aws_route_table.rt_pr.id}"
}

resource "aws_route_table_association" "assoc_public" {
  subnet_id = "${aws_subnet.public_subnet.id}"
  route_table_id = "${aws_route_table.rt_pub.id}"
}

//adding routes to route tables
resource "aws_route" "pub_route" {
  route_table_id = "${aws_route_table.rt_pub.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = "${aws_internet_gateway.igw.id}"
  depends_on = [
    "aws_route_table.rt_pub"]
}

resource "aws_route" "priv_route" {
  route_table_id = "${aws_route_table.rt_pr.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = "${aws_nat_gateway.gw.id}"
  depends_on = [
    "aws_route_table.rt_pub"]
}

//creating security groupe
resource "aws_security_group" "allow_80_22" {
  name = "allow_80_22"
  description = "Allow 80 and 22 inbound traffic."
  vpc_id = "${aws_vpc.vpc.id}"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [
      "0.0.0.0/0"]
  }

  tags {
    Name = "test-securty-groupe"
  }
}

//creating instances
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name = "name"
    values = [
      "ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"]
  }

  filter {
    name = "virtualization-type"
    values = [
      "hvm"]
  }
}

resource "aws_instance" "web1" {
  ami = "${data.aws_ami.ubuntu.id}"
  instance_type = "t2.micro"
  depends_on = [
    "aws_nat_gateway.gw"]
  key_name = "pavel"
  associate_public_ip_address = "false"
  subnet_id = "${aws_subnet.private_subnet.id}"
  security_groups = [
    "${aws_security_group.allow_80_22.id}"]
  user_data = "${file("userdata.sh")}"

  tags {
    Name = "web-1"
  }
}

resource "aws_instance" "web2" {
  ami = "${data.aws_ami.ubuntu.id}"
  instance_type = "t2.micro"
  depends_on = [
    "aws_nat_gateway.gw"]
  key_name = "pavel"
  associate_public_ip_address = "false"
  subnet_id = "${aws_subnet.private_subnet.id}"
  security_groups = [
    "${aws_security_group.allow_80_22.id}"]
  user_data = "${file("userdata.sh")}"

  tags {
    Name = "web-2"
  }
}

//creating loadbalancer

resource "aws_elb" "test_balancer" {
  depends_on = ["aws_instance.web2"]
  name = "test-elb"

  subnets = [
    "${aws_subnet.public_subnet.id}"]
  security_groups = [
    "${aws_security_group.allow_80_22.id}"]
  instances = [
    "${aws_instance.web1.id}",
    "${aws_instance.web2.id}"]

  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "HTTP:80/"
    interval = 30
  }

  cross_zone_load_balancing = true

  tags {
    Name = "test_balancer"
  }
}