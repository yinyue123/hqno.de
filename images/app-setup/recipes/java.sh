#!/bin/sh
# app-setup: 1
# id: java
# name: Java (OpenJDK)
# name.zh: Java（OpenJDK）
# category: dev
# order: 13
# summary: OpenJDK, the newest LTS this distro carries. Needed by Halo, Minecraft servers and most .jar files.
# summary.zh: OpenJDK，装本发行版能提供的最新 LTS。Halo、Minecraft 服务端和各种 jar 都要它。
# includes: java, javac, jar
# includes.zh: java 运行时、javac 编译器、jar 打包工具
# disk: 320M
# memory: 512M
. /usr/lib/app-setup/common.sh

CHECK_BIN="java"

version_line() { printf '%s' "$(java -version 2>&1 | head -1 | tr -d '"')"; }

do_install() {
	case "$PMF" in
		deb) pkg_install_first openjdk-21-jdk-headless openjdk-17-jdk-headless \
		                       openjdk-11-jdk-headless default-jdk-headless default-jdk ;;
		rpm) pkg_install_first java-21-openjdk-devel java-17-openjdk-devel \
		                       java-11-openjdk-devel java-latest-openjdk-devel ;;
		apk) pkg_install_first openjdk21 openjdk17 openjdk11 ;;
	esac
	have java || die "java is still not on PATH"
	ok "$(version_line)"
}

do_uninstall() {
	case "$PMF" in
		deb) pkg_remove "$(dpkg-query -W -f='${Package}\n' 'openjdk-*-jdk-headless' 2>/dev/null | head -1)" ;;
		rpm) pkg_remove "$(rpm -qa 'java-*-openjdk-devel' | head -1)" ;;
		apk) pkg_remove "$(apk info 2>/dev/null | grep -m1 '^openjdk')" ;;
	esac
}

do_help() { cat <<'EOF'
Java

  Check it
    java -version
    javac -version

  Run a jar
    java -jar thing.jar
    java -Xmx512m -jar thing.jar        cap the heap — see below

  Set the heap, always, in a container
    The JVM decides how much memory to take from what it thinks the machine
    has. Modern JVMs read the container's cgroup limit correctly, older
    ones read the host's and then get killed. Be explicit:

      java -Xmx512m -Xms128m -jar thing.jar

    A rule of thumb: -Xmx at about half the memory your container was
    given. The JVM uses a good deal more than the heap on top of that
    (metaspace, threads, buffers), and "the container was killed and Java
    logged nothing" is nearly always this.

  Running a jar as a service
    /etc/systemd/system/myapp.service

      [Unit]
      Description=my java app
      After=network.target
      [Service]
      WorkingDirectory=/opt/myapp
      ExecStart=/usr/bin/java -Xmx512m -jar /opt/myapp/app.jar
      Restart=on-failure
      User=nobody
      [Install]
      WantedBy=multi-user.target

  Which version did I get?
    Whichever LTS this distribution carries — 21 where it exists, 17 on
    older releases. Software that demands an exact version will say so; if
    it wants something newer than the distro has, get the tarball from
    adoptium.net and unpack it into /opt.

  JAVA_HOME
    Some build tools want it:
      export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    Put that line in /etc/profile.d/java.sh to make it permanent.

  Disk
    A JDK is around 320MB. If you only need to *run* jars and never compile,
    the -headless JRE packages are about a third of that.
EOF
}

app_main "$@"
