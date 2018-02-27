# coding: utf-8
require 'neo4j-core'
require 'neo4j/core/cypher_session/adaptors/http'
require 'typhoeus/adapters/faraday'

class Board
  attr_accessor :name
  attr_accessor :nsfw
  attr_accessor :bump_limit
  attr_accessor :image_limit
  attr_accessor :spoilers

  def initialize(name, nsfw, bl, il, sp)
    @name = name
    @nsfw = nsfw
    @bump_limit = bl
    @image_limit = il
    @spoilers = sp
  end

  def nsfw?
    @nsfw
  end

  def spoilers?
    @spoilers
  end
end

class Thread
  attr_accessor :id, :dead, :archived
  
  def initialize(id, dead, archived)
    @id = id
    @dead = dead
    @archived = archived
  end

  def dead?
    dead
  end

  def spoilers?
    spoilers
  end
end

class Image
  attr_accessor :md5

  def initialize(md5)
    @md5 = md5
  end
end

class Tag
  attr_accessor :name

  def initialize(name)
    @name = name
  end
end

class PassYear
  attr_accessor :year

  def initialize(year)
    @year = year
  end
end

class User
  attr_accessor :id

  def initialize(id)
    @id = id
  end
end

class Tripcode
  attr_accessor :code

  def initialize(code)
    @code = code
  end
end

class Country
  attr_accessor :name, :code

  def initialize(name, code)
    @name = name
    @code = code
  end
end

class Post
  attr_accessor :message, :subject, :id, :time, :after_bump_limit, :after_image_limit

  def initialize(message, subject, id, time, after_bl, after_il)
    @message = message
    @subject = subject
    @id = id
    @time = time
    @after_bump_limit = after_bl
    @after_image_limit = after_il
  end

  def self.inflate(node)
    props = node.properties
    Post.new props[:message], props[:subject], props[:id], props[:time], props[:after_bump_limit], props[:after_image_limit]
  end
end

class Entity
  attr_accessor :value, :type

  def initialize(value, type)
    @value = value
    @type = type
  end
end

SPECIAL_USER_IDS = [
  'Mod',
  'Admin',
  'Manager',
  'Developer',
  'Founder'
]

class Neo4jAdaptor
  def initialize
    neo4j_host = ENV['NEO4J_HOST'] || 'neo4j'
    neo4j_port = ENV['NEO4J_PORT'] || 7474
    neo4j_user = ENV['NEO4J_USER'] || 'neo4j'
    neo4j_pass = ENV['NEO4J_PASS'] || '4chan'

    @adaptor = Neo4j::Core::CypherSession::Adaptors::HTTP.new(
      "http://#{neo4j_user}:#{neo4j_pass}@#{neo4j_host}:#{neo4j_port}")
    @session = Neo4j::Core::CypherSession.new @adaptor
    add_4chan_if_not_exists
    add_checker
  end

  def add_checker
    @session.query 'merge (c:Checker)'
  end
  
  def add_board(board)
    #p "Adding board #{board}"
    @session.query('match (s:Site { name: "4chan" }) create (b:Board { name: {name}, nsfw: {nsfw}, bump_limit: {bump_limit}, image_limit: {image_limit}, spoilers: {spoilers}}), (b)-[:IN]->(s)',
                   name: board.name,
                   nsfw: board.nsfw,
                   bump_limit: board.bump_limit,
                   image_limit: board.image_limit,
                   spoilers: board.spoilers)
  end

  def board_exists?(board)
    @session.query('match (b:Board { name: {name} }), (s:Site { name: "4chan" }), (s)<-[:IN]-(b) return b', name: board.name).rows.length != 0
  end

  def get_board(name)
    results = @session.query('match (b:Board { name: {name} }), (s:Site { name: "4chan" }), (b)-[:IN]->(s) return b', name: name)
    if results.rows.length == 0
      nil
    else
      results.rows[0]
    end
  end

  def thread_exists?(board, thread_no)
    @session.query('match (t:Thread { id: {thread_id} }),
 (b:Board { name: {name} }),
 (s:Site { name: "4chan" }),
 (t)-[:IN]->(b)-[:IN]->(s) return t', thread_id: thread_no.to_s, name: board).rows.length != 0
  end
  
  def add_thread_unless_found(board, thread_no)
    unless thread_exists? board, thread_no
      @session.query('match (b:Board { name: {name} }), (s:Site { name: "4chan" }), (b)-[:IN]->(s)
create (t:Thread { id: {thread_id}, dead: false, archived: false }), (t)-[:IN]->(b)',
                     name: board, thread_id: thread_no.to_s)
    end
  end

  def add_4chan_if_not_exists
    results = @session.query 'match (s:Site { name: "4chan" }) return s'
    if results.rows.length == 0
      puts "Inserted 4chan site in graph"
      @session.query 'create (s:Site { name: "4chan" })'
    end
  end

  def post_exists?(board, thread_no, post_no)
    @session.query('match (s:Site { name: "4chan" }), (b:Board { name: {name} }), 
(t:Thread { id: {thread_id} }), (p:Post { id: {post_id} }), 
(s)<-[:IN]-(b)<-[:IN]-(t)<-[:POSTED]-(p) return p',
                   name: board, thread_id: thread_no.to_s, post_id: post_no).rows.length != 0
  end

  # XXX This method needs a refactor
  def insert_post_info_if_new(board, thread_no, post, image, tripcode, passyear, user, country, tag)
    # Insert the post object. If exists, ignore and return.
    if post_exists? board, thread_no, post.id
      #puts "Post exists. Ignoring..."
      return
    end

    #puts "Add post #{board}/#{thread_no}/#{post.id}"

    @session.query('match (s:Site { name: "4chan" })<-[:IN]-(b:Board { name: {name} })<-[:IN]- 
(t:Thread { id: {thread_id} }) 
create
(p:Post{ id: {post_id}, message: {message}, subject: {subject}, time: {time}, 
after_bump_limit: {after_bump_limit}, after_image_limit: {after_image_limit} }), (p)-[:POSTED]->(t)',
                   name: board,
                   thread_id: thread_no.to_s,
                   post_id: post.id,
                   message: post.message,
                   subject: post.subject,
                   time: post.time,
                   after_bump_limit: post.after_bump_limit,
                   after_image_limit: post.after_image_limit
                  )
    base_query = 'match (s:Site { name: "4chan" }), (b:Board { name: {name} }), 
(t:Thread {id: {thread_id} }), (p:Post { id: {post_id} }), (s)<-[:IN]-(b)<-[:IN]-(t)<-[:POSTED]-(p)'
    
    # If the image isnt nil, search. If exists, connect, else, create and connect
    if image
      image_exists = @session.query("match (i:Image { md5: {md5} }) return i",
                                    md5: image.md5).rows.length != 0
      if image_exists
        @session.query("#{base_query}, (i:Image { md5: {md5} }) create (i)<-[:WITH]-(p)",
                       name: board,
                       thread_id: thread_no.to_s,
                       post_id: post.id,
                       md5: image.md5)
      else
        @session.query("#{base_query} create (i:Image { md5: {md5} }), (i)<-[:WITH]-(p)",
                       name: board,
                       thread_id: thread_no.to_s,
                       post_id: post.id,
                       md5: image.md5)
      end
    end

    # If the tripcode isnt nil, search. If exists, connect, else, create and connect
    if tripcode
      tripcode_exists = @session.query("match (trip:Tripcode { code: {code} }) return trip",
                                       code: tripcode.code).rows.length != 0

      if tripcode_exists
        @session.query("#{base_query}, (trip:Tripcode { code: {code} }) 
create (p)-[:HAS]->(trip)",
                       name: board,
                       thread_id: thread_no.to_s,
                       post_id: post.id,
                       code: tripcode.code)
      else
        @session.query("#{base_query} create (trip:Tripcode { code: {code} }), (p)-[:HAS]->(trip)",
                       name: board,
                       thread_id: thread_no.to_s,
                       post_id: post.id,
                       code: tripcode.code)
      end
    end
    
    # If the passyear isnt nil, search. If exists, connect, else, create and connect
    if passyear
      passyear_exists = @session.query("match (year:PassYear { year: {year} }) return year",
                                       year: passyear.year).rows.length != 0

      if passyear_exists
        @session.query("#{base_query}, (year:PassYear { year: {year} }) create 
(p)-[:BOUGHT]->(year)",
                       name: board,
                       thread_id: thread_no,
                       post_id: post.id,
                       year: passyear.year)
      else
        @session.query("#{base_query} create (year:PassYear { year: {year} }), 
(p)-[:BOUGHT]->(year)",
                       name: board,
                       thread_id: thread_no.to_s,
                       post_id: post.id,
                       year: passyear.year)
      end
    end
    
    # If the user isnt nil, If is a special user, search. If exists, connect, else create and connect. If is a normal user. Search inside the thread, if exists, connect, else create and connect.
    if user
      if SPECIAL_USER_IDS.include? user.id
        special_user_exists = @session.query(
          "match (user:User { id: {user_id} }) return user",
          user_id: user.id
        ).rows.length != 0

        begin
          if special_user_exists
            @session.query("#{base_query}, (user:User { id: {user_id} }) 
create (user)-[:POSTED]->(p)",
              name: board,
              thread_id: thread_no.to_s,
              post_id: post.id,
              user_id: user.id
            ) 
          else
            @session.query("#{base_query} create (user:User { id: {user_id} }), 
 (user)-[:POSTED]->(p)",
              name: board,
              thread_id: thread_no.to_s,
              post_id: post.id,
              user_id: user.id
                          )
          end
        end
      else
        user_exists = @session.query(
          "#{base_query}, (user:User { id: {user_id} }), (user)-[:IN]->(t) return user",
              name: board,
              thread_id: thread_no.to_s,
              post_id: post.id,
              user_id: user.id
        ).rows.length != 0

        begin
          if user_exists
            @session.query("#{base_query}, (user:User { id: {user_id} }) 
create (user)-[:POSTED]->(p)",
              name: board,
              thread_id: thread_no.to_s,
              post_id: post.id,
              user_id: user.id
            ) 
          else
            @session.query("#{base_query} create (user:User { id: {user_id} }), 
 (user)-[:POSTED]->(p), (user)-[:IN]->(t)",
              name: board,
              thread_id: thread_no.to_s,
              post_id: post.id,
              user_id: user.id
                          )
          end
        end
        
        # If the country isnt nil, search. If exists, connect, else, create and connect
        if country
          country_exists = @session.query("match 
(country:Country { name: {country_name}, code: {country_code} }) return country",
                                          country_name: country.name,
                                          country_code: country.code).rows.length != 0

          if country_exists
            already_connected = @session.query("#{base_query}, (user:User { id: {user_id} }),
(country:Country { name: {country_name}, code: {country_code} }), (user)-[:LIVES]->(country), (user)-[:IN]->(t) return user",
                           name: board,
                           thread_id: thread_no.to_s,
                           post_id: post.id,
                           user_id: user.id,
                           country_name: country.name,
                           country_code: country.code).rows.length != 0

            @session.query("#{base_query}, (user:User { id: {user_id} }),
(country:Country { name: {country_name}, code: {country_code} }), (user)-[:IN]->(t) create 
(user)-[:LIVES]->(country)",
                           name: board,
                           thread_id: thread_no.to_s,
                           post_id: post.id,
                           user_id: user.id,
                           country_name: country.name,
                           country_code: country.code) unless already_connected
          else
            @session.query("#{base_query}, (user:User { id: {user_id} }), (user)-[:IN]->(t) create
(country:Country { name: {country_name}, code: {country_code} }),
(user)-[:LIVES]->(country)",
                           name: board,
                           thread_id: thread_no.to_s,
                           post_id: post.id,
                           user_id: user.id,
                           country_name: country.name,
                           country_code: country.code)
          end
        end
      end
    end
         
    # If the tag isnt nil, search. If exists, connect, else, create and connect
    if tag
      tag_exists = @session.query("match (tag:Tag { name: {tag_name} }) return tag",
                                       tag_name: tag.name).rows.length != 0
      begin
      if tag_exists
        @session.query("#{base_query}, (tag:Tag { name: {tag_name} }) create 
(p)-[:TAGGED]->(tag)",
                       name: board,
                       thread_id: thread_no.to_s,
                       post_id: post.id,
                       tag_name: tag.name)
      else
        @session.query("#{base_query} create (tag:Tag { name: {tag_name} }), 
(p)-[:TAGGED]->(tag)",
                       name: board,
                       thread_id: thread_no.to_s,
                       post_id: post.id,
                       tag_name: tag.name)
      end
      end
    end
  end

         def get_unmarked_posts(size)
           @session.query 'match (c:Checker), (p:Post) where not (c)-[:CHECKED]->(p) 
return p limit {size}', size: size
         end

         def relate_url(post_id, url, domain)
           # Create url and domain if not exists
           @session.query 'match (p:Post { id: {post_id} }) 
merge (p)-[:FOUND]->(u:URL { value: {url} })-[:IN]->(d:Domain { name: {domain} }))',
                          url: url, post_id: post_id, domain: domain
         end

         def relate_entity(post_id, entity)
           # @session.query 'merge (:Entity { value: {entity_value}, type: {entity_type} })',
           #               entity_value: entity.value, entity_type: entity.type
           @session.query 'match (p:Post { id: {post_id} }) 
merge (p)-[:FOUND]->(:Entity { value: {entity_value}, type: {entity_type} })',
                          entity_value: entity.value, entity_type: entity.type, post_id: post_id
         end

         def relate_reply(from, to)
           @session.query 'match (from:Post { id: {from_id} }), (to:Post { id: {to_id}}) 
where (from)-[:POSTED]->(:Thread)<-[:POSTED]-(to)
merge (from)-[:REPLY]->(to)', from_id: from, to_id: to
         end

         def mark_post(post_id)
           @session.query 'match (p:Post { id: {post_id} }), (c:Checker) 
create (p)<-[:CHECKED]-(c)', post_id: post_id
         end
end
