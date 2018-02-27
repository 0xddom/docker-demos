require 'graph'
require 'nokogiri'
require 'stanford'
require 'slf4j'
require 'uri'

class Findings
  attr_accessor :urls, :entities, :replies

  def reset
    @urls = 0
    @entities = 0
    @replies = 0
  end

  def inc(what)
    case what
    when :urls
      @urls = @urls + 1
    when :entities
      @entities = @entities + 1
    when :replies
      @replies = @replies + 1
    end
  end

  def report
    "[Findings] URLs: #{@urls} | Entities: #{@entities} | Replies: #{@replies}"
  end
end

class AnalysisMode

  def initialize(args)
    @neo4j = Neo4jAdaptor.new
    @batch_size = 200
    @classifier = Stanford.create_classifier
    @findings = Findings.new
  end
 
  def run
    each 2 do
      posts = get_posts
      @findings.reset
      puts "Processing #{posts.length} posts" if posts.length != 0
      posts.each do |post|
        process_post post
      end
      puts @findings.report if posts.length != 0
    end
  end

  def process_post(post)
    msg = post.message
    if msg
      extract_replies post.id, msg
      extract_entities post, msg
      extract_urls post, msg
    end
    mark_post post
  end

  def extract_urls(post, msg)
    URI.extract(msg).each do |match|
      host = match.scan(URI.regexp)[0][2]
      relate_url post.id, match, host if host
    end
  end

  def relate_url post, match, host
    @findings.inc :urls
    @neo4j.relate_url post.id, match, host
  end
  
  def mark_post(post)
    @neo4j.mark_post post.id
  end
  
  def extract_entities(post, msg)
    entities = @classifier.process clean_post msg
    entities.each do |entity|
      @findings.inc :entities
      @neo4j.relate_entity post.id, entity
    end
  end

  def clean_post(msg)
    Nokogiri::HTML(msg).to_html.
      gsub(/\<a.*\>.*\<\/a\>/, '').
      gsub('<br>', "\n").
      gsub(/\<.*\>/, '').
      gsub(/\<\/.*\>/, '').
      chomp('').strip
  end
  
  def extract_replies(post_id, msg)
    html_msg = Nokogiri::HTML msg
    links = get_a_tags html_msg
    links.map do |link|
      link.children.to_s
    end.map do |reply|
      reply.gsub('&gt;', '').to_i
    end.each do |reply_id|
      connect_threads post_id, reply_id
    end
  end

  def connect_threads(from, to)
    @findings.inc :replies
    @neo4j.relate_reply from, to
  end

  def get_a_tags(html)
    return html.css('a.quotelink')
  end
  
  def each(n)
    while true
      yield
      sleep n
    end
  end

  def get_posts
    @neo4j.get_unmarked_posts(@batch_size).rows.map do |post|
      Post.inflate post[0]
    end
  end
end
