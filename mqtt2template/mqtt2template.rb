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
if config['mqtt_broker_url'].nil? || config['mqtt_broker_url'].empty?
  abort('Error: MQTT broker URL is not defined in config.json')
end

# Read topic-template mappings
TOPIC_CONFIG = config['topics']
if TOPIC_CONFIG.nil? || TOPIC_CONFIG.empty?
  abort('Error: No topics defined in config.json')
end

# Load templates and track modification timestamps
# Structure: TEMPLATES[topic] = [{template: erb_template, file: template_path, output: output_path, mtime: timestamp}, ...]
TEMPLATES = {}

def load_template(topic, template_file, output_file)
  if File.exist?(template_file)
    template_obj = {
      template: ERB.new(File.read(template_file)),
      file: template_file,
      output: output_file,
      mtime: File.mtime(template_file)
    }
    
    TEMPLATES[topic] ||= []
    TEMPLATES[topic] << template_obj
    
    log "Loaded template: #{template_file} for topic: #{topic}, output: #{output_file}"
  else
    abort("Error: Template file '#{template_file}' not found.")
  end
end

TOPIC_CONFIG.each do |topic, settings|
  # Initialize the topic array if it doesn't exist
  TEMPLATES[topic] = [] unless TEMPLATES.key?(topic)
  
  # Handle both single template/output and multiple templates/outputs
  if settings.key?('template') && settings.key?('output')
    # Legacy single template format
    template_file = settings['template']
    output_file = settings['output']
    load_template(topic, template_file, output_file)
  elsif settings.key?('templates') && settings['templates'].is_a?(Array)
    # New multi-template format
    settings['templates'].each do |template_config|
      template_file = template_config['template']
      output_file = template_config['output']
      
      if template_file && output_file
        load_template(topic, template_file, output_file)
      else
        puts "Warning: Skipping invalid template configuration for topic '#{topic}'"
      end
    end
  else
    puts "Warning: Invalid configuration for topic '#{topic}'"
  end
end

# Process MQTT message
def process_message(topic, message)
  log "Received message on topic '#{topic}': #{message}"  # Log full MQTT message

  if TEMPLATES.key?(topic) && !TEMPLATES[topic].empty?
    begin
      # Parse the message once for all templates
      data = JSON.parse(message)
    rescue JSON::ParserError => e
      puts "Error: Failed to parse JSON for topic '#{topic}': #{e.message}"
      $stdout.flush
      return
    end

    # Process each template associated with this topic
    TEMPLATES[topic].each_with_index do |template_obj, index|
      template_file = template_obj[:file]
      current_mtime = File.mtime(template_file) rescue nil

      # Check if the template file has changed
      if current_mtime && current_mtime > template_obj[:mtime]
        log "Template for topic '#{topic}' (#{template_file}) has changed, reloading..."
        begin
          template_obj[:template] = ERB.new(File.read(template_file))
          template_obj[:mtime] = current_mtime
        rescue StandardError => e
          puts "Error reloading template '#{template_file}': #{e.message}"
          $stdout.flush
          next # Skip this template and continue with others
        end
      end

      begin
        output = template_obj[:template].result_with_hash(data)

        # Ensure output directory exists
        output_file = template_obj[:output]
        output_dir = File.dirname(output_file)
        
        begin
          Dir.mkdir(output_dir) unless Dir.exist?(output_dir)
        rescue StandardError => e
          puts "Error creating directory '#{output_dir}': #{e.message}"
          $stdout.flush
          next # Skip this template and continue with others
        end

        # Write output to the specified file
        File.write(output_file, output)
        log "Generated file for topic '#{topic}' using template #{index+1}/#{TEMPLATES[topic].size}: #{output_file}"
      rescue StandardError => e
        puts "Error processing template '#{template_file}' for topic '#{topic}': #{e.message}"
        $stdout.flush
      end
    end
  else
    log "Received message for unhandled topic: #{topic}"
  end
end

# MQTT Connection with robust reconnection logic
def connect_mqtt_with_retry(config)
  retries = 0
  max_retries = config.fetch('max_connection_retries', 10)
  delay = config.fetch('retry_delay_seconds', 5)
  backoff_factor = config.fetch('retry_backoff_factor', 1.5)
  mqtt_broker_url = config['mqtt_broker_url']

  loop do
    begin
      log "Connecting to MQTT broker at #{mqtt_broker_url}..."
      client = MQTT::Client.new(mqtt_broker_url)
      client.connect
      
      log "Successfully connected to MQTT broker"
      
      # Only subscribe to topics that have templates configured
      topics_to_subscribe = TEMPLATES.keys.reject { |k| TEMPLATES[k].empty? }
      
      if topics_to_subscribe.empty?
        abort("Error: No valid topics with templates to subscribe to.")
      end
      
      log "Subscribed to topics: #{topics_to_subscribe.join(', ')}"
      client.subscribe(*topics_to_subscribe)
      
      return client
    rescue StandardError => e
      retries += 1
      puts "MQTT connection error: #{e.message}"
      
      if max_retries > 0 && retries > max_retries
        abort("Failed to connect to MQTT broker after #{max_retries} attempts. Giving up.")
      end
      
      puts "Retrying in #{delay.round} seconds... (Attempt #{retries})"
      $stdout.flush
      sleep delay
      delay *= backoff_factor  # Exponential backoff
    end
  end
end

# Main loop with connection monitoring
def main_loop(config)
  client = connect_mqtt_with_retry(config)
  
  # Set up a heartbeat check if the broker supports it
  last_message_time = Time.now
  heartbeat_interval = config.fetch('heartbeat_interval_seconds', 60)
  
  # Only subscribe to topics that have templates configured
  topics_to_subscribe = TEMPLATES.keys.reject { |k| TEMPLATES[k].empty? }
  
  if topics_to_subscribe.empty?
    abort("Error: No valid topics with templates to subscribe to.")
  end
  
  Thread.new do
    loop do
      sleep 10
      
      # Check if we haven't received messages for too long
      if Time.now - last_message_time > heartbeat_interval
        puts "No messages received for #{heartbeat_interval} seconds, reconnecting..."
        $stdout.flush
        
        begin
          client.disconnect
        rescue StandardError => e
          # Just log, don't worry if disconnect fails
          log "Error during disconnect: #{e.message}"
        end
        
        client = connect_mqtt_with_retry(config)
        last_message_time = Time.now
      end
    end
  end
  
  # Main message processing loop
  loop do
    begin
      topic, message = client.get
      last_message_time = Time.now
      process_message(topic, message)
    rescue StandardError => e
      puts "Error in MQTT message processing: #{e.message}"
      $stdout.flush
      
      # Try to reconnect if connection is lost
      if e.is_a?(MQTT::Exception) || e.is_a?(Errno::ECONNRESET) || e.is_a?(Errno::ECONNABORTED)
        puts "Connection issue detected, reconnecting..."
        $stdout.flush
        
        begin
          client.disconnect
        rescue StandardError => disconnect_error
          # Just log, don't worry if disconnect fails
          log "Error during disconnect: #{disconnect_error.message}"
        end
        
        client = connect_mqtt_with_retry
      end
      
      # Brief pause to prevent tight loop in case of persistent errors
      sleep 1
    end
  end
end

# Start the main processing loop
begin
  main_loop(config)
rescue Interrupt
  puts "Interrupt received, shutting down..."
  exit(0)
end

