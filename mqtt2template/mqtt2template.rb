require 'json'
require 'mqtt'
require 'erb'
require 'optparse'

# Parse command-line arguments for verbose mode
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: mqtt_processor.rb [options]"

  opts.on("-v", "--verbose", "Enable verbose logging") do
    options[:verbose] = true
  end
end.parse!

# Load configuration from /config/config.json
CONFIG_FILE = '/config/config.json'

unless File.exist?(CONFIG_FILE)
  abort("Error: Configuration file '#{CONFIG_FILE}' not found.")
end

config = JSON.parse(File.read(CONFIG_FILE))

# Determine verbosity from config.json or CLI option
VERBOSE = options[:verbose] || config.fetch('verbose', false)

# Print a message if verbosity is enabled (with immediate flush)
def log(message)
  if VERBOSE
    puts message
    $stdout.flush  # Ensure logs are flushed immediately
  end
end

# Ensure MQTT broker URL is set
MQTT_BROKER_URL = config['mqtt_broker_url']
if MQTT_BROKER_URL.nil? || MQTT_BROKER_URL.empty?
  abort('Error: MQTT broker URL is not defined in config.json')
end

# Read topic-template mappings
TOPIC_CONFIG = config['topics']
if TOPIC_CONFIG.nil? || TOPIC_CONFIG.empty?
  abort('Error: No topics defined in config.json')
end

# Load templates and track modification timestamps
TEMPLATES = {}
OUTPUT_FILES = {}
TEMPLATE_MTIMES = {}

def load_template(topic, template_file)
  if File.exist?(template_file)
    TEMPLATES[topic] = ERB.new(File.read(template_file))
    TEMPLATE_MTIMES[topic] = File.mtime(template_file)
    log "Loaded template: #{template_file}"
  else
    abort("Error: Template file '#{template_file}' not found.")
  end
end

TOPIC_CONFIG.each do |topic, settings|
  template_file = settings['template']
  output_file = settings['output']

  OUTPUT_FILES[topic] = output_file
  load_template(topic, template_file)
end

# MQTT Connection
log "Connecting to MQTT broker at #{MQTT_BROKER_URL}..."
MQTT::Client.connect(MQTT_BROKER_URL) do |client|
  log "Subscribed to topics: #{TEMPLATES.keys.join(', ')}"
  client.subscribe(*TEMPLATES.keys)

  client.get do |topic, message|
    log "Received message on topic '#{topic}': #{message}"  # Log full MQTT message

    if TEMPLATES.key?(topic)
      template_file = TOPIC_CONFIG[topic]['template']

      # Check if the template file has changed
      if File.exist?(template_file) && File.mtime(template_file) > TEMPLATE_MTIMES[topic]
        log "Template for topic '#{topic}' has changed, reloading..."
        load_template(topic, template_file)
      end

      begin
        data = JSON.parse(message)
      rescue JSON::ParserError => e
        puts "Error: Failed to parse JSON for topic '#{topic}': #{e.message}"
        $stdout.flush
        next
      end

      begin
        output = TEMPLATES[topic].result_with_hash(data)

        # Write output to the specified file
        File.write(OUTPUT_FILES[topic], output)
        log "Generated file for topic '#{topic}': #{OUTPUT_FILES[topic]}"
      rescue StandardError => e
        puts "Error processing template for topic '#{topic}': #{e.message}"
        $stdout.flush
      end
    else
      log "Received message for unhandled topic: #{topic}"
    end
  end
end
