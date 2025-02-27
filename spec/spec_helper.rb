# frozen_string_literal: true

require 'puppetlabs_spec_helper/module_spec_helper'
require 'rspec-puppet'
require 'simp/rspec-puppet-facts'
include Simp::RspecPuppetFacts

require 'pathname'

# RSpec Material
fixture_path = File.expand_path(File.join(__FILE__, '..', 'fixtures'))
module_name = File.basename(File.expand_path(File.join(__FILE__, '../..')))

# Add fixture lib dirs to LOAD_PATH. Work-around for PUP-3336
if Puppet.version < '4.0.0'
  Dir["#{fixture_path}/modules/*/lib"].entries.each do |lib_dir|
    $LOAD_PATH << lib_dir
  end
end

unless ENV.key?('TRUSTED_NODE_DATA')
  warn '== WARNING: TRUSTED_NODE_DATA is unset, using TRUSTED_NODE_DATA=yes'
  ENV['TRUSTED_NODE_DATA'] = 'yes'
end

default_hiera_config = <<-DEFAULT_HIERA_CONFIG
---
:backends:
  - "yaml"
:yaml:
  :datadir: "stub"
:hierarchy:
  - "%{custom_hiera}"
  - "%{module_name}"
  - "default"
DEFAULT_HIERA_CONFIG

# This can be used from inside your spec tests to set the testable environment.
# You can use this to stub out an ENC.
#
# Example:
#
# context 'in the :foo environment' do
#   let(:environment){:foo}
#   ...
# end
#
def set_environment(environment = :production)
  RSpec.configure { |c| c.default_facts['environment'] = environment.to_s }
end

# This can be used from inside your spec tests to load custom hieradata within
# any context.
#
# Example:
#
# describe 'some::class' do
#   context 'with version 10' do
#     let(:hieradata){ "#{class_name}_v10" }
#     ...
#   end
# end
#
# Then, create a YAML file at spec/fixtures/hieradata/some__class_v10.yaml.
#
# Hiera will use this file as it's base of information stacked on top of
# 'default.yaml' and <module_name>.yaml per the defaults above.
#
# Note: Any colons (:) are replaced with underscores (_) in the class name.
def set_hieradata(hieradata)
  RSpec.configure { |c| c.default_facts['custom_hiera'] = hieradata }
end

unless File.directory?(File.join(fixture_path, 'hieradata'))
  FileUtils.mkdir_p(File.join(fixture_path, 'hieradata'))
end

unless File.directory?(File.join(fixture_path, 'modules', module_name))
  FileUtils.mkdir_p(File.join(fixture_path, 'modules', module_name))
end

RSpec.configure do |c|
  # If nothing else...
  c.default_facts = {
    :production => {
      :path => '/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin',
      :concat_basedir => '/tmp'
    }
  }

  c.mock_framework = :rspec
  c.mock_with :mocha

  c.module_path = File.join(fixture_path, 'modules')
  c.manifest_dir = File.join(fixture_path, 'manifests')

  c.hiera_config = File.join(fixture_path, 'hieradata', 'hiera.yaml')

  # Useless backtrace noise
  backtrace_exclusion_patterns = [
    %r{spec_helper},
    %r{gems},
  ]

  if c.respond_to?(:backtrace_exclusion_patterns)
    c.backtrace_exclusion_patterns = backtrace_exclusion_patterns
  elsif c.respond_to?(:backtrace_clean_patterns)
    c.backtrace_clean_patterns = backtrace_exclusion_patterns
  end

  # rubocop:disable RSpec/BeforeAfterAll
  c.before(:all) do
    # rubocop:disable Security/YAMLLoad
    data = YAML.load(default_hiera_config)
    # rubocop:enable Security/YAMLLoad
    data[:yaml][:datadir] = File.join(fixture_path, 'hieradata')

    File.open(c.hiera_config, 'w') do |f|
      f.write data.to_yaml
    end
  end
  # rubocop:enable RSpec/BeforeAfterAll

  c.before(:each) do
    @spec_global_env_temp = Dir.mktmpdir('simpspec')

    if defined?(environment)
      set_environment(environment)
      FileUtils.mkdir_p(File.join(@spec_global_env_temp, environment.to_s))
    end

    # ensure the user running these tests has an accessible environmentpath
    Puppet[:environmentpath] = @spec_global_env_temp
    Puppet[:user] = Etc.getpwuid(Process.uid).name
    Puppet[:group] = Etc.getgrgid(Process.gid).name

    # sanitize hieradata
    if defined?(hieradata)
      set_hieradata(hieradata.gsub(':', '_'))
    elsif defined?(class_name)
      set_hieradata(class_name.gsub(':', '_'))
    end
  end

  c.after(:each) do
    # clean up the mocked environmentpath
    FileUtils.rm_rf(@spec_global_env_temp)
    @spec_global_env_temp = nil
  end
end

Dir.glob("#{RSpec.configuration.module_path}/*").each do |dir|
  begin
    Pathname.new(dir).realpath
  rescue StandardError => e
    raise "ERROR: The module '#{dir}' is not installed (#{e.message}). Tests cannot continue."
  end
end
