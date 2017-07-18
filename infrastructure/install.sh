#!/bin/sh
set -e

# This script detects the current linux distribution and
# installs the corresponding NewRelic Infrastructure agent

# It configures the NewRelic license key from the NEWRELIC_LICENSE_KEY global variable

command_exists() {
    command -v "$@" > /dev/null 2>&1
}

# Check if this is a forked Linux distro
check_forked() {

    # Check for lsb_release command existence, it usually exists in forked distros
    if command_exists lsb_release; then
        # Check if the `-u` option is supported
        set +e
        lsb_release -a -u > /dev/null 2>&1
        lsb_release_exit_code=$?
        set -e

        # Check if the command has exited successfully, it means we're in a forked distro
        if [ "$lsb_release_exit_code" = "0" ]; then
            # Print info about current distro
            cat <<-EOF
			you're using '$lsb_dist' version '$dist_version'.
			EOF

            # Get the upstream release info
            lsb_dist=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'id' | cut -d ':' -f 2 | tr -d '[[:space:]]')
            dist_version=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'codename' | cut -d ':' -f 2 | tr -d '[[:space:]]')

            # Print info about upstream distro
            cat <<-EOF
			Upstream release is '$lsb_dist' version '$dist_version'.
			EOF
        else
            if [ -r /etc/debian_version ] && [ "$lsb_dist" != "ubuntu" ] && [ "$lsb_dist" != "raspbian" ]; then
                # We're Debian and don't even know it!
                lsb_dist=debian
                dist_version="$(cat /etc/debian_version | sed 's/\/.*//' | sed 's/\..*//')"
                case "$dist_version" in
                    9)
                        dist_version="stretch"
                    ;;
                    8|'Kali Linux 2')
                        dist_version="jessie"
                    ;;
                    7)
                        dist_version="wheezy"
                    ;;
                esac
            fi
        fi
    fi
}

do_install() {

    architecture=$(uname -m)
    case $architecture in
        # supported
        amd64|x86_64)
            ;;
        # not supported
        *)
            cat >&2 <<-EOF
			Error: $architecture is not a supported platform.
			EOF
            exit 1
            ;;
    esac

    user="$(id -un 2>/dev/null || true)"

    sh_c='sh -c'
    if [ "$user" != 'root' ]; then
        if command_exists sudo; then
            sh_c='sudo -E sh -c'
        elif command_exists su; then
            sh_c='su -c'
        else
            cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
            exit 1
        fi
    fi

    # perform some very rudimentary platform detection
    lsb_dist=''
    dist_version=''
    if command_exists lsb_release; then
        lsb_dist="$(lsb_release -si)"
    fi
    if [ -z "$lsb_dist" ] && [ -r /etc/lsb-release ]; then
        lsb_dist="$(. /etc/lsb-release && echo "$DISTRIB_ID")"
    fi
    if [ -z "$lsb_dist" ] && [ -r /etc/debian_version ]; then
        lsb_dist='debian'
    fi
    if [ -z "$lsb_dist" ] && [ -r /etc/fedora-release ]; then
        lsb_dist='fedora'
    fi
    if [ -z "$lsb_dist" ] && [ -r /etc/oracle-release ]; then
        lsb_dist='oracleserver'
    fi
    if [ -z "$lsb_dist" ] && [ -r /etc/centos-release ]; then
        lsb_dist='centos'
    fi
    if [ -z "$lsb_dist" ] && [ -r /etc/redhat-release ]; then
        lsb_dist='redhat'
    fi
    if [ -z "$lsb_dist" ] && [ -r /etc/os-release ]; then
        lsb_dist="$(. /etc/os-release && echo "$ID")"
    fi

    lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

    # Special case redhatenterpriseserver
    if [ "${lsb_dist}" = "redhatenterpriseserver" ]; then
        # Set it to redhat, it will be changed to centos below anyways
        lsb_dist='redhat'
    fi

    case "$lsb_dist" in

        ubuntu)
            if command_exists lsb_release; then
                dist_version="$(lsb_release --codename | cut -f2)"
            fi
            if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
                dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
            fi
        ;;

        debian)
            dist_version="$(cat /etc/debian_version | sed 's/\/.*//' | sed 's/\..*//')"
            case "$dist_version" in
                9)
                    dist_version="stretch"
                ;;
                8)
                    dist_version="jessie"
                ;;
                7)
                    dist_version="wheezy"
                ;;
            esac
        ;;

        oracleserver)
            # need to switch lsb_dist to match yum repo URL
            lsb_dist="oraclelinux"
            dist_version="$(rpm -q --whatprovides redhat-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//')"
        ;;

        fedora|centos|redhat)
            dist_version="$(rpm -q --whatprovides ${lsb_dist}-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//' | sort | tail -1)"
        ;;

        *)
            if command_exists lsb_release; then
                dist_version="$(lsb_release --codename | cut -f2)"
            fi
            if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
                dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
            fi
        ;;


    esac

    # Check if this is a forked Linux distro
    check_forked

    # Setup licence key file
    $sh_c "echo \"license_key: $NEWRELIC_LICENSE_KEY\" | sudo tee -a /etc/newrelic-infra.yml"

    # Run setup for each distro accordingly
    case "$lsb_dist" in
        ubuntu|debian)
            pre_reqs="apt-transport-https ca-certificates curl"
            if [ "$lsb_dist" = "debian" ] && [ "$dist_version" = "wheezy" ]; then
                pre_reqs="$pre_reqs python-software-properties"
                backports="deb http://ftp.debian.org/debian wheezy-backports main"
                if ! grep -Fxq "$backports" /etc/apt/sources.list; then
                    (set -x; $sh_c "echo \"$backports\" >> /etc/apt/sources.list")
                fi
            else
                pre_reqs="$pre_reqs software-properties-common"
            fi
            if ! command_exists gpg; then
                pre_reqs="$pre_reqs gnupg"
            fi
            apt_repo="deb [arch=$(dpkg --print-architecture)] https://download.newrelic.com/infrastructure_agent/linux/apt $dist_version main"
            (
                set -x
                $sh_c 'apt-get update'
                $sh_c "apt-get install -y -q $pre_reqs"
                curl -fsSl "https://download.newrelic.com/infrastructure_agent/gpg/newrelic-infra.gpg" | $sh_c 'apt-key add -'
                $sh_c "add-apt-repository \"$apt_repo\""
                $sh_c 'apt-get update'
                $sh_c 'apt-get install -y -q newrelic-infra'
            )
            exit 0
            ;;
        centos|redhat)
            yum_repo="https://download.newrelic.com/infrastructure_agent/linux/yum/el/$dist_version/x86_64/newrelic-infra.repo"
            pkg_manager="yum"
            config_manager="yum-config-manager"
            enable_channel_flag="--enable"
            pre_reqs="yum-utils"
            (
                set -x
                $sh_c "$pkg_manager install -y -q $pre_reqs"
                $sh_c "$config_manager --add-repo $yum_repo"
                $sh_c "$pkg_manager makecache -y fast"
                $sh_c "$pkg_manager install -y -q newrelic-infra"
                if [ -d '/run/systemd/system' ]; then
                    $sh_c 'service newrelic-infra start'
                else
                    $sh_c 'systemctl start newrelic-infra'
                fi
            )
            exit 0
            ;;

    esac

    # intentionally mixed spaces and tabs here -- tabs are stripped by "<<-'EOF'", spaces are kept in the output
    cat >&2 <<-'EOF'
	Either your platform is not easily detectable or is not supported by this
	installer script.
	Please visit the following URL for more detailed installation instructions:
	https://docs.newrelic.com/docs/infrastructure/new-relic-infrastructure/installation/install-infrastructure-linux
	EOF
    exit 1
}

# wrapped up in a function so that we have some protection against only getting
# half the file during "curl | sh"
do_install
