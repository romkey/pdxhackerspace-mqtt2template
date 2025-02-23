FROM ruby:3.4

# Set working directory
WORKDIR /app

# Install required gems
COPY Gemfile ./
RUN bundle install

# Copy application files
COPY mqtt2template.rb .

# Run the script
CMD ["ruby", "mqtt2template.rb"]
