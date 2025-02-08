#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'net/http'
require 'json'
require 'io/console'

def run_command(command, error_message = nil)
  return if system(command)

  puts error_message || "Command failed: #{command}"
  exit 1
end

initial_tty_device_permissions = nil
working_directory = File.join(ENV['HOME'], 'Downloads', 'diy_yadigar')
temp_directory = File.join(working_directory, 'temp')

# --- Define a cleanup lambda to remove temp files and restore TTY permissions ---
cleanup = lambda do
  temp_dir = File.join(working_directory, 'temp')
  FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  tty_device = '/dev/ttyACM0'
  if initial_tty_device_permissions && File.exist?(tty_device)
    current_permissions = format('%o', File.stat(tty_device).mode & 0o777)
    if current_permissions != initial_tty_device_permissions
      run_command("sudo chmod #{initial_tty_device_permissions} #{tty_device}",
                  'Failed to restore tty device permissions')
    end
  end
end
at_exit { cleanup.call }

# --- Configuration Variables ---
jade_repo_url          = 'https://github.com/sukunetsiz/yadigar.git'
esp_idf_repo_url       = 'https://github.com/espressif/esp-idf.git'
esp_idf_git_tag        = 'v5.3.1'
chosen_device          = 'TTGO T-Display'
tty_device             = '/dev/ttyACM0'
jade_save_directory    = File.join(working_directory, 'yadigar')
esp_idf_temp_dir       = File.join(temp_directory, 'esp-idf')
esp_idf_save_directory = File.join(working_directory, 'esp-idf')

# --- Fetch Latest Jade Tag from GitHub API ---
jade_git_tag = nil
begin
  uri      = URI('https://api.github.com/repos/sukunetsiz/yadigar/releases/latest')
  response = Net::HTTP.get(uri)
  data     = JSON.parse(response)
  jade_git_tag = data['tag_name']
rescue StandardError => e
  puts "Failed to fetch latest jade tag: #{e}"
  exit 1
end

# --- Print Header ---
system('clear')
puts '------------------------------------------------------------'
puts '------------------------------------------------------------'
puts '---                                                      ---'
puts '---          Do-It-Yourself Yadigar Install Script       ---'
puts '---                Written by sukunetsiz                 ---'
puts '---                                                      ---'
puts '------------------------------------------------------------'
puts '------------------------------------------------------------'
puts

if Process.uid.zero?
  puts "ALERT: You're running the script as root/superuser.\n" \
       "You may notice PIP 'sudo -H' warnings.\n"
end
puts "LINUX ONLY. Flashing the #{chosen_device}..."

# --- Check Dependencies ---
depends_url = 'https://github.com/sukunetsiz/yadigar-diy/raw/master/depends.txt'
begin
  depends_data = Net::HTTP.get(URI(depends_url))
rescue StandardError => e
  puts "Failed to fetch dependencies list: #{e}"
  exit 1
end

dependencies = depends_data.lines.map(&:strip).reject(&:empty?)
dependencies.each do |dependency|
  next if system("command -v #{dependency} > /dev/null 2>&1")

  install_command = if %w[pip virtualenv].include?(dependency)
                      "sudo apt update && sudo apt install -y python3-#{dependency}"
                    else
                      "sudo apt update && sudo apt install -y #{dependency}"
                    end
  puts "\n\nERROR:\n#{dependency} was not found on your system.\n" \
       "Please install #{dependency} by running:\n\n#{install_command}\n\n"
  exit 1
end

# --- Install ESP-IDF if Needed ---
unless File.exist?(File.join(esp_idf_save_directory, 'export.sh'))
  run_command("git clone --branch #{esp_idf_git_tag} --single-branch --depth 1 " \
              "#{esp_idf_repo_url} #{esp_idf_temp_dir}",
              'Failed to clone ESP-IDF repository')
  Dir.chdir(esp_idf_temp_dir) do
    run_command('git submodule update --depth 1 --init --recursive',
                'Failed to update ESP-IDF submodules')
    run_command('./install.sh esp32 > /dev/null 2>&1',
                'Failed to run ESP-IDF install script')
  end
  run_command("mv #{esp_idf_temp_dir} #{esp_idf_save_directory}",
              'Failed to move ESP-IDF directory')
end

Dir.chdir(esp_idf_save_directory) do
  run_command('./install.sh esp32', 'Failed to run ESP-IDF install script')
end

# --- Clone and Prepare the Yadigar Repository ---
unless Dir.exist?(jade_save_directory)
  run_command("git clone --branch #{jade_git_tag} --single-branch --depth 1 " \
              "#{jade_repo_url} #{jade_save_directory}",
              'Failed to clone Yadigar repository')
  Dir.chdir(jade_save_directory) do
    run_command('git submodule update --depth 1 --init --recursive > /dev/null 2>&1',
                'Failed to update Yadigar submodules')
  end
end

# --- Build the Project ---
def build_project(jade_dir, esp_idf_dir)
  Dir.chdir(jade_dir) do
    jade_version = `git describe --tags`.strip
    FileUtils.cp('configs/sdkconfig_display_ttgo_tdisplay.defaults', 'sdkconfig.defaults')
    run_command("sed -i.bak -e '/CONFIG_DEBUG_MODE/d' -e '1s/^/CONFIG_LOG_DEFAULT_LEVEL_NONE=y\\n/' sdkconfig.defaults",
                'Failed to modify sdkconfig.defaults')
    FileUtils.rm_f('sdkconfig.defaults.bak')
    run_command("bash -c 'source #{File.join(esp_idf_dir, 'export.sh')} && idf.py build'",
                'Failed to build the project')
    jade_version
  end
end

# --- Wait for TTY Device ---
def wait_for_tty(tty_device, chosen_device)
  until File.exist?(tty_device) && begin
    File.stat(tty_device).ftype == 'characterSpecial'
  rescue StandardError
    false
  end
    print "Connect your #{chosen_device} and PRESS ANY KEY to continue... "
    $stdin.getch
    puts
  end
end

# --- Elevate TTY Device Permissions if Needed ---
def elevate_permissions(tty_device, chosen_device)
  permissions = format('%o', File.stat(tty_device).mode & 0o777)
  return unless permissions[-1].to_i < 6

  puts "\nElevating write permissions for #{chosen_device}"
  run_command("sudo chmod o+rw #{tty_device}", 'Failed to change tty device permissions')
  puts
end

# --- Flash the Device ---
def flash_device(esp_idf_dir, jade_dir)
  Dir.chdir(jade_dir) do
    run_command("bash -c 'source #{File.join(esp_idf_dir, 'export.sh')} && idf.py flash'",
                'Failed to flash the device')
  end
end

# --- Prepare Yadigar ---
def prepare_yadigar(jade_dir, esp_idf_dir, tty_device, chosen_device)
  jade_version = build_project(jade_dir, esp_idf_dir)
  if ENV['CI'] == 'true'
    puts 'Exiting the script for CI runners.'
    exit 0
  end
  wait_for_tty(tty_device, chosen_device)
  elevate_permissions(tty_device, chosen_device)
  flash_device(esp_idf_dir, jade_dir)
  puts "\nSUCCESS! Yadigar #{jade_version} is now installed on your #{chosen_device}."
  puts 'You can close this window.'
end

prepare_yadigar(jade_save_directory, esp_idf_save_directory, tty_device, chosen_device)
