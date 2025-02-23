require 'json'
require 'rb-inotify'
require 'fileutils'
require 'mini_magick'

CONFIG_PATH = '/config/rotater.json'
OUTPUT_DIR = '/output'

# Ensure output directory exists
FileUtils.mkdir_p(OUTPUT_DIR)

# Load file list
def load_file_list
  if File.exist?(CONFIG_PATH)
    JSON.parse(File.read(CONFIG_PATH))['files']
  else
    puts "Config file not found: #{CONFIG_PATH}"
    exit 1
  end
rescue JSON::ParserError => e
  puts "Error parsing JSON: #{e.message}"
  exit 1
end

# Rotate image by 90 degrees
def rotate_image(file)
  puts "Processing: #{file}"
  begin
    image = MiniMagick::Image.open(file)
    image.rotate "-90"
    output_file = File.join(OUTPUT_DIR, File.basename(file))
    image.write(output_file)
    puts "Rotated image saved to: #{output_file}"
  rescue => e
    puts "Error processing #{file}: #{e.message}"
  end
end

# Watch files for changes
def watch_files(file_list)
  notifier = INotify::Notifier.new

  file_list.each do |file|
    notifier.watch(file, :modify) do
      rotate_image(file)
    end
  end

  puts "Watching files for changes..."
  notifier.run
end

file_list = load_file_list
watch_files(file_list)
