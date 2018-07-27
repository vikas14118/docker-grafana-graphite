FROM   ubuntu:14.04

# ---------------- #
#   Installation   #
# ---------------- #
# Install all prerequisites
RUN	apt-get update
RUN	apt-get install -f
RUN     apt-get install -y nginx npm git curl wget gcc ca-certificates 
RUN     apt-get install -y python-dev python-pip musl-dev libffi-dev supervisor bash 
RUN     apt-get install -y libsasl2-dev python-ldap python-rrdtool postfix telnet libc6                                          
RUN 	adduser --disabled-password --gecos  '' www                                                                        
RUN     pip install -U pytz gunicorn six
RUN	sudo apt-get update && sudo apt-get -y upgrade
RUN 	curl -sL https://deb.nodesource.com/setup_4.x | sudo -E bash -
RUN	sudo apt-get install -y nodejs                                                         
RUN     npm install -g wizzy                                                                                        
RUN     npm cache clean --force

RUN 	mkdir -p /etc/resolvconf/resolv.conf.d								
RUN	> /etc/resolvconf/resolv.conf.d/base
RUN 	> /etc/resolvconf/resolv.conf.d/head
RUN     echo "nameserver 10.14.155.200" >> /etc/resolvconf/resolv.conf.d/base
RUN     echo "nameserver 10.14.67.100" >> /etc/resolvconf/resolv.conf.d/base
RUN     echo "nameserver 10.14.155.100" >> /etc/resolvconf/resolv.conf.d/base


# Checkout the master branches of Graphite, Carbon and Whisper and install from there
RUN     mkdir /src                                                                                                   &&\
        git clone --depth=1 --branch master https://github.com/graphite-project/whisper.git /src/whisper             &&\
        cd /src/whisper                                                                                              &&\
        pip install .                                                                                 &&\
        python setup.py install

RUN     git clone --depth=1 --branch master https://github.com/graphite-project/carbon.git /src/carbon               &&\
        cd /src/carbon    												&&\
	pwd							&&\
	ls                                                                                           &&\
        pip install .                                                                                 &&\
        python setup.py install

RUN	pip install Django==1.8
RUN     git clone --depth=1 --branch master https://github.com/graphite-project/graphite-web.git /src/graphite-web    &&\
     	cd /src/graphite-web            &&\                      
     	pip install /src/graphite-web                 &&\                                                                                             
     	python setup.py install                          &&\                                                           
     	pip install -r requirements.txt       &&\                                                         
     	python check-dependencies.py


# Install StatsD
RUN     git clone --depth=1 --branch master https://github.com/etsy/statsd.git /src/statsd

# Install Grafana
RUN     mkdir /src/grafana                                                                                           &&\
        mkdir /opt/grafana                                                                                           &&\
        curl https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-5.1.0.linux-x64.tar.gz \
             -o /src/grafana.tar.gz                                                                                  &&\
        tar -xzf /src/grafana.tar.gz -C /opt/grafana --strip-components=1                                            &&\
        rm /src/grafana.tar.gz



# ----------------- #
#   Configuration   #
# ----------------- #

# Confiure StatsD
ADD     ./statsd/config.js /src/statsd/config.js

# Configure Whisper, Carbon and Graphite-Web
ADD     ./graphite/initial_data.json /opt/graphite/webapp/graphite/initial_data.json
ADD     ./graphite/local_settings.py /opt/graphite/webapp/graphite/local_settings.py
ADD     ./graphite/carbon.conf /opt/graphite/conf/carbon.conf
ADD     ./graphite/storage-schemas.conf /opt/graphite/conf/storage-schemas.conf
ADD     ./graphite/storage-aggregation.conf /opt/graphite/conf/storage-aggregation.conf
RUN     mkdir -p /opt/graphite/storage/whisper                                                                       &&\
        mkdir -p /opt/graphite/storage/log/webapp                                                                    &&\
        touch /opt/graphite/storage/graphite.db /opt/graphite/storage/index                                          &&\
        chown -R www /opt/graphite/storage                                                                           &&\
        chmod 0775 /opt/graphite/storage /opt/graphite/storage/whisper                                               &&\
        chmod 0664 /opt/graphite/storage/graphite.db                                                                 &&\
        cp /src/graphite-web/webapp/manage.py /opt/graphite/webapp                                                   &&\
        cd /opt/graphite/webapp/ && python manage.py migrate 

# Configure Grafana and wizzy
RUN     mkdir -p /etc/grafana
ADD     ./grafana/custom.ini /etc/grafana/grafana.ini
ADD     ./grafana/custom.ini /opt/grafana/conf/custom.ini
RUN     cd /src                                                                                                      &&\
        wizzy init                                                                                                   &&\
        extract() { cat /opt/grafana/conf/custom.ini | grep $1 | awk '{print $NF}'; }                                &&\
        wizzy set grafana url $(extract ";protocol")://$(extract ";domain"):$(extract ";http_port")                  &&\
        wizzy set grafana username $(extract ";admin_user")                                                          &&\
        wizzy set grafana password $(extract ";admin_password")

# Add the default datasource and dashboards
RUN 	mkdir /src/datasources                                                                                       &&\
        mkdir /src/dashboards
ADD     ./grafana/datasources/* /src/datasources
ADD     ./grafana/dashboards/* /src/dashboards/
ADD     ./grafana/export-datasources-and-dashboards.sh /src/

# Configure nginx and supervisord
ADD     ./nginx/nginx.conf /etc/nginx/nginx.conf
ADD     ./supervisord.conf /etc/supervisor/conf.d/supervisord.conf


# ---------------- #
#   Expose Ports   #
# ---------------- #

# Grafana
EXPOSE  80

# StatsD UDP port
EXPOSE  8125/udp

# StatsD Management port
EXPOSE  8126

# Graphite web port
EXPOSE 81

# Graphite Carbon port
EXPOSE 2003


# -------- #
#   Run!   #
# -------- #

CMD     ["/usr/bin/supervisord", "--nodaemon", "--configuration", "/etc/supervisor/conf.d/supervisord.conf"]
