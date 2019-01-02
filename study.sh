#!/bin/sh
# Ubuntu 16.04 LTS / Ubuntu 18.04 LTS
# CONFIGURE THE FOLLOWING SECTION 
# --------------------------------------------
project_name="bharat"
project_password="password"
project_ip="127.0.0.1:8000"
project_domain="domain.com www.domain.com"
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
sudo su postgres<<EOF
cd ~
createuser $project_name
createdb $database_name --owner $project_name
psql -c "ALTER USER $project_name WITH PASSWORD '$project_password'"
EOF
cd /root

# Create project user, venv, and setup django
echo "[DJANGOGO] CREATING PROJECT USER, VENV & SETTING UP DJANGO..."
sudo adduser $project_name
sudo gpasswd -a $project_name sudo

# Django setup as project user
sudo su $project_name<<EOF
cd /home/$project_name
python3 -m venv .
source bin/activate
pip install Django
django-admin startproject project
mv project $project_name
cd $project_name
cd project
sed -i "s/ALLOWED_HOSTS = \[\]/ALLOWED_HOSTS = ['$project_ip']/" settings.py
cd ..
django-admin startapp main
pip install gunicorn
EOF

# Create gunicorn_start file
echo "[DJANGOGO] CONFIGURING GUNICORN..."
cd /home/$project_name/bin
cat << EOF >> gunicorn_start
#!/bin/bash
NAME="$project_name"
DIR=/home/$project_name/$project_name
USER=$project_name
GROUP=$project_name
WORKERS=3
BIND=unix:/home/$project_name/run/gunicorn.sock
DJANGO_SETTINGS_MODULE=project.settings
DJANGO_WSGI_MODULE=project.wsgi
LOG_LEVEL=error
cd \$DIR
source /home/$project_name/bin/activate
export DJANGO_SETTINGS_MODULE=\$DJANGO_SETTINGS_MODULE
export PYTHONPATH=\$DIR:\$PYTHONPATH
exec /home/$project_name/bin/gunicorn \${DJANGO_WSGI_MODULE}:application \\
  --name \$NAME \\
  --workers \$WORKERS \\
  --user=\$USER \\
  --group=\$GROUP \\
  --bind=\$BIND \\
  --log-level=\$LOG_LEVEL \\
  --log-file=-
EOF

# Set permissions on gunicorn_start file and create gunicorn logs
chmod u+x gunicorn_start
chown $project_name gunicorn_start
chgrp $project_name gunicorn_start
cd /home/$project_name
mkdir run
chown $project_name run
chgrp $project_name run
mkdir logs
chown $project_name logs
chgrp $project_name logs
touch logs/gunicorn-error.log
chown $project_name logs/gunicorn-error.log
chgrp $project_name logs/gunicorn-error.log

# Configure gunicorn on supervisor
echo "[DJANGOGO] CONFIGURING SUPERVISOR FOR GUNICORN..."
cat << EOF >> /etc/supervisor/conf.d/$project_name.conf
[program:$project_name]
command=/home/$project_name/bin/gunicorn_start
user=$project_name
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/home/$project_name/logs/gunicorn-error.log
EOF

# Restart Supervisor
echo "[DJANGOGO] RESTARTING SUPERVISOR..."
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl status $project_name
sudo supervisorctl restart $project_name

# Configure Nginx
echo "[DJANGOGO] CONFIGURING NGINX..."

# Create project_name.conf in /etc/nginx/conf.d
cat << EOF >> /etc/nginx/conf.d/$project_name.conf
upstream app_server {
    server unix:/home/$project_name/run/gunicorn.sock fail_timeout=0;
}
server {
    listen 80;
    # add here the ip address of your server
    # or a domain pointing to that ip (like example.com or www.example.com)
    server_name $project_ip $project_domain;
    keepalive_timeout 5;
    client_max_body_size 4G;
    access_log /home/$project_name/logs/nginx-access.log;
    error_log /home/$project_name/logs/nginx-error.log;
    location /static/ {
    alias /home/$project_name/$project_name/static/;
    }
    # checks for static file, if not found proxy to app
    location / {
      try_files \$uri @proxy_to_app;
    }
    location @proxy_to_app {
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header Host \$http_host;
      proxy_redirect off;
      proxy_pass http://app_server;
    }
}
EOF

# Restart nginx and you are good to go!
echo "[DJANGOGO] RESTARTING NGINX..."
sudo service nginx restart
echo "[DJANGOGO] COMPLETE!"
echo "[DJANGOGO] VISIT: http://$project_ip"
