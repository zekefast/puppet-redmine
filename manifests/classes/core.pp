class redmine::core {
	$redmine_id = $operatingsystem ? {
		/Debian|Ubuntu/ => 'www-data',
		Centos => 'apache',
	}

	group { 'redmine':
		ensure => present,
		name => "$redmine_id",
	}	

	user { 'redmine':
		ensure => present,
		name => "$redmine_id",
		gid => "$redmine_id",
		require => Group["$redmine_id"],
	}

	case $operatingsystem {
		'Centos': {realize(Exec['selinux_disable', 'session_store'], File['redmine.conf'])}
		'Debian': {realize(File['sites-available redmine'], Exec['redmine site enable'])}
	}

	@file {
		'redmine.conf':
			name => '/etc/httpd/conf.d/redmine.conf',
			ensure => present,
#			notify => Service["$webserver"],
			content => template('redmine/apache_redmine.conf');

		'sites-available redmine':
			path => '/etc/apache2/sites-available/redmine',
			ensure => present,
			owner => root,
			group => root,
			mode => 0644,
			content => 'RailsBaseURI /redmine',
			require => Package['redmine'];
	}

	@exec {
		'selinux_disable':
			path => '/bin:/usr/bin',
			command => 'system-config-securitylevel-tui -q --selinux="disabled"',
			unless => 'cat /etc/selinux/config|grep "SELINUX=disabled"';
#			notify => Service["$webserver"],
#			before => Service["$webserver"];

		'session_store':
			path => '/bin:/usr/bin:/opt/ruby/bin',
			cwd => '/usr/share/redmine/public',
			provider => 'shell',
			command => 'rake generate_session_store',
			require => Package['gem_rails'];

		'redmine site enable':
			command => '/usr/sbin/a2ensite redmine',
			require => File['/etc/apache2/sites-available/redmine'],
			unless => '/usr/bin/test -f /etc/apache2/sites-enabled/redmine';
	}
}