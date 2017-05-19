#!/bin/bash
apt-get update -y
apt-get install -y apache2
/etc/init.d/apache2 start