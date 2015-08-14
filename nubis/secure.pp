include sudoers::dns
include collectd::plugins
include dns::ssh_client_keys

realize(Collectd::Plugin['dns'])

class {
    'tzdata':
        timezone => 'UTC';
}

file {
    ['/etc/facter/facts.d/dns_view', '/etc/facter/facts.d/dns_view.yaml']:
        ensure => absent,
}

case $::operatingsystemrelease {
    /^5/: {
        $package_prefix="bind97"
        $package_version='present'
    }
    /^6/: {
        $package_prefix="bind"
        $package_version='present'
    }
}

package {
    $package_prefix:
        ensure => $package_version;
    "${package_prefix}-utils":
        ensure => $package_version;
    "${package_prefix}-chroot":
        ensure => $package_version;
    "${package_prefix}-libs":
        ensure => $package_version;
    'dnstop':
        ensure => installed;
}

package {
    'mtree':
        ensure => latest,
}

realize(Package['subversion'])
realize(Nrpe::Plugin["dns_health"])
realize(Nrpe::Plugin["dns_soa"])

service {
    'named':
        ensure     => running,
        enable     => true,
        hasstatus  => true,
        hasrestart => false,
        require    => Package[$package_prefix];
}

user {
    'named-update':
        ensure => present,
        system => true,
        home   => '/var/named';
}

file {
    '/var/named':
        ensure  => directory,
        mode    => '0711',
        owner   => "named",
        group   => 'named';

    '/var/named/.ssh':
        ensure  => directory,
        owner   => "named-update",
        group   => "named",
        mode    => '0700',
        require => User['named-update'];

    '/var/named/.subversion':
        ensure  => directory,
        owner   => "named-update",
        group   => "named",
        mode    => '0700',
        require => User['named-update'];

    '/var/named/.ssh/config':
        ensure  => present,
        owner   => "named-update",
        group   => "named",
        mode    => '0600',
        source  => "puppet:///modules/dns/ssh/config",
        require => User['named-update'];

    '/var/named/.ssh/known_hosts':
        ensure  => present,
        owner   => "named-update",
        group   => "named",
        mode    => '0644',
        source  => "puppet:///modules/secrets/svn/known_hosts",
        require => User['named-update'];

    '/var/named/chroot':
        ensure  => directory,
        mode    => '0711',
        owner   => "root",
        group   => "named",
        before  => Service['named'],
        require => Package["${package_prefix}-chroot"];

    '/var/named/chroot/var':
        ensure  => directory,
        mode    => '0711',
        owner   => "root",
        group   => "named",
        before  => Service['named'];

    '/var/named/chroot/var/named':
        ensure  => directory,
        mode    => '0755',
        owner   => "named-update",
        group   => "named",
        before  => Service['named'];

    '/var/named/chroot/var/log':
        ensure  => directory,
        mode    => '0755',
        owner   => "named",
        group   => "named",
        before  => Service['named'];

    '/var/named/chroot/var/log/named':
        ensure  => directory,
        mode    => '0755',
        owner   => "named",
        group   => "named",
        before  => Service['named'];

    '/var/named/chroot/var/run':
        ensure  => directory,
        owner   => "root",
        group   => "root",
        mode    => '0755',
        before  => Service['named'];

    '/var/named/chroot/var/run/named':
        ensure  => directory,
        owner   => "named",
        group   => "named",
        mode    => '0770',
        before  => Service['named'];

    '/var/named/chroot/var/run/namedctl':
        ensure  => directory,
        owner   => "named-update",
        group   => "named-update",
        mode    => '0755',
        before  => Service['named'];

    '/var/named/chroot/var/lock':
        ensure  => directory,
        owner   => "named-update",
        group   => "named",
        mode    => '0755';

    '/var/named/chroot/var/tmp':
        ensure  => directory,
        owner   => named,
        group   => named,
        mode    => '0770',
        before  => Service['named'];

    # /var/named/config/global-options:145: open: /etc/named-forwarding.conf: file not found
    '/var/named/chroot/etc/named-forwarding.conf':
        ensure  => present,
        before  => Service['named'];

    '/var/named/chroot/var/named/slaves':
        ensure  => directory,
        mode    => '0770',
        owner   => "named",
        group   => "named-update",
        before  => Service['named'],
        require => [
            Package["${package_prefix}-chroot"],
            Exec["dns-svn-checkout"],
        ];

    '/var/named/chroot/var/named/dynamic':
        ensure => directory,
        owner  => "named",
        group  => "named-update",
        mode    => '0770',
        before  => Service['named'],
        require => [
            Package["${package_prefix}-chroot"],
            Exec["dns-svn-checkout"],
        ];

    '/var/named/chroot/etc':
        ensure  => directory,
        owner   => "named",
        group   => "named",
        mode    => '0755',
        before  => Service['named'];

    '/var/named/chroot/etc/rndc.key':
        ensure  => file,
        mode    => '0640',
        owner   => "root",
        group   => "named",
        require => Exec["rndc-keygen"];

    '/var/named/chroot/etc/named.conf':
        ensure  => file,
        content => template("dns/named.conf-master.erb"),
        require => Package[$package_prefix],
        notify  => Service['named'];

    '/etc/named.conf':
        ensure  => file,
        content => template("dns/named.conf-master.erb"),
        require => Package[$package_prefix],
        notify  => Service['named'];

    '/etc/sysconfig/named':
        ensure  => file,
        mode    => '0644',
        source  => "puppet:///modules/dns/sysconfig/named",
        before  => Service['named'],
        require => Package[$package_prefix];
    #   notify  => Service['named'];

    '/etc/cron.d/named':
        ensure  => present,
        owner   => root,
        group   => root,
        mode    => '0644',
        source  => ["puppet:///modules/dns/cron.d/${::fqdn}.named", 'puppet:///modules/dns/cron.d/named'];

    '/usr/local/bin/namedctl':
        ensure  => present,
        owner   => root,
        group   => root,
        mode    => '0755',
        content => template('dns/bin/namedctl.erb');

    '/etc/rndc.key':
        ensure => link,
        target => '/var/named/chroot/etc/rndc.key';
}

exec {
    'rndc-keygen':
        cwd       => "/var/named/chroot/etc",
        command   => "/usr/sbin/rndc-confgen -r /dev/urandom -a -k rndckey -b 384 -c rndc.key",
        creates   => "/var/named/chroot/etc/rndc.key",
        logoutput => on_failure,
        before    => Service['named'],
        require   => [ Package[$package_prefix], Exec["dns-svn-checkout"] ];

    'ssh-keygen':
        command => "/usr/bin/ssh-keygen -t rsa -C ${::fqdn} -N '' -f /var/named/.ssh/id_rsa",
        creates => "/var/named/.ssh/id_rsa",
        user    => "named-update",
        require => File['/var/named/.ssh'],
        before  => Exec["dns-svn-checkout"];

    # The install script for bind makes /var/named/chroot/var/named/slaves, which angers svn checkout
    'dns-svn-cleanup':
        cwd         => "/var/named/chroot/var/named/",
        command     => "/bin/rm -rf /var/named/chroot/var/named/slaves /var/named/chroot/var/named/data",
        environment => "SVN_SSH=/usr/bin/ssh -oStrictHostKeyChecking=no",
        onlyif      => '/usr/bin/test -d /var/named/chroot/var/named/slaves -a \! -d /var/named/chroot/var/named/.svn',
        require     => Package["${package_prefix}-chroot"];

    'dns-svn-checkout':
        cwd         => "/var/named/chroot/var/named/",
        command     => "/usr/bin/svn checkout --non-interactive --config-dir /var/named/.subversion svn+ssh://dnsconfig@svn.mozilla.org/sysadmins/dnsconfig/ .",
        environment => "SVN_SSH=/usr/bin/ssh -oStrictHostKeyChecking=no",
        creates     => "/var/named/chroot/var/named/.svn",
        logoutput   => on_failure,
        user        => "named-update",
        require     => [
            File['/var/named/chroot/var/named'],
            File['/var/named/.ssh/id_rsa'],
            Package['subversion'],
            Exec["dns-svn-cleanup"],
        ],
        before      => Service['named'];

    # Bug 845107
    'enforce-ownership':
        path        => '/usr/bin:/usr/sbin:/bin:/sbin',
        command     => '/usr/bin/find /var/named/chroot/var/named \( -type d -name dynamic -prune -o -type d -name slaves -prune \) -o -not -user named-update -exec chown -h named-update:named-update {} \;',
        onlyif      => '/usr/bin/find /var/named/chroot/var/named \( -type d -name dynamic -prune -o -type d -name slaves -prune \) -o -not -user named-update -print | /bin/grep -q ".*"',
        require     => Exec["dns-svn-checkout"]
}

host {
    'svn.mozilla.org':
        ensure  => present,
        ip      => "63.245.217.46",
        comment => "Need this for the nameservers to access svn via the external interface";
}

cron {
    'update-named':
        ensure => absent;
}

file {
    '/usr/local/libexec/dns-server-patch':
        ensure => present,
        mode => 0755,
        owner => 'root',
        group => '0',
        source => 'puppet:///modules/dns/bin/dns-server-patch',
}
