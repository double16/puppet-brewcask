require "tempfile"
require "puppet/provider/package"
require "puppet/util/execution"

Puppet::Type.type(:package).provide :brewcask, :parent => Puppet::Provider::Package do
  include Puppet::Util::Execution

  confine :operatingsystem => :darwin

  has_feature :versionable
  has_feature :install_options

  # no caching, thank you
  def self.instances
    []
  end

  def self.home
    Facter.value(:homebrew_root)
  end

  def self.caskroom
    if legacy_caskroom.exist?
      legacy_caskroom.to_s
    else
      new_caskroom.to_s
    end
  end

  def self.current(name)
    caskdir = Pathname.new "#{caskroom}/#{name}"
    caskdir.directory? && caskdir.children.size >= 1 && caskdir.children.sort.last.to_s
  end

  def self.legacy_caskroom
    @legacy_caskroom ||= Pathname.new('/opt/homebrew-cask/Caskroom')
  end

  def self.new_caskroom
    @new_caskroom ||= Pathname.new("#{home}/Caskroom")
  end

  def query
    return unless version = self.class.current(resource[:name])
    { :ensure => version, :name => resource[:name] }
  end

  def install
    begin
      sudo_script = askpass_script
      opts = command_opts
      opts[:custom_environment]['SUDO_ASKPASS'] = sudo_script.path

      if install_options.any?
        execute ["brew", "install", "Caskroom/cask/#{resource[:name]}", *install_options].flatten, opts
      else
        execute ["brew", "install", "Caskroom/cask/#{resource[:name]}"], opts
      end
    ensure
      sudo_script.unlink
    end
  end

  def uninstall
    execute ["brew", "cask", "uninstall", "--force", resource[:name]]
  end

  def install_options
    Array(resource[:install_options]).flatten.compact
  end

  private
  # Override default `execute` to run super method in a clean
  # environment without Bundler, if Bundler is present
  def execute(*args)
    if Puppet.features.bundled_environment?
      Bundler.with_clean_env do
        super
      end
    else
      super
    end
  end

  # Override default `execute` to run super method in a clean
  # environment without Bundler, if Bundler is present
  def self.execute(*args)
    if Puppet.features.bundled_environment?
      Bundler.with_clean_env do
        super
      end
    else
      super
    end
  end

  def default_user
    Facter.value(:boxen_user) || Facter.value(:id) || "root"
  end

  def command_opts
    opts = {
      :combine               => true,
      :custom_environment    => {
        "HOME"               => "/Users/#{default_user}",
        "PATH"               => "#{self.class.home}/bin:/usr/bin:/usr/sbin:/bin:/sbin",
        "HOMEBREW_NO_EMOJI"  => "Yes",
      },
      :failonfail            => true,
    }
    # Only try to run as another user if Puppet is run as root.
    opts[:uid] = default_user if Process.uid == 0
    opts
  end

  def askpass_script
    f = Tempfile.new('askpass', '/tmp')
    f.write(%{#!/bin/bash

APP_NAME=Terminal
term_pid=$PPID
while [ $term_pid -ne 1 ]; do
	ps="$(ps -o command= -p $term_pid)"
	if [[ "$ps" =~ Terminal ]]; then
		APP_NAME=Terminal
	fi
	if [[ "$ps" =~ iTerm ]]; then
		APP_NAME=iTerm.app
	fi
	term_pid=$(ps -o ppid= -p $term_pid)
done

osascript \\
	-e "Tell application \\"${APP_NAME}\\" to display dialog \\"Password for installing #{resource[:name]}:\\" default answer \\"\\" with hidden answer" \\
	-e 'text returned of result' 2>/dev/null
})
    f.chmod(0755)
    f.close
    f
  end
end
