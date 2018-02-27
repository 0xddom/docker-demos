require 'httparty'
require 'json'

class Queues
  def self.crawling_requests
    'crawling_requests'
  end

  def self.threads
    'threads'
  end

  def self.boards
    'boards'
  end

  def self.pruned_threads
    'pruned'
  end
end

class RestQueue
  include HTTParty
  default_options.update(verify: false)
  restmq_hostname = ENV['RESTMQ_HOST'] || 'restmq'
  restmq_port = ENV['RESTMQ_PORT'] || 8888
  base_uri "http://#{restmq_hostname}:#{restmq_port}"

  def dequeue(queue)
    #puts "[#{Time.now}] Reading from queue #{queue}"
    begin
      JSON.parse self.class.get("/q/#{queue}").parsed_response
    rescue
      nil
    end
  end

  def enqueue(queue, val)
   # puts "[#{Time.now}] Pushing #{val} in queue #{queue}"
    self.class.post("/q/#{queue}", query: {value: val })
  end
end
