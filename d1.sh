#!/bin/sh
# Ubuntu 16.04 LTS / Ubuntu 18.04 LTS
# CONFIGURE THE FOLLOWING SECTION 
# --------------------------------------------
. var
# --------------------------------------------
# NOTE: project_password serves as the password for postgres database that is created
# USAGE:
# From root home directory
# sudo su - 
# Edit project_name, project_ip, and project_domain variables above 
# Then chmod +x djangogo.sh; ./djangogo.sh
# If you are on AWS, make sure to change your security groups to allow for traffic on port 80

# Install nginx, python, supervisor and dependencies
echo "[DJANGOGO] UPDATING SYSTEM & INSTALLING DEPENDENCIES..."
sudo apt-get update
sudo apt-get -y upgrade
echo "[DJANGOGO] INSTALL PYTHON 3 & BUILD ESSENTIALS..."
sudo apt-get -y install build-essential libpq-dev python-dev python3-venv libssl-dev
echo "[DJANGOGO] INSTALL NGINX.."
sudo apt-get -y install nginx
echo "[DJANGOGO] INSTALL & CONFIGURE SUPERVISOR.."
sudo apt-get -y install supervisor
sudo systemctl enable supervisor
sudo systemctl start supervisor
sudo apt-get -y install python-virtualenv git

# Create Postgres
echo "[DJANGOGO] INSTALL & CONFIGURE POSTGRES..."
sudo apt-get -y install postgresql postgresql-contrib
database_prefix=$project_name
database_suffix="_prod"
database_name=$database_prefix$database_suffix
su postgres<<EOF
cd ~
createuser $project_name
createdb $database_name --owner $project_name
psql -c "ALTER USER $project_name WITH PASSWORD '$project_password'"
EOF
