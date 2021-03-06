#!/bin/bash 
# vim: tabstop=2:shiftwidth=2:softtabstop=2

set -e
set -x

# Define the version of zabbixapi gem to be downloaded
# Refer https://github.com/bloomberg/chef-bcpc/issues/343
ZABBIXAPI_VERSION=2.4.5

# Define the appropriate version of each binary to grab/build
VER_KIBANA=d1495fbf6e9c20c707ecd4a77444e1d486a1e7d6
VER_DIAMOND=d64cc5cbae8bee93ef444e6fa41b4456f89c6e12
VER_ESPLUGIN=c3635657f4bb5eca0d50afa8545ceb5da8ca223a
EPOCH=`date +"%s"`; export EPOCH 

# The proxy and $CURL will be needed later
if [[ -f ./proxy_setup.sh ]]; then
  . ./proxy_setup.sh
fi

if [[ -z "$CURL" ]]; then
  echo "CURL is not defined"
  exit
fi

DIR=`dirname $0`

mkdir -p $DIR/bins
pushd $DIR/bins/

# create directory for Python bins
mkdir -p python

# create directory for dpkg's
APT_REPO_VERSION=0.5.0
APT_REPO="dists/${APT_REPO_VERSION}/"
APT_REPO_BINS="${APT_REPO}/main/binary-amd64/"
mkdir -p $APT_REPO_BINS

# Get up to date
apt-get -y update

# Install tools needed for packaging
apt-get -y install git ruby make pkg-config pbuilder python-mock python-configobj python-support cdbs python-all-dev python-stdeb libmysqlclient-dev libldap2-dev ruby-dev gcc patch rake ruby1.9.3 ruby1.9.1-dev python-pip python-setuptools dpkg-dev apt-utils haveged libtool autoconf automake autotools-dev unzip rsync autogen

# Install json gem first to avoid a too-new version being pulled in by other gems.
if [[ -z `gem list --local json | grep json | cut -f1 -d" "` ]]; then
  gem install json --no-ri --no-rdoc -v 1.8.3
fi

if [[ -z `gem list --local cabin | grep cabin | cut -f1 -d" "` ]]; then
  gem install cabin --no-ri --no-rdoc -v 0.7.2
fi

if [[ -z `gem list --local fpm | grep fpm | cut -f1 -d" "` ]]; then
  gem install fpm --no-ri --no-rdoc -v 1.3.3
fi

# Download jmxtrans tar.gz file
if ! [[ -f jmxtrans-256-dist.tar.gz ]]; then
  while ! $(file jmxtrans-256-dist.tar.gz | grep -q 'gzip compressed data'); do
    $CURL -O -L -k http://central.maven.org/maven2/org/jmxtrans/jmxtrans/256/jmxtrans-256-dist.tar.gz
   done
fi
FILES="jmxtrans-254-dist.tar.gz $FILES"

# Fetch Kafka Tar
for version in 0.9.0.1; do
  mkdir -p kafka/${version}/
  if ! [[ -f kafka/${version}/kafka_2.11-${version}.tgz ]]; then
    pushd kafka/${version}/
    while ! $(file kafka_2.11-${version}.tgz | grep -q 'gzip compressed data'); do
      $CURL -O -L http://mirrors.ocf.berkeley.edu/apache/kafka/${version}/kafka_2.11-${version}.tgz
    done
    popd
  fi
  FILES="kafka_2.11-${version}.tgz $FILES"
done

# Fetch Java Tar
if ! [[ -f jdk-8u101-linux-x64.tar.gz ]]; then
  while ! $(file jdk-8u101-linux-x64.tar.gz | grep -q 'gzip compressed data'); do
    $CURL -O -L -C - -b "oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jdk/8u101-b13/jdk-8u101-linux-x64.tar.gz
  done
fi
FILES="jdk-8u101-linux-x64.tar.gz $FILES"

if ! [[ -f jce_policy-8.zip ]]; then
  while ! $(file jce_policy-8.zip | grep -q 'Zip archive data'); do
    $CURL -O -L -C - -b "oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jce/8/jce_policy-8.zip
  done
fi
FILES="jce_policy-8.zip $FILES"

# Pull all the (unversioned) gems required for the cluster 
for i in patron wmi-lite simple-graphite ruby-augeas chef-rewind; do
  if ! [[ -f gems/${i}.gem ]]; then
    gem fetch ${i}
    ln -s ${i}-*.gem ${i}.gem || true
  fi
  FILES="${i}*.gem $FILES"
done

# Get the Rubygem for mysql2
if ! [[ -f gems/mysql2.gem ]]; then
  gem fetch mysql2 -v 0.4.4
  ln -s mysql2-*.gem mysql2.gem || true
fi
FILES="mysql2*.gem $FILES"

# Get the Rubygem for kerberos
if ! [[ -f gems/rake-compiler.gem ]]; then
  gem fetch rake-compiler
  ln -s rake-compiler*.gem rake-compiler.gem || true
fi
FILES="rake-compiler*.gem $FILES"

# Get the Rubygem for sequel
if ! [[ -f gems/sequel.gem ]]; then
  gem fetch sequel -v 4.36.0
  ln -s sequel-*.gem sequel.gem || true
fi
FILES="sequel*.gem $FILES"

# Get the Rubygem for rkerberos
if ! [[ -f gems/rkerberos.gem ]]; then
  gem fetch rkerberos
  ln -s rkerberos*.gem rkerberos.gem || true
fi
FILES="rkerberos*.gem $FILES"

# Get the Rubygem for webhdfs
if ! [[ -f gems/webhdfs.gem ]]; then
  gem fetch webhdfs -v 0.5.5
  ln -s webhdfs-*.gem webhdfs.gem || true
fi
FILES="webhdfs*.gem $FILES"

# Get Rubygem for zabbixapi
if ! [[ -f gems/zabbixapi.gem ]]; then
  gem fetch zabbixapi -v ${ZABBIXAPI_VERSION}
  ln -s zabbix*.gem zabbixapi.gem || true
fi
FILES="zabbix*.gem $FILES"

# Get the Rubygem for zookeeper
if ! [[ -f gems/zookeeper.gem ]]; then
  gem fetch zookeeper -v 1.4.7
  ln -s zookeeper-*.gem zookeeper.gem || true
fi
FILES="zookeeper*.gem $FILES"

# Fetch the cirros image for testing
if ! [[ -f cirros-0.3.0-x86_64-disk.img ]]; then
  while ! $(file cirros-0.3.0-x86_64-disk.img | grep -q 'QEMU QCOW Image'); do
    $CURL -O -L https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-x86_64-disk.img
  done
fi
FILES="cirros-0.3.0-x86_64-disk.img $FILES"

# Grab the Ubuntu 14.04 installer image with a 4.4 "HWE" kernel from Xenial
TRUSTY_IMAGE="ubuntu-14.04-hwe44-mini.iso"
if ! [[ -f $TRUSTY_IMAGE ]]; then
    while ! $(file $TRUSTY_IMAGE | grep -qE '(x86 boot sector)|(ISO 9660 CD-ROM)'); do
	$CURL -o $TRUSTY_IMAGE http://archive.ubuntu.com/ubuntu/dists/trusty-updates/main/installer-amd64/current/images/xenial-netboot/mini.iso
    done
fi
FILES="$TRUSTY_IMAGE $FILES"

# Grab the Ubuntu 12.04 installer image with a 3.13 kernel.
PRECISE_IMAGE="ubuntu-12.04-hwe313-mini.iso"
if ! [[ -f $PRECISE_IMAGE ]]; then
    while ! $(file $PRECISE_IMAGE | grep -qE '(x86 boot sector)|(ISO 9660 CD-ROM)'); do
	$CURL -o $PRECISE_IMAGE http://archive.ubuntu.com/ubuntu/dists/precise-updates/main/installer-amd64/current/images/trusty-netboot/mini.iso
    done
fi
FILES="$PRECISE_IMAGE $FILES"


# Make the diamond package
if ! [[ -f diamond.deb ]]; then
  git clone https://github.com/BrightcoveOS/Diamond.git
  pushd Diamond
  git checkout $VER_DIAMOND
  make builddeb
  VERSION=`cat version.txt`
  popd
  mv Diamond/build/diamond_${VERSION}_all.deb diamond.deb
  rm -rf Diamond
fi
FILES="diamond.deb $FILES"

# Fetch pyrabbit
if ! [[ -f python/pyrabbit-1.0.1.tar.gz ]]; then
  while ! $(file python/pyrabbit-1.0.1.tar.gz | grep -q 'gzip compressed data'); do
    (cd python && $CURL -O -L http://pypi.python.org/packages/source/p/pyrabbit/pyrabbit-1.0.1.tar.gz)
  done
fi
FILES="pyrabbit-1.0.1.tar.gz $FILES"

if ! [[ -f python-pyparsing_2.0.6_all.deb ]]; then
  while ! $(file pyparsing-2.0.6.zip | grep -q 'Zip archive data'); do
    $CURL -O -L https://pypi.python.org/packages/source/p/pyparsing/pyparsing-2.0.6.zip
  done
  unzip -o pyparsing-2.0.6.zip; rm pyparsing-2.0.6.zip
  fpm --epoch $EPOCH --log info --python-install-bin /opt/graphite/bin -f -s python -t deb pyparsing-2.0.6/setup.py
fi
FILES="python-pyparsing_2.0.6_all.deb $FILES"

if ! [[ -f python-pytz_2015.6_all.deb ]]; then 
  while ! $(file pytz-2015.6.zip | grep -q 'Zip archive data'); do
    $CURL -O -L https://pypi.python.org/packages/source/p/pytz/pytz-2015.6.zip
  done
  unzip -o pytz-2015.6.zip; rm pytz-2015.6.zip
  fpm --epoch $EPOCH --log info --python-install-bin /opt/graphite/bin -f -s python -t deb pytz-2015.6/setup.py
fi
FILES="python-pytz_2015.6_all.deb $FILES"

# build Django 
if ! [[ -f python-django_1.5.4_all.deb ]]; then
  while ! $(file Django-1.5.4.tar.gz | grep -q 'gzip compressed data'); do
    $CURL -O -L https://pypi.python.org/packages/source/D/Django/Django-1.5.4.tar.gz
  done
  tar -xzvf Django-1.5.4.tar.gz; rm Django-1.5.4.tar.gz
  fpm --epoch $EPOCH --log info --python-install-bin /opt/graphite/bin -f -s python -t deb Django-1.5.4/setup.py
fi
FILES="python-django_1.5.4_all.deb $FILES"


# Build graphite packages
if ! [[ -f python-carbon_0.9.10_all.deb  && \
        -f python-whisper_0.9.10_all.deb  && \
        -f python-graphite-web_0.10.0-alpha_all.deb ]]; then
  # pull from github
  # until PR https://github.com/graphite-project/graphite-web/pull/1320 is merged 
  #$CURL -O -L https://github.com/graphite-project/graphite-web/archive/master.zip
  #unzip -o master.zip; rm master.zip
  while ! $(file https_intracluster.zip | grep -q 'Zip archive data'); do
    $CURL -O -L https://github.com/pu239ppy/graphite-web/archive/https_intracluster.zip 
  done
  unzip -o https_intracluster.zip
  while ! $(file carbon_master.zip | grep -q 'Zip archive data'); do
    $CURL -L https://github.com/graphite-project/carbon/archive/master.zip -o carbon_master.zip
  done
  unzip -o carbon_master.zip
  while ! $(file whisper_master.zip | grep -q 'Zip archive data'); do
    $CURL -L https://github.com/graphite-project/whisper/archive/master.zip -o whisper_master.zip
  done
  unzip -o whisper_master.zip
  # build with FPM
  fpm --epoch $EPOCH --log info --python-install-bin /opt/graphite/bin -f -s python -t deb carbon-master/setup.py
  fpm --epoch $EPOCH --log info --python-install-bin /opt/graphite/bin  -f -s python -t deb whisper-master/setup.py
  # until PR https://github.com/graphite-project/graphite-web/pull/1320 is merged 
  #fpm --epoch $EPOCH --log info --python-install-lib /opt/graphite/webapp -f -s python -t deb graphite-web-master/setup.py
  fpm --epoch $EPOCH --log info --python-install-lib /opt/graphite/webapp -f -s python -t deb graphite-web-https_intracluster/setup.py
  rm -rf carbon-master
  rm -rf whisper-master
  rm -rf graphite-web-https_intracluster

fi
FILES="python-carbon_0.9.10_all.deb python-whisper_0.9.10_all.deb python-graphite-web_0.10.0-alpha_all.deb $FILES"


# Download Python requests-aws for Zabbix monitoring
if ! [[ -f python-requests-aws_0.1.5_all.deb ]]; then
  fpm --log info -s python -t deb -v 0.1.5 requests-aws
fi
FILES="python-requests-aws_0.1.5_all.deb $FILES"

# Gather the Chef packages and provide a dpkg repo
opscode_urls="https://opscode-omnibus-packages.s3.amazonaws.com/ubuntu/12.04/x86_64/chef_11.12.8-2_amd64.deb
https://opscode-omnibus-packages.s3.amazonaws.com/ubuntu/12.04/x86_64/chef-server_11.1.1-1_amd64.deb
https://packages.chef.io/stable/ubuntu/12.04/chefdk_0.15.16-1_amd64.deb"
for url in $opscode_urls; do
  if ! [[ -f $(basename $url) ]]; then
    $CURL -L -O $url
  fi
done

###################
# generate apt-repo
dpkg-scanpackages . > ${APT_REPO_BINS}/Packages
gzip -c ${APT_REPO_BINS}/Packages > ${APT_REPO_BINS}/Packages.gz
tempfile=$(mktemp)
rm -f ${APT_REPO}/Release
rm -f ${APT_REPO}/Release.gpg
echo -e "Version: ${APT_REPO_VERSION}\nSuite: ${APT_REPO_VERSION}\nComponent: main\nArchitecture: amd64" > ${APT_REPO_BINS}/Release
apt-ftparchive -o APT::FTPArchive::Release::Version=${APT_REPO_VERSION} -o APT::FTPArchive::Release::Suite=${APT_REPO_VERSION} -o APT::FTPArchive::Release::Architectures=amd64 -o APT::FTPArchive::Release::Components=main release dists/${APT_REPO_VERSION} > $tempfile
mv $tempfile ${APT_REPO}/Release

# generate a key and sign repo
if ! [[ -f ${HOME}/apt_key.sec && -f apt_key.pub ]]; then
  rm -rf ${HOME}/apt_key.sec apt_key.pub
  gpg --batch --gen-key << EOF
    Key-Type: DSA
    Key-Length: 4096
    Key-Usage: sign
    Name-Real: Local BCPC Repo
    Name-Comment: For dpkg repo signing
    Expire-Date: 0
    %pubring apt_key.pub
    %secring ${HOME}/apt_key.sec
    %commit
EOF
  chmod 700 ${HOME}/apt_key.sec
fi
gpg --no-tty -abs --keyring ./apt_key.pub --secret-keyring ${HOME}/apt_key.sec -o ${APT_REPO}/Release.gpg ${APT_REPO}/Release

# generate ASCII armored GPG key
gpg --import ./apt_key.pub
gpg -a --export $(gpg --list-public-keys --with-colons | grep 'Local BCPC Repo' | cut -f 5 -d ':') > apt_key.asc
# ensure everything is readable in the bins directory
chmod -R 755 .

####################
# generate Pypi repo
if ! hash dir2pi; then
    PIP_VERSION=`pip --version | perl -nle 'm/pip\s+([\d\.]+)/; print $1'`
    
    # If we have an ancient pip, upgrade it before getting pip2pi.
    if ruby -e "exit 1 if Gem::Version.new('$PIP_VERSION') > \ 
                          Gem::Version.new('1.5.4')"
    then
	# Wheel installs require setuptools >= 0.8 for dist-info support.
	# can then follow http://askubuntu.com/questions/399446
	# but can't upgrade setuptools first as:
	# "/usr/bin/pip install: error: no such option: --no-use-wheel"
	echo "Upgrading pip before pip2pi install"
	/usr/bin/pip install pip2pi || /bin/true
	/usr/local/bin/pip install setuptools --no-use-wheel --upgrade
	/usr/local/bin/pip install pip2pi
    else
	/usr/bin/pip install pip2pi
    fi	 
fi

dir2pi python

#########################
# generate rubygems repos

# need the builder gem to generate a gem index
if [[ -z `gem list --local builder | grep builder | cut -f1 -d" "` ]]; then
  gem install builder --no-ri --no-rdoc
fi

# place all gems into the server normally
[ ! -d gems ] && mkdir gems
[ "$(echo *.gem)" != '*.gem' ] && mv *.gem gems
gem generate_index --legacy

popd

