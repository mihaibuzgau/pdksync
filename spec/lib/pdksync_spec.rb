require_relative '../../lib/pdksync'
require 'git'
require 'fileutils'
require 'octokit'

describe PdkSync do
  before(:all) do
    @pdksync_dir = './modules_pdksync'
    module_name = 'puppetlabs-testing'
    @module_names = ['puppetlabs-testing']
    @output_path = "#{@pdksync_dir}/#{module_name}"
    @folder = Dir.pwd
    # Make changes to modules_managed.yaml file
    text = File.read('managed_modules.yml')
    new_contents = text.gsub(%r{#- puppetlabs-testing$}, '- puppetlabs-testing')
    File.open('managed_modules.yml', 'w') { |file| file.puts new_contents }
  end

  before(:each) do
    allow(PdkSync).to receive(:return_modules).and_return(@module_names)
    allow(PdkSync).to receive(:validate_modules_exist).and_return(@module_names)
    Dir.chdir(@folder)
  end

  context 'main method' do
    it 'runs clone sucessfully' do
      FileUtils.rm_rf(@pdksync_dir)
      PdkSync.create_filespace
      PdkSync.main(steps: [:clone])
      expect(Dir.exist?(@pdksync_dir)).to be(true)
      expect(Dir.exist?(@output_path)).to be(true)
    end
    it 'runs pdk convert, and files have changed' do
      PdkSync.main(steps: [:pdk_convert])
      File.exist?("#{@output_path}/convert_report.txt")
    end
    it 'raise when running a command with no argument' do
      expect { PdkSync.main(steps: [:run_a_command]) }.to raise_error(RuntimeError, %r{"run_a_command" requires an argument to run.})
    end
    it 'runs a command "touch cat.meow"' do
      PdkSync.main(steps: [:run_a_command], args: 'touch cat.meow')
      expect File.exist?("#{@output_path}/cat.meow")
    end
    it 'raise when create_commit with no arguments' do
      expect { PdkSync.main(steps: [:create_commit]) }.to raise_error(RuntimeError, %r{Needs a branch_name and commit_message})
    end
    it 'create_commit runs, and contains the "kittens in mittens"' do
      PdkSync.main(steps: [:create_commit], args: { branch_name: 'temp_branch', commit_message: 'kittens in mittens' })
      git_repo = Git.open(@output_path)
      expect(git_repo.show).to include('kittens in mittens')
    end
    it 'raise when create_pr with no arguments' do
      expect { PdkSync.main(steps: [:create_pr]) }.to raise_error(RuntimeError, %r{Needs a pr_title})
    end
    it 'raise when create_pr with invalid label' do
      expect { PdkSync.main(steps: [:create_pr], args: { pr_title: 'My amazing PR', label: 'doot doot' }) }.to raise_error(RuntimeError, %r{Ensure label is valid})
    end
    it 'raise when clean_branches with no arguments' do
      expect { PdkSync.main(steps: [:clean_branches]) }.to raise_error(RuntimeError, %r{Needs a branch_name, and the branch name contains the string pdksync})
    end
    it 'raise when gem_file_update with no arguments' do
      expect { PdkSync.main(steps: [:gem_file_update]) }.to raise_error(NoMethodError)
    end
    it 'gem_file_update runs with invalid gem_line given' do
      expect { PdkSync.main(steps: [:gem_file_update], args: { gem_to_test: 'puppet_litmus', gem_line: "gem 'puppet_litmus'\, git: 'https://github.com/test/puppet_litmus.git'" }) }. to raise_error(Errno::ENOENT) # rubocop:disable Metrics/LineLength
    end
    it 'gem_file_update runs with invalid gem_sha_replacer' do
      expect { PdkSync.main(steps: [:gem_file_update], args: { gem_to_test: 'puppet_litmus', gem_sha_finder: 'jsjsjsjsjsjsjs', gem_sha_replacer: 'abcdefgjhkk' }) }.to raise_error(RuntimeError) # , ("Couldn't find sha: abcdefgjhkk in your repository: puppet_litmus")) # rubocop:disable Metrics/LineLength
    end
    it 'gem_file_update runs with invalid gem_version_replacer' do
      expect { PdkSync.main(steps: [:gem_file_update], args: { gem_to_test: 'puppet_litmus', gem_version_finder: '<= 0.4.9', gem_version_replacer: '<= 1.4.11' }) }.to raise_error(RuntimeError) # , ("Couldn't find version: 1.4.11 in your repository: puppet_litmus")) # rubocop:disable Metrics/LineLength
    end
    it 'gem_file_update runs with invalid gem_branch_replacer' do
      expect { PdkSync.main(steps: [:gem_file_update], args: { gem_to_test: 'puppet_litmus', gem_branch_finder: 'jsjsjsjsjsjsjs', gem_branch_replacer: 'abcdefgjhkk' }) }.to raise_error(RuntimeError) # , "Couldn't find branch: abcdefgjhkk in your repository: puppet_litmus") # rubocop:disable Metrics/LineLength
    end
    it 'raise when run_tests with no arguments' do
      expect { PdkSync.main(steps: [:run_tests]) }.to raise_error(NoMethodError) # , %r{run_tests" requires arguments (module_type) to run.})
    end

    describe 'gem_file_update with valid values' do
      before(:all) do
        # rubocop:disable LineLength
        PdkSync.main(steps: [:gem_file_update], args: { gem_to_test: 'puppet_litmus', gem_line: "gem 'puppet_litmus'\, git: 'https://github.com/puppetlabs/puppet_litmus.git'\, branch: 'master'\, ref: '04da90638f5b5fd7f007123c8c0cc551c8cb3e54'\, '=0.1.0'" })
      end
      it 'gem_file_update with valid gem_branch_replacer' do
        PdkSync.main(steps: [:gem_file_update], args: { gem_to_test: 'puppet_litmus',
                                                        gem_branch_finder: 'master', gem_branch_replacer: 'install_modules_with_puppetfile' })
        expect(File.read('Gemfile')).to match(%r{install_modules_with_puppetfile})
      end
      it 'gem_file_update runs, and contains the gem_sha given' do
        PdkSync.main(steps: [:gem_file_update], args: { gem_to_test: 'puppet_litmus',
                                                        gem_sha_finder: '04da90638f5b5fd7f007123c8c0cc551c8cb3e54', gem_sha_replacer: 'af33ece9e400f0cf7b556f0440627cffe969e03b' })
        expect(File.read('Gemfile')).to match(%r{af33ece9e400f0cf7b556f0440627cffe969e03})
      end
      it 'gem_file_update runs, and contains the gem_version given' do
        PdkSync.main(steps: [:gem_file_update], args: { gem_to_test: 'puppet_litmus',
                                                        gem_version_finder: '=0.1.0', gem_version_replacer: '<=0.3.0' })
        expect(File.read('Gemfile')).to match(%r{0.3.0})
      end
      it 'gem_file_update with valid gem_line' do
        PdkSync.main(steps: [:gem_file_update], args: { gem_to_test: 'puppet_litmus',
                                                        gem_line: "gem 'puppet_litmus'\, git: 'https://github.com/puppetlabs/puppet_litmus.git'" })
        expect(File.read('Gemfile')).to match(%r{gem 'puppet_litmus', git: 'https://github.com/puppetlabs/puppet_litmus.git'})
      end
    end
  end
  after(:all) do
    # Make changes to modules_managed.yaml file
    Dir.chdir(@folder)
    text = File.read('managed_modules.yml')
    new_contents = text.gsub(%r{- puppetlabs-testing$}, '#- puppetlabs-testing')
    File.open('managed_modules.yml', 'w') { |file| file.puts new_contents }
  end
end
