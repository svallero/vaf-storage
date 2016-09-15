#!/usr/bin/ruby

#
# af-create-deps.rb -- by Dario Berzano <dario.berzano@cern.ch>
#
# Creates the dependency file for AliRoot versions. The following environment
# variables are needed:
#
# AF_DEP_URL  => HTTP URL containing the list of AliEn packages for ALICE
# AF_DEP_FILE => destination file on the local filesystem
# AF_PACK_DIR => local AliEn Packman repository
#

require 'net/http'
require 'pp'
require 'optparse'

def get_ali_packages(url, pack_dir)

  if (url.kind_of?(URI::HTTP) === false)
    raise URI::InvalidURIError.new('Invalid URL: only http URLs are supported')
  end

  packages = []

  Net::HTTP.start(url.host, url.port) do |http|

    http.request_get(url.request_uri) do |resp|

      # Generic HTTP error
      if (resp.code.to_i != 200)
        raise Exception.new("Invalid HTTP response: #{resp.code}")
        return false
      end

      resp.body.split("\n").each do |line|

        # 0=>pkg.tar.gz, 1=>type, 2=>rev, 3=>platf, 4=>name, 5=>deps
        ary = line.split(" ")

        # Consider only AliRoot packages
        next unless (ary[1] == 'AliRoot')

        # Get the VO name (like VO_ALICE, for instance)
        vo_name = ary[4].split('@').first

        # Check integrity of line format
        deps = ary[5].split(',')
        dep_root = nil
        dep_geant3 = nil
        deps.each do |d|
          if (d.include?('@ROOT::'))
           dep_root = d
          elsif (d.include?('@GEANT3'))
           dep_geant3 = d
          end
        end
        next unless (dep_root && dep_geant3)

        # Check if package is installed for real
        if (pack_dir &&
          !File.exists?("#{pack_dir}/#{vo_name}/AliRoot/#{ary[2]}/#{ary[2]}"))
          next
        end

        # Push package hash
        packages << {
          :aliroot => ary[4],
          :root    => dep_root,
          :geant3  => dep_geant3,
        }

      end # |line|

    end # |resp|

  end # |http|

  return packages

end

def main

  # Check if envvars are set
  begin
    dep_url = URI(ENV['AF_DEP_URL'])
  rescue URI::InvalidURIError => e
    warn 'Environment variable AF_DEP_URL should be set to a valid URL'
    exit 3
  end

  if ((dep_file = ENV['AF_DEP_FILE']) == nil)
    warn 'Environment variable AF_DEP_FILE should be set to a local filename'
    exit 3
  end

  if ((pack_dir = ENV['AF_PACK_DIR']) == nil)
    warn 'Environment variable AF_PACK_DIR should be set to a local directory'
    exit 3
  end

  # Options
  opts = {
    :checkexists => true,
  }

  # Define and parse options
  OptionParser.new do |op|

    op.on('-h', '--help', 'shows usage') do
      puts op
      exit 4
    end

    op.on('-c', '--[no-]check-exists',
      "include only installed packages (default: #{opts[:checkexists]})") do |v|
      opts[:checkexists] = v
    end

    # Custom banner
    prog = File.basename($0)
    op.banner = "#{prog} -- by Dario Berzano <dario.berzano@cern.ch>\n" +
      "Creates a dependency file for AliRoot packages\n\n" +
      "Usage: #{prog} [options]"

    begin
      op.parse!
    rescue OptionParser::ParseError => e
      warn "#{prog}: arguments error: #{e.message}"
      exit 5
    end

  end

  begin
    packages = get_ali_packages(dep_url, opts[:checkexists] ? pack_dir : nil)

    begin

      File.open(dep_file, 'w') do |f|
        packages.each do |pack|
          f << pack[:aliroot] << '|' << pack[:root] << '|' <<
            pack[:geant3] << "\n"
        end
     end

    rescue Exception => e
      warn "Can not write #{dep_file}: #{e.message}"
      exit 2
    end

  rescue Exception => e
    warn "Error fetching dependencies: #{e.message}"
    exit 1
  end

  warn "#{dep_file} written"
  exit 0

end

#
# Entry point
#

main
