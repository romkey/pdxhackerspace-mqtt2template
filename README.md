# mqtt2template

We use this program to help us generate HTML dashboards from Home Assistant.

Home Assistant reasonably tries very hard to restrict automations from writing files. While there are ways to circumvent its restrictions, just building an external service for generating the web sites we wanted felt like a simpler, more maintainable solution.

mqtt2template listens on a set of MQTT topics. Each topic has an [ERB](https://github.com/ruby/erb)  template associated with it. When it receives a message on the topic it attempts to parse it as JSON and renders the template passing the data to it.

PDX Hackerspace currently uses this to generate a dashboard of snapshots from its external security cameras, enabling members on site to easily see what's going on outside, and to provide a dashboard that shows the current status of our 3D printers, which members can check both on and off-site.

This repo includes two other services:
- rotater - watches for JPG or PNG files to change and then rotates the images in them by -90 degrees
- nginx - serves the web sites generated by the templates and MQTT messages

Our printer cameras provide images that are unpleasantly rotated. While we could rotate them on the dashboard using CSS this makes positioning extremely difficult and doesn't work with Bootstrap. rotater was a very easy solution to the problem.

## Installation

mqtt2template is containerized using Docker. It's intended to be run as a [Hackstack](https://github.com/romkey/pdxhackerspace-hackstack)  application and fits easily into the stack.

To run it as part of Hackstack just cd to its directory, configure it and run
```
docker compose up
```
Hackstack will need to be already installed.

## Configuration

### mqtt2template

1. Copy `config/config.json.example` to `config/config.json`
2. Create an account for mqtt2template on your MQTT broker. If you're using Hackstack's bundled Mosquitto instance, do this:
```
cd ../mosquitto
bin/mkuser.sh mqtt2template
cd ../mqtt2template
```
3. Copy the MQTT url (should be output from the above script) into `config/config.json` as `mqtt_broker_url`
4. Set up the templates you want to use. You can see examples in `config/config.json`
5. Make sure that the generated web sites are on Docker volumes that make them available to NGINX to serve. The stock `docker-compose.yml` file has this set up for CTRLH's use.

### rotater

If you need to rotate any snapshots before displaying them, edit `config/rotater.json` to list them. Currently all images are rotated by -90 degrees.

### nginx

If you need to serve any of the output as a website (this is PDX Hackerspace's use case) you'll want to configure nginx to serve the sites. Top level nginx configuration is loaded from `config/nginx/nginx.conf` and individual sites are loaded from `config/nginx/sites`. We use very simple configurations with different port numbers. The example files show our setup. 

### Home Assistant

Our Home Assistant instance is configured to talk to each of our printers via PrusaLink, and is also configured with printer monitors running firmware generated by ESPHome.

We run an automation once per minute which grabs snapshots of the printers' cameras and publishes the current state of the printers to our MQTT broker.
```
alias: 3D Printers - Update mqtt2template
description: ""
triggers:
  - trigger: time_pattern
    hours: "*"
    minutes: "*"
    seconds: "30"
conditions: []
actions:
  - action: camera.snapshot
    metadata: {}
    data:
      filename: /config/websites/printers/prusa-1.jpg
    target:
      entity_id:
        - camera.prusa1_monitor_my_camera
  - action: camera.snapshot
    metadata: {}
    data:
      filename: /config/websites/printers/prusa-3.jpg
    target:
      entity_id:
        - camera.printer_monitor_mk4_my_camera
  - action: mqtt.publish
    metadata: {}
    data:
      qos: 0
      retain: false
      topic: mqtt2template/printers
      payload: |-
        { "prusa1": {
              "available": {{ (states('sensor.prusa_1')  not in ['unknown', 'unavailable', 'none']) | tojson }},
              "filename": {{ states('sensor.prusa_1_filename')|tojson }},
              "state": {{ states('sensor.prusa_1')|tojson }},
              "material": {{ states('sensor.prusa_1_material')|tojson }},
              "nozzle": {{ states('sensor.prusa_1_nozzle_diameter')|float(0)|tojson }},
              "progress": {{ states('sensor.prusa_1_progress')|float(0)|tojson }},
              "finish": {{ states('sensor.prusa_1_print_finish')|tojson }},
              "seconds_until_completion": {{ (as_timestamp(states('sensor.prusa_1_print_finish')) - as_timestamp(now())) | int if states('sensor.prusa_1_print_finish') not in ['unknown', 'unavailable', 'none'] else 0 }},
              "temperatures": {
                "nozzle": {{ states('sensor.prusa_1_nozzle_temperature')|tojson }},
                "bed": {{ states('sensor.prusa_1_heatbed_temperature')|tojson }},
                "enclosure": {{ states('sensor.printer_monitor_mk4_bme680_temperature')|tojson }},
                "ambient": {{ states('sensor.indoor_temperature')|tojson }}
                }
              },
          "prusa2": {
              "available": {{ (states('sensor.prusa_2')  not in ['unknown', 'unavailable', 'none']) | tojson }},
              "filename": {{ states('sensor.prusa_2_filename')|tojson }},
              "state": {{ states('sensor.prusa_2')|tojson }},
              "material": {{ states('sensor.prusa_2_material')|tojson }},
              "nozzle": {{ states('sensor.prusa_2_nozzle_diameter')|float(0)|tojson }},
              "progress": {{ states('sensor.prusa_2_progress')|float(0)|tojson }},
              "seconds_until_completion": {{ (as_timestamp(states('sensor.prusa_2_print_finish')) - as_timestamp(now())) | int if states('sensor.prusa_2_print_finish') not in ['unknown', 'unavailable', 'none'] else 0 }},
              "temperatures": {
                "nozzle": {{ states('sensor.prusa_2_nozzle_temperature')|tojson }},
                "bed": {{ states('sensor.prusa_2_heatbed_temperature')|tojson }},
                "enclosure": {{ 0|tojson }},
                "ambient": {{ states('sensor.indoor_temperature')|tojson }}
                }
              },
          "prusa3": {
              "available": {{ (states('sensor.prusa_3')  not in ['unknown', 'unavailable', 'none']) | tojson }},
              "filename": {{ states('sensor.prusa_3_filename')|tojson }},
              "state": {{ states('sensor.prusa_3')|tojson }},
              "material": {{ states('sensor.prusa_3_material')|tojson }},
              "nozzle": {{ states('sensor.prusa_3_nozzle_diameter')|float(0)|tojson }},
              "progress": {{ states('sensor.prusa_3_progress')|float(0)|tojson }},
              "seconds_until_completion": {{ (as_timestamp(states('sensor.prusa_3_print_finish')) - as_timestamp(now())) | int if states('sensor.prusa_3_print_finish') not in ['unknown', 'unavailable', 'none'] else 0 }},
              "temperatures": {
                "nozzle": {{ states('sensor.prusa_3_nozzle_temperature')|tojson }},
                "bed": {{ states('sensor.prusa_3_heatbed_temperature')|tojson }},
                "enclosure": {{ states('sensor.printer_monitor_mk4_bme680_temperature')|tojson }},
                "ambient": {{ states('sensor.indoor_temperature')|tojson }}
                }
              },
          "prusaxl": {
              "available": {{ (states('sensor.prusa_xl')  not in ['unknown', 'unavailable', 'none']) | tojson }},
              "filename": {{ states('sensor.prusa_xl_filename')|tojson }},
              "state": {{ states('sensor.prusa_xl')|tojson }},
              "material": {{ states('sensor.prusa_xl_material')|tojson }},
              "nozzle": {{ states('sensor.prusa_xl_nozzle_diameter')|float(0)|tojson }},
              "progress": {{ states('sensor.prusa_xl_progress')|float(0)|tojson }},
              "seconds_until_completion": {{ (as_timestamp(states('sensor.prusa_xl_print_finish')) - as_timestamp(now())) | int if states('sensor.prusa_xl_print_finish') not in ['unknown', 'unavailable', 'none'] else 0 }},
              "temperatures": {
                "nozzle": {{ states('sensor.prusa_xl_nozzle_temperature')|tojson }},
                "bed": {{ states('sensor.prusa_xl_heatbed_temperature')|tojson }},
                "enclosure": {{ 0|tojson }},
                "ambient": {{ states('sensor.co2_ball_electronics_lab_bme680_temperature')|tojson }}
                }
              }
          }
mode: single
```

### Reverse Proxy

Hackstack uses nginx proxy manager as a reverse proxy for web sites. If you're using Hackstack you'll need to go to nginx proxy manager's dashboard and create a proxy for each site you want to serve. 

## Implementation Details

mqtt2template and rotater are both written in Ruby. ChatGPT wrote 95% of the code.

Templates use ERB.

Styling is done using Bootstrap 5.

The bundlded templates use [Lightbox for Bootstrap 5](https://trvswgnr.github.io/bs5-lightbox/) to display images.

## Debugging

`docker compose logs -f -t` to see logging output from the services.

Make sure `verbose` is set to `true` in `config/config.json`

## License

The entire project is released under the [MIT License](LICENSE).
