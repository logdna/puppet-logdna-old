require 'puppet'
require 'yaml'

begin
  require 'httparty'
rescue LoadError => e
  Puppet.emerg "You need the `httparty` gem to send reports to LogDNA"
end

Puppet::Reports.register_report(:logdna) do

  configfile = File.join([File.dirname(Puppet.settings[:config]), "logdna.yaml"])
  raise(Puppet::ParseError, "LogDNA report config file #{configfile} not readable") unless File.exist?(configfile)
  config = YAML.load_file(configfile)
  API_KEY = config[:logdna_api_key]

  desc <<-DESC
  Send notification of metrics to LogDNA
  DESC

  def process
    messages = Array.new
    files = Array.new
    repos = Array.new
    seen = Array.new
    messages.push({
        :message => "#{self.host} has status #{self.status}",
        :node => "#{self.host}"
    })
    self.metrics.each { |metric, data|
      data.values.each { |val|
        name = "puppet.#{val[1].gsub(/ /, '_')}.#{metric}".downcase
        value = val[2]
        messages.push({
            :message => "#{name} -- " + " Value: " + value.to_s,
            :node => "#{self.host}"
        })
      }
    }
    self.logs.each { |log|
        source = log.source
        messages.push({
            :message => log.message,
            :node => source
        })
        if !log.file.nil?
            if (!seen.include? log.file)
                File.open(log.file, "rb") do |f|
                    files.push(f.read)
                end
                seen.push(log.file);
            end
        end
    }


    files.each { |file|
        chunks = file.split(' ')
        num_nodes = -1;
        chunks.each_with_index { |val, index|
            if (val == "node")
                num_nodes += 1
                repos.push({
                    :node => chunks[index + 1],
                    :repos => []
                })
            end
            if (val.split(//).last(5).join == ".git\"")
                repos[num_nodes][:repos].push(val)
            end
        }
    }


    HTTParty.post("https://logs.logdna.com/webhooks/puppet", {
        :body => { "messages" => messages, "repos" => repos }.to_json,
        :basic_auth => { :username => API_KEY },
        :headers => { "Content-Type" => "application/json", "Accept" => "application/json"}
    })
  end
end
