class redmine::packages {
	case $operatingsystem {
		Centos: { include redmine_install_centos }
		Debian: { include redmine_install_debian }
	}

	$redmine_id = $operatingsystem ? {
		/Debian|Ubuntu/ => 'www-data',
		/Centos|Fedora/ => 'apache',
	}

	group { redmine:
		ensure => present,
		name => $redmine_id,
	}	

	user { redmine:
		ensure => present,
		name => $redmine_id,
		gid => $redmine_id,
		require => Group["$redmine_id"],
	}

	package { redmine:
		ensure => installed,
		name => $operatingsystem ? {
			Centos => 'redmine_client',
			Debian => 'redmine',
		},
		provider => $operatingsystem ? {
			Centos => "gem",
			Debian => "apt",
		},
		before => Exec["config_redmine_mysql_bootstrap"],
		require => [ User['redmine'], Class['apache_packages', 'mysql_packages'] ],
	}
}

class redmine_install_debian {
	package { 'redmine-mysql':
		ensure => installed,
		require => Package['redmine'],
	}

	file { '/etc/apache2/sites-available/redmine':
		ensure => present,
		owner => root,
		group => root,
		mode => 0644,
		content => 'RailsBaseURI /redmine',
		require => Package['redmine'],
	}

	exec { 'config_redmine_link_apache':
		command => '/usr/sbin/a2ensite redmine',
		require => File['/etc/apache2/sites-available/redmine'],
		unless => '/usr/bin/test -f /etc/apache2/sites-enabled/redmine',
	}
}

class redmine_install_centos {
	file { '$HOME/.netrc':
		content => 'machine ftp.ruby-lang.org login anonymous password anonymous\nmacdef init\nprompt\ncd /pub/ruby\nget ruby-1.8.7-p334.tar.gz\nbye',
	}

#	exec { 'ruby_centos':
#		path => "/bin:/usr/bin",
#		command => "cd ~/Downloads;ftp ftp.ruby-lang.org;cd /pub/ruby;get ruby-1.8.7-p334.tar.gz;tar xzvf ruby-1.8.7-p334.tar.gz ruby-1.8.7-p334;cd ruby-1.8.7-p334;./configure;make;make install;ruby -v;cd `dirname \`pwd\``",
#		command => "/bin/sh -c 'cd ~/downloads;ftp ftp.ruby-lang.org;tar xzvf ruby-1.8.7-p334.tar.gz ruby-1.8.7-p334;cd ruby-1.8.7-p334;./configure;make;make install;ruby -v;cd `dirname 'which ruby'`'",
#		require => File["$HOME/.netrc"],
#	}

#	exec { 'redmine_centos':
#		path => '/bin:/usr/bin',
#		command => '/bin/sh -c "cd /usr/share/;wget http://rubyforge.org/frs/download.php/74419/redmine-1.1.2.tar.gz;tar zxvf redmine-1.1.2.tar.gz;mv redmine-1.1.2 redmine;chmod -R a+rx /usr/share/redmine/public/;cd /usr/share/redmine;chmod -R 755 files log tmp"',
#		unless => '/usr/bin/test -d /usr/share/redmine',
#	}

	file { '/usr/share/redmine-1.1.3.tar.gz':
		ensure => present,
		source => 'puppet:///modules/redmine/redmine.tar.gz',
	}

	exec { 'extract_redmine':
		path => '/bin:/usr/bin',
		command => 'cd /usr/share && tar xzvf redmine-1.1.3.tar.gz redmine && touch /usr/share/redmine/redmine.puppet',
		require => File['/usr/share/redmine-1.1.3.tar.gz'],
		unless => '/usr/bin/test -f /usr/share/redmine/redmine.puppet',
	}

	file { '/etc/redmine':
		ensure => directory,
		owner => root,
		group => root,
		mode => 0755,
		before => File['/etc/redmine/default'],
	}

	file { '/etc/redmine/default':
		ensure => directory,
		owner => $redmine_id,
		group => $redmine_id,
		mode => 0755,
		before => Class['redmine_config'],
		require => Exec['redmine_centos'],
	}

	package { 'gem_i18n':
		ensure => '0.4.2',
		provider => gem,
		before => Package['gem_rails'],
	}

	package { 'gem_mysql':
		ensure => installed,
		name => mysql,
		provider => gem,
		require => Package['gem_i18n'],
	}

	package { 'gem_rack':
		ensure => '1.0.1',
		name => 'rack',
		provider => gem,
		before => Package['gem_rails'],
	}

	package { 'gem_hoe':
		ensure => installed,
		name => 'hoe',
		provider => gem,
		before => Package['gem_rails'],
	}

	package { 'gem_rails':
		ensure => installed,
		name => 'rails',
		provider => gem,
		before => Exec['config_redmine_mysql_bootstrap'],
	}

	package { 'curl-devel':
		ensure => installed,
	}

	exec { 'build_passenger_modules':
		path => '/bin:/usr/bin:/opt/ruby/bin',
		command => 'passenger-install-apache2-module -a',
		require => Package['$package_apache_mod_passenger'],
		unless => 'test -f /opt/ruby/lib/ruby/gems/1.8/gems/passenger-3.0.7/ext/apache2/mod_passenger.so',
	}

	exec { 'selinux_disable':
		path => '/bin:/usr/bin',
		command => 'system-config-securitylevel-tui -q --selinux="disabled"',
		unless => 'cat /etc/selinux/config|grep "SELINUX=disabled"',
		before => Service['apache'],
		notify => Service['apache'],
	}

	exec { 'session_store':
		path => '/bin:/usr/bin:/opt/ruby/bin',
		command => '/bin/sh -c "cd /usr/share/redmine/public && rake generate_session_store"',
		require => Package['gem_rails'],
	}

	file { '/etc/httpd/conf.d/redmine.conf':
		ensure => present,
		content => '<VirtualHost *:80>\n\tDocumentRoot /usr/share/redmine/public\n\tErrorLog logs/redmine_error_log\n</VirtualHost>',
		notify => Service['apache'],
	}

	exec { 'apache_modules':
		path => '/bin:/usr/bin',
		command => 'echo -e "LoadModule passenger_module /opt/ruby/lib/ruby/gems/1.8/gems/passenger-3.0.7/ext/apache2/mod_passenger.so\nPassengerRoot /opt/ruby/lib/ruby/gems/1.8/gems/passenger-3.0.7\nPassengerRuby /opt/ruby/bin/ruby" >> /etc/httpd/conf/httpd.conf',
		unless => 'cat /etc/httpd/conf/httpd.conf|grep "LoadModule passenger_module"',
		require => Class['apache_mod_passenger', 'rubygems'],
		notify => Service['apache'],
	}
}
